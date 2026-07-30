local M = {}

--- Convert a 24-bit integer color (as returned by nvim_get_hl) to "#rrggbb".
---@param n integer|nil
---@return string|nil
function M.hex(n)
    if type(n) ~= "number" then
        return nil
    end
    return string.format("#%06x", n)
end

--- Resolve a highlight group to its final attributes, following links.
---@param name string
---@return table attrs  the resolved highlight (may be empty)
function M.resolve(name)
    if not name or name == "" then
        return {}
    end
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    if not ok or type(hl) ~= "table" then
        return {}
    end
    return hl
end

return M
