local M = {}

---@class tweaker.Config
---@field auto_save boolean  persist overrides to disk on every committed edit
---@field path string|nil    override file location
---@field colors table|nil   extra/override master colors ({ name = "#hex" }) for export naming
local defaults = {
    auto_save = false,
    colors = {},
}

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

--- Open the editable float. With no group names, edit the groups under the
--- cursor (with a leader line). With names, edit those groups specifically.
---@param names string[]|nil
function M.edit(names)
    local ui = require("tweaker.ui")
    if names and #names > 0 then
        local util = require("tweaker.util")
        local items = {}
        for _, name in ipairs(names) do
            items[#items + 1] = { source = "", group = name, priority = "", hl = util.own(name) }
        end
        ui.open("Tweaker · edit", items, { editable = true })
    else
        local src = cursor_source()
        local items = require("tweaker.inspect").collect(src.buf, src.row, src.col)
        ui.open("Tweaker · edit", items, { editable = true, source = src })
    end
end

--- Plugin entry point. Registers user commands and starts the overrides store.
---@param opts tweaker.Config|nil
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
    require("tweaker.overrides").setup(M.config)
    require("tweaker.palette").setup(M.config.colors)

    local cmd = vim.api.nvim_create_user_command

    cmd("Tweaker", function(o)
        M.edit(o.fargs)
    end, {
        nargs = "*",
        complete = "highlight",
        desc = "Edit highlight groups (under cursor, or named) with live preview",
    })

    cmd("TweakerToggle", function()
        require("tweaker.overrides").toggle()
    end, { desc = "Toggle application of tweaker overrides on/off" })

    cmd("TweakerSave", function()
        require("tweaker.overrides").save()
    end, { desc = "Persist tweaker overrides to disk" })

    cmd("TweakerLoad", function()
        require("tweaker.overrides").load()
    end, { desc = "Discard unsaved tweaks and reload persisted overrides" })

    cmd("TweakerOpenOverrides", function()
        vim.cmd.edit(vim.fn.fnameescape(require("tweaker.overrides").path()))
    end, { desc = "Open the tweaker overrides file in the current window" })

    cmd("TweakerBake", function(o)
        require("tweaker.export").write(o.args ~= "" and o.args or nil, o.bang)
    end, {
        nargs = "?",
        bang = true,
        complete = "color",
        desc = "Export current highlights + tweaks to a standalone colorscheme (bang to overwrite)",
    })
end

return M
