--- `:checkhealth tweaker` — verifies the environment tweaker needs and reports
--- state useful for debugging (override file, debug log, conflicting maps).
local M = {}

local function report()
    -- vim.health is the modern API; fall back for older signatures.
    return vim.health
end

function M.check()
    local h = report()
    h.start("tweaker.nvim")

    -- Neovim version
    if vim.fn.has("nvim-0.10") == 1 then
        h.ok("Neovim " .. tostring(vim.version()) .. " (>= 0.10)")
    else
        h.error("Neovim 0.10+ is required (uses vim.inspect_pos, vim.hl.priorities)")
    end

    -- True color
    if vim.o.termguicolors then
        h.ok("'termguicolors' is enabled")
    else
        h.warn(
            "'termguicolors' is off — hex colors won't render",
            { "add `vim.o.termguicolors = true` to your config" }
        )
    end

    -- Overrides store
    local ov = require("tweaker.overrides")
    local path = ov.path()
    local st = vim.uv.fs_stat(path)
    if not st then
        h.info("no overrides file yet (created on first save): " .. path)
    else
        local f = io.open(path, "r")
        local content = f and f:read("*a")
        if f then
            f:close()
        end
        if content and pcall(vim.json.decode, content) then
            h.ok("overrides file is valid JSON: " .. path)
        else
            h.warn("overrides file exists but isn't valid JSON: " .. path)
        end
    end

    -- Debug logging
    local log = require("tweaker.log")
    if log.enabled() then
        h.info("debug logging is ON — log: " .. log.path())
    else
        h.info("debug logging is off (enable with `:lua vim.g.tweaker_debug = true`, log: " .. log.path() .. ")")
    end

    -- Insert-mode <BS> — a global mapping is fine (tweaker overrides it
    -- buffer-locally), but surfacing it helps diagnose editing issues.
    local bs = vim.fn.maparg("<BS>", "i", false, true)
    if bs and (bs.callback or (bs.rhs and bs.rhs ~= "")) then
        local from = bs.desc or (bs.rhs ~= "" and bs.rhs) or "a Lua callback"
        h.info(
            "a global insert-mode <BS> mapping is set ("
                .. tostring(from)
                .. "); tweaker remaps <BS> buffer-locally inside its window"
        )
    else
        h.ok("no conflicting global insert-mode <BS> mapping")
    end
end

return M
