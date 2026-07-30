local M = {}

---@class tweaker.Config
local defaults = {}

M.config = vim.deepcopy(defaults)

--- Open the read-only inspect float for the highlights under the cursor.
function M.inspect()
    local inspect = require("tweaker.inspect")
    local ui = require("tweaker.ui")

    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local pos = vim.api.nvim_win_get_cursor(win) -- {row (1-based), col (0-based)}
    local row, col = pos[1] - 1, pos[2]
    -- Cursor display column (0-based, relative to first text column), used to
    -- align the leader line even with tabs / horizontal scroll.
    local dcol = vim.fn.virtcol(".") - 1 - (vim.fn.winsaveview().leftcol or 0)

    local items = inspect.collect(buf, row, col)
    ui.open("Tweaker · under cursor", items, {
        source = { win = win, buf = buf, row = row, col = col, dcol = dcol },
    })
end

--- Plugin entry point. Registers user commands.
---@param opts tweaker.Config|nil
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

    vim.api.nvim_create_user_command("TweakerInspect", function()
        M.inspect()
    end, { desc = "Inspect highlight groups under the cursor" })
end

return M
