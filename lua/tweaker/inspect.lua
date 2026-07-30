local util = require("tweaker.util")

local M = {}

-- Neovim's canonical priority ladder: syntax=50, treesitter=100,
-- semantic_tokens=125, diagnostics=150, user=200.
local PRI = vim.hl.priorities

---@class tweaker.Item
---@field source string      one of "treesitter"|"semantic"|"syntax"|"extmark"
---@field group string       the highlight group name
---@field link string|nil    the group it links to, if any
---@field priority integer    effective draw priority (higher wins)
---@field hl table           resolved attributes (fg/bg/bold/...)

--- Collect every highlight contribution at (row, col) [0-indexed] in `bufnr`,
--- sorted by priority descending so the winning group is first.
---@param bufnr integer|nil
---@param row integer  0-indexed
---@param col integer  0-indexed
---@return tweaker.Item[] items, table info  raw inspect_pos result
function M.collect(bufnr, row, col)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local info = vim.inspect_pos(bufnr, row, col, {
        syntax = true,
        treesitter = true,
        semantic_tokens = true,
        extmarks = true,
    })

    local items = {}

    local function add(source, group, priority, link)
        if not group or group == "" then
            return
        end
        table.insert(items, {
            source = source,
            group = group,
            link = link,
            -- Some sources report priority as a string (e.g. treesitter
            -- `(#set! priority N)` directives), so coerce to a number.
            priority = tonumber(priority) or 0,
            hl = util.resolve(group),
        })
    end

    for _, ts in ipairs(info.treesitter or {}) do
        local md = ts.metadata or {}
        local pri = md.priority or (md[ts.id] and md[ts.id].priority) or PRI.treesitter
        add("treesitter", ts.hl_group, pri, ts.hl_group_link)
    end

    -- semantic_tokens and extmarks are both extmark-maps: fields live under .opts
    for _, st in ipairs(info.semantic_tokens or {}) do
        local o = st.opts or {}
        add("semantic", o.hl_group, o.priority or PRI.semantic_tokens, o.hl_group_link)
    end

    for _, sy in ipairs(info.syntax or {}) do
        add("syntax", sy.hl_group, PRI.syntax, sy.hl_group_link)
    end

    for _, ex in ipairs(info.extmarks or {}) do
        local o = ex.opts or {}
        add("extmark", o.hl_group, o.priority or PRI.user, o.hl_group_link)
    end

    table.sort(items, function(a, b)
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.source < b.source
    end)

    return items, info
end

return M
