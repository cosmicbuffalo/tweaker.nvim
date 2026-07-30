local M = {}

---@class tweaker.Config
local defaults = {}

M.config = vim.deepcopy(defaults)

--- Collect the source-window context (window/buffer/cursor) for placement and
--- the leader line.
local function cursor_source()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local pos = vim.api.nvim_win_get_cursor(win) -- {row (1-based), col (0-based)}
    local row, col = pos[1] - 1, pos[2]
    -- Cursor display column (0-based, relative to first text column), used to
    -- align the leader line even with tabs / horizontal scroll.
    local dcol = vim.fn.virtcol(".") - 1 - (vim.fn.winsaveview().leftcol or 0)
    return { win = win, buf = buf, row = row, col = col, dcol = dcol }
end

--- Open the read-only inspect float for the highlights under the cursor.
function M.inspect()
    local src = cursor_source()
    local items = require("tweaker.inspect").collect(src.buf, src.row, src.col)
    require("tweaker.ui").open("Tweaker · under cursor", items, { source = src })
end

--- Open the editable float. With no group names, edit the groups under the
--- cursor (with a leader line). With names, edit those groups specifically.
---@param names string[]|nil
function M.edit(names)
    local ui = require("tweaker.ui")
    if names and #names > 0 then
        local util = require("tweaker.util")
        local items = {}
        for _, name in ipairs(names) do
            items[#items + 1] = { source = "", group = name, priority = "", hl = util.resolve(name) }
        end
        ui.open("Tweaker · edit", items, { editable = true })
    else
        local src = cursor_source()
        local items = require("tweaker.inspect").collect(src.buf, src.row, src.col)
        ui.open("Tweaker · edit", items, { editable = true, source = src })
    end
end

--- Plugin entry point. Registers user commands.
---@param opts tweaker.Config|nil
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

    vim.api.nvim_create_user_command("TweakerInspect", function()
        M.inspect()
    end, { desc = "Inspect highlight groups under the cursor" })

    vim.api.nvim_create_user_command("Tweaker", function(o)
        M.edit(o.fargs)
    end, {
        nargs = "*",
        complete = "highlight",
        desc = "Edit highlight groups (under cursor, or named) with live preview",
    })
end

return M
