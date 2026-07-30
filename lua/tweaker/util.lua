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

--- Parse a color cell's contents into a canonical value.
--- Accepts "#rrggbb" (any case) or "NONE" (any case), ignoring surrounding
--- whitespace. Returns "#rrggbb" (lowercased), "NONE", or nil if invalid/blank.
---@param s string
---@return string|nil
function M.parse_color(s)
    if type(s) ~= "string" then
        return nil
    end
    local t = s:gsub("^%s+", ""):gsub("%s+$", "")
    if t:match("^#%x%x%x%x%x%x$") then
        return t:lower()
    end
    if t:upper() == "NONE" then
        return "NONE"
    end
    return nil
end

return M
