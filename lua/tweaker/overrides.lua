--- Manages tweaker's highlight overrides: an in-memory table (per colorscheme),
--- optional JSON persistence, live application, an on/off toggle, and save/load.
local M = {}

local state = {
    enabled = true, -- whether overrides are applied
    auto_save = false, -- persist to disk on every committed edit
    path = vim.fn.stdpath("data") .. "/tweaker/overrides.json",
    data = nil, -- lazily loaded: data[colorscheme][group] = { fg = "#hex"?, bg = "#hex"? }
}

local function scheme()
    return vim.g.colors_name or "default"
end

--- Load persisted overrides from disk into state.data (replacing it).
local function load_disk()
    state.data = {}
    local f = io.open(state.path, "r")
    if not f then
        return
    end
    local content = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, content)
    if ok and type(decoded) == "table" then
        state.data = decoded
    end
end

local function data()
    if not state.data then
        load_disk()
    end
    return state.data
end

--- Apply one override, breaking any link (an overridden group is concrete). We
--- start from the group's OWN attributes: for a linked group that's empty, so the
--- result is a clean unlink with just fg/bg; for a group with its own attrs those
--- (bold, etc.) are preserved.
local function apply_group(group, ov)
    if not group or group == "" then
        return
    end
    local raw = vim.api.nvim_get_hl(0, { name = group })
    local base = (type(raw) == "table" and not raw.link) and vim.deepcopy(raw) or {}
    base.link = nil
    base.fg = ov.fg
    base.bg = ov.bg
    pcall(vim.api.nvim_set_hl, 0, group, base)
end

--- Apply all overrides for the current colorscheme (no-op when disabled).
function M.apply()
    if not state.enabled then
        return
    end
    local ovs = data()[scheme()]
    if not ovs then
        return
    end
    for group, ov in pairs(ovs) do
        apply_group(group, ov)
    end
end

--- Record an override for `group` (fg/bg are "#rrggbb" or nil) and apply it live.
function M.set(group, fg, bg)
    local s = scheme()
    local d = data()
    d[s] = d[s] or {}
    d[s][group] = { fg = fg, bg = bg }
    apply_group(group, d[s][group])
end

--- Persist to disk if auto-save is on (called after committed edits).
function M.autosave()
    if state.auto_save then
        M.save()
    end
end

--- Write all overrides to disk.
function M.save()
    local dir = vim.fn.fnamemodify(state.path, ":h")
    vim.fn.mkdir(dir, "p")
    local f = io.open(state.path, "w")
    if not f then
        vim.notify("tweaker: cannot write " .. state.path, vim.log.levels.ERROR)
        return
    end
    f:write(vim.json.encode(data()))
    f:close()
    vim.notify("tweaker: saved overrides", vim.log.levels.INFO)
end

--- Re-source the current colorscheme (resets highlights); the ColorScheme
--- autocmd then re-applies overrides when enabled.
local function refresh()
    local name = vim.g.colors_name
    if name then
        vim.cmd.colorscheme(name)
    else
        M.apply()
    end
end

--- Discard unsaved changes, reload persisted overrides, and re-apply.
function M.load()
    load_disk()
    refresh()
    vim.notify("tweaker: reloaded overrides from disk", vim.log.levels.INFO)
end

--- Toggle application of overrides on/off.
function M.toggle()
    state.enabled = not state.enabled
    refresh()
    vim.notify("tweaker: overrides " .. (state.enabled and "ON" or "OFF"), vim.log.levels.INFO)
    return state.enabled
end

function M.is_enabled()
    return state.enabled
end

--- The override file path.
function M.path()
    return state.path
end

--- Configure and start: load persisted overrides, apply them, and re-apply on
--- every future colorscheme load.
function M.setup(cfg)
    cfg = cfg or {}
    if cfg.auto_save ~= nil then
        state.auto_save = cfg.auto_save
    end
    if cfg.path then
        state.path = cfg.path
    end
    load_disk()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("TweakerOverrides", { clear = true }),
        callback = function()
            M.apply()
        end,
    })
    M.apply()
end

return M
