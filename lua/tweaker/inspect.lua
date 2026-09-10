--- Collects the highlight groups contributing at a cursor position (treesitter,
--- LSP semantic tokens, syntax, extmarks), deduped and sorted by draw priority.
local util = require("tweaker.util")

local M = {}

-- Neovim's canonical priority ladder: syntax=50, treesitter=100,
-- semantic_tokens=125, diagnostics=150, user=200. (vim.hl on 0.11+, vim.highlight
-- on 0.10 — the namespace was renamed.)
local PRI = (vim.hl or vim.highlight).priorities

---@class tweaker.Item
---@field source string      one of "treesitter"|"semantic"|"syntax"|"extmark"
---@field group string       the highlight group name
---@field link string|nil    the group it links to, if any
---@field priority integer    effective draw priority (higher wins)
---@field order integer       draw order at equal priority (higher sits on top)
---@field hl table           resolved attributes (fg/bg/bold/...)

--- Collect every highlight contribution at (row, col) [0-indexed] in `bufnr`,
--- ordered so the group that actually paints the cell is first (and the cursor,
--- which starts on the first row, lands on it).
---@param bufnr integer|nil
---@param row integer  0-indexed
---@param col integer  0-indexed
---@return tweaker.Item[] items
function M.collect(bufnr, row, col)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local info = vim.inspect_pos(bufnr, row, col, {
        syntax = true,
        treesitter = true,
        semantic_tokens = true,
        extmarks = true,
    })

    local items = {}
    -- `order` records Neovim's application (draw) order: contributions drawn
    -- later sit on top, so at equal priority the higher `order` wins. We add
    -- sources in draw order (syntax < treesitter < semantic < extmark) and, in
    -- each, in the order vim.inspect_pos reports them (later capture = on top —
    -- e.g. @comment.documentation over @comment).
    local order = 0

    local function add(source, group, priority, link)
        if not group or group == "" then
            return
        end
        order = order + 1
        table.insert(items, {
            source = source,
            group = group,
            link = link,
            -- Some sources report priority as a string (e.g. treesitter
            -- `(#set! priority N)` directives), so coerce to a number.
            priority = tonumber(priority) or 0,
            order = order,
            hl = util.own(group), -- own definition (may be a link)
        })
    end

    for _, sy in ipairs(info.syntax or {}) do
        add("syntax", sy.hl_group, PRI.syntax, sy.hl_group_link)
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

    for _, ex in ipairs(info.extmarks or {}) do
        local o = ex.opts or {}
        add("extmark", o.hl_group, o.priority or PRI.user, o.hl_group_link)
    end

    -- Dedupe: the same highlight group can be reported by more than one source;
    -- keep its topmost occurrence (highest priority, then latest draw order).
    local best = {}
    for _, it in ipairs(items) do
        local prev = best[it.group]
        if
            not prev
            or it.priority > prev.priority
            or (it.priority == prev.priority and it.order > prev.order)
        then
            best[it.group] = it
        end
    end
    local unique = {}
    for _, it in pairs(best) do
        unique[#unique + 1] = it
    end

    -- Find the group that actually paints the cell. Neovim layers the
    -- contributions in draw order and merges their attributes, so the effective
    -- foreground comes from the topmost (highest priority, then latest-drawn)
    -- group that defines an fg — even when a color-less group (e.g. @spell,
    -- @nospell) sits above it. That fg provider is "the one that wins" the color
    -- the user sees; fall back to the bg provider, then the topmost overall.
    table.sort(unique, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.order < b.order
    end)
    local winner
    for _, it in ipairs(unique) do
        if util.resolve(it.group).fg ~= nil then
            winner = it
        end
    end
    if not winner then
        for _, it in ipairs(unique) do
            if util.resolve(it.group).bg ~= nil then
                winner = it
            end
        end
    end

    -- Display order: the winning group first (obvious position + cursor start),
    -- then the rest as a top-down layer stack.
    table.sort(unique, function(a, b)
        if a == winner then
            return b ~= winner
        end
        if b == winner then
            return false
        end
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.order > b.order
    end)

    return unique
end

return M
