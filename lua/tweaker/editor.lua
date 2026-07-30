local util = require("tweaker.util")
local ui = require("tweaker.ui")

local M = {}

local W = ui.FIELD_W -- fixed field width

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

--- Apply the row's fg/bg to its highlight group. Reads the group's current attrs
--- and overrides only fg/bg so other attributes survive.
local function apply(s, lnum, fg, bg)
    local desc = s.rows and s.rows[lnum]
    if not desc or not desc.group or desc.group == "" then
        return
    end
    local new = vim.deepcopy(util.resolve(desc.group))
    new.link = nil
    local function set_attr(key, raw)
        if raw == "" then
            new[key] = nil -- cleared cell -> remove attribute
            return
        end
        local c = util.parse_color(raw)
        if c == "NONE" then
            new[key] = nil
        elseif c then
            new[key] = c
        end
        -- invalid / partial input: leave the attribute unchanged
    end
    set_attr("fg", fg)
    set_attr("bg", bg)
    pcall(vim.api.nvim_set_hl, 0, desc.group, new)
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
    return s, win, pos[1], s.field or (pos[2] < W and 1 or 2)
end

--- Insert-mode change: re-render chrome at dynamic offsets and apply live. Never
--- mutates the buffer or moves the cursor (that would corrupt the insert).
local function live(buf)
    local s, _, lnum, field = ctx(buf)
    if not s then
        return
    end
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local _, fg, bg = split(line, field)
    ui.rerender(buf, lnum)
    apply(s, lnum, fg, bg)
end

--- Normal-mode change / InsertLeave: normalize the line back to fixed width
--- (only if it changed), keep the cursor inside its field, re-render, apply.
local function settle(buf)
    local s, win, lnum, field = ctx(buf)
    if not s then
        return
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
    ui.rerender(buf, lnum)
    apply(s, lnum, fg, bg)
end

--- Wire editing autocmds onto an editable tweaker buffer.
function M.attach(buf)
    local grp = vim.api.nvim_create_augroup("TweakerEditor_" .. buf, { clear = true })

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
