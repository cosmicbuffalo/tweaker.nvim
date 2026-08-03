--- Editing behavior for the float: fixed-width fg/bg fields, live apply, link
--- unlink/restore, the <C-t> link-target toggle, and RGB stepping.
local util = require("tweaker.util")
local ui = require("tweaker.ui")
local overrides = require("tweaker.overrides")
local log = require("tweaker.log")

local M = {}

local W = ui.FIELD_W -- fixed field width
local LINE_LEN = ui.LINE_LEN -- two fields, no separators

--- Split a (possibly mid-edit) data line into its two fields and rebuild it at
--- fixed width. Exactly one field (the one being edited) absorbed the length
--- delta; the other kept width W.
---@return string newline, string fg, string bg
local function split(line, field)
    local fg_raw, bg_raw
    if field == 1 then
        fg_raw = line:sub(1, math.max(0, #line - W))
        bg_raw = line:sub(math.max(1, #line - W + 1))
    else
        fg_raw = line:sub(1, W)
        bg_raw = line:sub(W + 1)
    end
    local fg = ui.trim(fg_raw):sub(1, W)
    local bg = ui.trim(bg_raw):sub(1, W)
    return ui.padr(fg, W) .. ui.padr(bg, W), fg, bg
end

--- The group a row's edits target: normally the row's own group, or — when the
--- row has been toggled with <C-t> — the group it links to.
local function active_group(desc)
    if desc.editing_target and desc.link and desc.link ~= "" then
        return desc.link
    end
    return desc.group
end

--- Record the row's fg/bg as an override (which applies it live, breaking any
--- link). Each cell: "#rrggbb" -> that color; NONE -> cleared; blank/partial ->
--- keep the group's own value. Only records when a cell holds a *deliberate*
--- value (a color or NONE), so a linked group isn't unlinked just by opening it
--- or typing a partial value. Edits target the row's active group (its own, or
--- the linked-to group when toggled), so tweaking a link target changes it
--- directly rather than unlinking the group under the cursor.
local function apply(s, lnum, fg_raw, bg_raw)
    local desc = s.rows and s.rows[lnum]
    if not desc or not desc.group or desc.group == "" then
        return
    end
    local group = active_group(desc)
    local own = util.own(group)
    local own_fg = not own.link and own.fg or nil
    local own_bg = not own.link and own.bg or nil
    local function cell(raw, ownv)
        if raw == "" then
            return nil, false -- blank -> no color, not deliberate
        end
        local c = util.parse_color(raw)
        if c == "NONE" then
            return nil, true -- deliberate clear
        elseif c then
            return c, true -- deliberate color
        end
        return util.hex(ownv), false -- invalid/partial -> keep own value
    end
    local fg, fg_set = cell(fg_raw, own_fg)
    local bg, bg_set = cell(bg_raw, own_bg)
    if log.enabled() then
        log.write(
            string.format(
                "apply lnum=%d group=%s target=%s fg=%q bg=%q fg_set=%s bg_set=%s has=%s has_base=%s orig=%s link=%s",
                lnum,
                group,
                tostring(desc.editing_target),
                fg_raw,
                bg_raw,
                tostring(fg_set),
                tostring(bg_set),
                tostring(overrides.has(group)),
                tostring(overrides.has_base(group)),
                (vim.inspect(desc.orig):gsub("%s+", " ")),
                tostring(desc.link)
            )
        )
    end
    if fg_set or bg_set then
        overrides.set(group, fg, bg, desc.orig)
        return false
    end
    -- Nothing deliberate. If both cells are now empty and this group has a live
    -- override that we know how to revert (its open-time definition, or the link
    -- the override remembered), clearing the cells restores the original link.
    local relinked = false
    if not desc.editing_target and fg_raw == "" and bg_raw == "" and overrides.has(group) then
        if desc.orig ~= nil then
            if log.enabled() then
                log.write("  -> restore via desc.orig " .. (vim.inspect(desc.orig):gsub("%s+", " ")))
            end
            overrides.clear(group, desc.orig)
        elseif overrides.has_base(group) then
            log.write("  -> restore via base")
            local base = overrides.clear(group)
            if not desc.link and base and base.link then
                desc.link = base.link -- reopened concrete row: show it as a link again
                relinked = true -- the GROUP column just widened; caller must relayout
            end
        else
            log.write("  -> no restore source (orig nil, no base)")
        end
    end
    -- otherwise leave the group (and any link) untouched
    return relinked
end

--- Common context for a change on the current line, or nil if it should be
--- ignored.
---@return table? s, integer? win, integer? lnum, integer? field
local function ctx(buf)
    local s = ui.get_session(buf)
    if not s or not s.editable then
        return
    end
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) ~= buf then
        return
    end
    local pos = vim.api.nvim_win_get_cursor(win)
    if pos[1] < s.first or pos[1] > s.last then
        return
    end
    -- Trust s.field only while actually in insert; otherwise derive from cursor
    -- (s.field may be stale if insert was left via <C-c>, which skips InsertLeave).
    local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
    local field = (insert and s.field) or (pos[2] < W and 1 or 2)
    return s, win, pos[1], field
end

--- Insert-mode change: keep the edited field at fixed width by adjusting only
--- the trailing padding at that field's end (so BG/PRIORITY never shift), then
--- re-render and apply live. The trailing edit is away from the cursor, so the
--- cursor and the insert are undisturbed.
local function live(buf)
    local s, _, lnum, field = ctx(buf)
    if not s or s.adjusting then
        if log.enabled() then
            log.write("live bail: s=" .. tostring(s ~= nil) .. " adjusting=" .. tostring(s and s.adjusting))
        end
        return
    end
    if s.suppress then
        log.write("live bail: suppress")
        s.suppress = false
        return
    end
    local row = lnum - 1
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local delta = #line - LINE_LEN
    if delta ~= 0 then
        local fend = (field == 1 and 0 or W) + W -- byte where this field should end
        s.adjusting = true
        if delta > 0 then
            -- Inserted: drop `delta` chars at the field's end (padding/overflow).
            local from = math.min(fend, #line)
            local to = math.min(fend + delta, #line)
            pcall(vim.api.nvim_buf_set_text, buf, row, from, row, to, {})
        else
            -- Deleted: add back `-delta` padding spaces at the field's end.
            local at = math.min(math.max(0, fend + delta), #line)
            pcall(vim.api.nvim_buf_set_text, buf, row, at, row, at, { string.rep(" ", -delta) })
        end
        s.adjusting = false
    end
    local cur = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local _, fg, bg = split(cur, field)
    local relinked = apply(s, lnum, fg, bg)
    if relinked then
        ui.relayout(buf) -- link reappeared: widen/realign columns + window
    else
        ui.rerender(buf) -- after apply so the group swatch reflects the new/restored color
    end
end

--- Normal-mode change / InsertLeave: normalize the line back to fixed width
--- (only if it changed), keep the cursor inside its field, re-render, apply.
local function settle(buf)
    local s, win, lnum, field = ctx(buf)
    if not s then
        return
    end
    if s.suppress then
        s.suppress = false
        return
    end
    -- Guard against stray rows (e.g. a multiline paste): keep the fixed count.
    if vim.api.nvim_buf_line_count(buf) > s.last then
        s.adjusting = true
        pcall(vim.api.nvim_buf_set_lines, buf, s.last, -1, false, {})
        s.adjusting = false
    end
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local newline, fg, bg = split(line, field)
    if line ~= newline then
        vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { newline })
        local fstart = field == 1 and 0 or W
        local val = field == 1 and fg or bg
        local col = math.min(math.max(win and vim.api.nvim_win_get_cursor(win)[2] or fstart, fstart), fstart + #val)
        pcall(vim.api.nvim_win_set_cursor, win, { lnum, math.min(col, fstart + W - 1) })
    end
    local relinked = apply(s, lnum, fg, bg)
    if relinked then
        ui.relayout(buf) -- link reappeared: widen/realign columns + window
    else
        ui.rerender(buf) -- after apply so the group swatch reflects the new/restored color
    end
    overrides.autosave()
end

--- Increment/decrement (by `delta`) the R/G/B component of the hex color the
--- cursor is hovering over, clamped to 00..ff. No-op unless the field holds a
--- valid #rrggbb. Normal-mode helper for <M-Up>/<M-Down>.
local function bump(buf, delta)
    local s, win, lnum, field = ctx(buf)
    if not s then
        return
    end
    local col = vim.api.nvim_win_get_cursor(win)[2]
    local fstart = field == 1 and 0 or W
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local color = util.parse_color(line:sub(fstart + 1, fstart + W))
    if not color or color == "NONE" then
        return
    end

    -- "#rrggbb": component by cursor column within the field (# counts as R).
    local rel = col - fstart
    local comp = rel <= 2 and 1 or (rel <= 4 and 2 or 3)
    local hex = color:sub(2)
    local i = (comp - 1) * 2 + 1
    local byte = tonumber(hex:sub(i, i + 1), 16)
    byte = math.max(0, math.min(255, byte + delta))
    local newhex = hex:sub(1, i - 1) .. string.format("%02x", byte) .. hex:sub(i + 2)

    local newline = line:sub(1, fstart) .. ui.padr("#" .. newhex, W) .. line:sub(fstart + W + 1)
    local view = vim.fn.winsaveview() -- preserve cursor + scroll (no window shift)
    s.adjusting = true
    vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { newline })
    s.adjusting = false
    local _, fg, bg = split(newline, field)
    apply(s, lnum, fg, bg)
    ui.rerender(buf) -- after apply so the group swatch reflects the new color
    overrides.autosave()
    pcall(vim.fn.winrestview, view)
end

--- Toggle the row under the cursor between editing its own group and editing the
--- group it links to (only meaningful on a linked row). When switched to the
--- link target, the fg/bg fields are populated with that group's own values so
--- edits land on it directly; switched back, the fields go blank again.
local function toggle_link(buf)
    local s = ui.get_session(buf)
    if not s or not s.editable or not s.rows then
        return
    end
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) ~= buf then
        return
    end
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local desc = s.rows[lnum]
    if not desc or not desc.link or desc.link == "" then
        return -- nothing to toggle on this row
    end
    desc.editing_target = not desc.editing_target

    -- Repopulate the row's fields for the newly active group.
    local fg, bg = "", ""
    if desc.editing_target then
        local own = util.own(desc.link)
        if not own.link then
            fg = util.hex(own.fg) or ""
            bg = util.hex(own.bg) or ""
        end
    end
    local newline = ui.padr(fg, W) .. ui.padr(bg, W)
    local cur = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    if newline ~= cur then
        s.suppress = true -- the write below shouldn't be treated as an edit
        pcall(vim.api.nvim_buf_set_lines, buf, lnum - 1, lnum, false, { newline })
    end
    ui.rerender(buf)
    pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
end

--- Wire editing autocmds onto an editable tweaker buffer.
function M.attach(buf)
    local grp = vim.api.nvim_create_augroup("TweakerEditor_" .. buf, { clear = true })

    vim.keymap.set("n", "<C-t>", function()
        toggle_link(buf)
    end, { buffer = buf, nowait = true, silent = true, desc = "Tweaker: toggle editing the linked-to group" })

    vim.keymap.set("n", "<M-Up>", function()
        bump(buf, 1)
    end, { buffer = buf, nowait = true, silent = true, desc = "Tweaker: increment RGB component under cursor" })
    vim.keymap.set("n", "<M-Down>", function()
        bump(buf, -1)
    end, { buffer = buf, nowait = true, silent = true, desc = "Tweaker: decrement RGB component under cursor" })

    -- Never add or merge rows: block the line-creating/joining commands. <CR> in
    -- insert leaves insert instead of splitting the line.
    for _, k in ipairs({ "o", "O", "J", "gJ" }) do
        vim.keymap.set("n", k, "<Nop>", { buffer = buf, nowait = true, silent = true })
    end
    vim.keymap.set("i", "<CR>", "<Esc>", { buffer = buf, nowait = true, silent = true })

    -- Backspace must stay inside the current field: at a field's start it would
    -- otherwise join the row into the header (or cross into the previous field).
    -- Plain (non-expr) mapping so the delete is unambiguous — an expr map's
    -- returned key is easy to double-process into a no-op. <C-h> often == <BS>.
    local function guarded_bs()
        local win = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_get_buf(win) ~= buf then
            return
        end
        local pos = vim.api.nvim_win_get_cursor(win)
        local row, col = pos[1] - 1, pos[2]
        local s = ui.get_session(buf)
        local field = (s and s.field) or (col < W and 1 or 2)
        local fstart = (field == 1) and 0 or W
        if col <= fstart then
            return -- at field start: no-op (don't join lines / cross fields)
        end
        pcall(vim.api.nvim_buf_set_text, buf, row, col - 1, row, col, {})
        pcall(vim.api.nvim_win_set_cursor, win, { row + 1, col - 1 })
    end
    for _, k in ipairs({ "<BS>", "<C-h>" }) do
        vim.keymap.set("i", k, guarded_bs, { buffer = buf, nowait = true, silent = true })
    end
    -- Line/word kills can delete across field/line boundaries; disable them.
    for _, k in ipairs({ "<C-u>", "<C-w>" }) do
        vim.keymap.set("i", k, "<Nop>", { buffer = buf, nowait = true, silent = true })
    end

    vim.api.nvim_create_autocmd("InsertEnter", {
        group = grp,
        buffer = buf,
        callback = function()
            local s = ui.get_session(buf)
            if not s then
                return
            end
            local pos = vim.api.nvim_win_get_cursor(0)
            s.field = pos[2] < W and 1 or 2
            s.active_lnum = pos[1]
        end,
    })
    vim.api.nvim_create_autocmd("InsertLeave", {
        group = grp,
        buffer = buf,
        callback = function()
            settle(buf)
            local s = ui.get_session(buf)
            if s then
                s.field = nil
                s.active_lnum = nil
            end
        end,
    })
    vim.api.nvim_create_autocmd("TextChangedI", {
        group = grp,
        buffer = buf,
        callback = function()
            local repaired = ui.resync(buf)
            if log.enabled() then
                log.write("TextChangedI resync=" .. tostring(repaired))
            end
            if not repaired then
                live(buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TextChanged", {
        group = grp,
        buffer = buf,
        callback = function()
            local repaired = ui.resync(buf)
            if log.enabled() then
                log.write("TextChanged resync=" .. tostring(repaired))
            end
            if not repaired then
                settle(buf)
            end
        end,
    })
end

return M
