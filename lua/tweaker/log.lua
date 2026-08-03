--- Tiny opt-in debug logger. Enable with `:lua vim.g.tweaker_debug = true` (or set
--- it in your config), reproduce the issue, then read the log path from
--- `require("tweaker.log").path()`. No-op unless enabled, so it's safe to leave in.
local M = {}

local logpath = vim.fn.stdpath("cache") .. "/tweaker-debug.log"

function M.enabled()
    return vim.g.tweaker_debug == true
end

function M.path()
    return logpath
end

--- Append a line to the log (only when enabled).
function M.write(msg)
    if not M.enabled() then
        return
    end
    local f = io.open(logpath, "a")
    if not f then
        return
    end
    f:write(msg .. "\n")
    f:close()
end

return M
