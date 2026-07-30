local util = require("tweaker.util")
local ui = require("tweaker.ui")
local overrides = require("tweaker.overrides")

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

--- Record the row's fg/bg as an override (which applies it live). Parses each
--- cell: "#rrggbb" -> that color, NONE/empty -> cleared, invalid/partial -> keep
--- the group's current value (no change yet).
local function apply(s, lnum, fg_raw, bg_raw)
    local desc = s.rows and s.rows[lnum]
    if not desc or not desc.group or desc.group == "" then
        return
    end
    local cur = util.resolve(desc.group)
    local function val(raw, curval)
        if raw == "" then
            return nil
        end
        local c = util.parse_color(raw)
        if c == "NONE" then
            return nil
        elseif c then
            return c
        end
        return util.hex(curval) -- invalid / partial: keep current
    end
    overrides.set(desc.group, val(fg_raw, cur.fg), val(bg_raw, cur.bg))
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
    ui.rerender(buf)
    apply(s, lnum, fg, bg)
end

--- Normal-mode change / InsertLeave: normalize the line back to fixed width
--- (only if it changed), keep the cursor inside its field, re-render, apply.
local function settle(buf)
    local s, win, lnum, field = ctx(buf)
    if not s then
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
    ui.rerender(buf)
    apply(s, lnum, fg, bg)
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
    ui.rerender(buf)
    local _, fg, bg = split(newline, field)
    apply(s, lnum, fg, bg)
    overrides.autosave()
    pcall(vim.fn.winrestview, view)
end

--- Wire editing autocmds onto an editable tweaker buffer.
function M.attach(buf)
    local grp = vim.api.nvim_create_augroup("TweakerEditor_" .. buf, { clear = true })

    vim.keymap.set("n", "<M-Up>", function()
        bump(buf, 1)
    end, { buffer = buf, nowait = true, silent = true, desc = "Tweaker: increment RGB component under cursor" })
    vim.keymap.set("n", "<M-Down>", function()
        bump(buf, -1)
    end, { buffer = buf, nowait = true, silent = true, desc = "Tweaker: decrement RGB component under cursor" })

    -- Never add rows: block the line-creating commands. <CR> in insert leaves
    -- insert instead of splitting the line.
    for _, k in ipairs({ "o", "O" }) do
        vim.keymap.set("n", k, "<Nop>", { buffer = buf, nowait = true, silent = true })
    end
    vim.keymap.set("i", "<CR>", "<Esc>", { buffer = buf, nowait = true, silent = true })

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
            live(buf)
        end,
    })
    vim.api.nvim_create_autocmd("TextChanged", {
        group = grp,
        buffer = buf,
        callback = function()
            settle(buf)
        end,
    })
end

return M
