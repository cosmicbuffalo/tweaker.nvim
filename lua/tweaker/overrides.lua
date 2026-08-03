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
    local ok, raw = pcall(vim.api.nvim_get_hl, 0, { name = group })
    local base = (ok and type(raw) == "table" and not raw.link) and vim.deepcopy(raw) or {}
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
--- The first time a group is overridden we remember how to relink it later
--- (`base`): the caller can pass `base_hint` (the row's open-time definition,
--- e.g. `{ link = provider }`); otherwise we derive it from the group's current
--- definition. Persisted so it survives restarts.
function M.set(group, fg, bg, base_hint)
    local s = scheme()
    local d = data()
    d[s] = d[s] or {}
    local existing = d[s][group]
    local base
    if existing then
        base = existing.base
    elseif base_hint ~= nil then
        base = base_hint
    else
        local ok, raw = pcall(vim.api.nvim_get_hl, 0, { name = group })
        if ok and type(raw) == "table" and raw.link then
            base = { link = raw.link }
        elseif ok and type(raw) == "table" and vim.tbl_isempty(raw) then
            base = { inherit = true }
        end
    end
    d[s][group] = { fg = fg, bg = bg, base = base }
    apply_group(group, d[s][group])
end

--- Whether an override is recorded for `group` (current colorscheme).
function M.has(group)
    local d = data()[scheme()]
    return d ~= nil and d[group] ~= nil
end

--- Whether `group`'s override remembers an original link/hierarchy to restore.
function M.has_base(group)
    local d = data()[scheme()]
    return d ~= nil and d[group] ~= nil and d[group].base ~= nil
end

--- Remove `group`'s override and restore its original definition live. Restores
--- to `orig` when given (e.g. the row's open-time definition: `{ link = target }`,
--- or `{}` to fall back through a treesitter @-hierarchy); otherwise to whatever
--- the override remembered (`base`); otherwise to empty. Returns the stored base.
function M.clear(group, orig)
    if not group or group == "" then
        return
    end
    local s = scheme()
    local d = data()
    local entry = d[s] and d[s][group]
    if d[s] then
        d[s][group] = nil
    end
    local restore = orig
    if restore == nil then
        local base = entry and entry.base
        restore = {}
        if base and base.link then
            restore = { link = base.link }
        end -- base.inherit -> {} (already)
    end
    pcall(vim.api.nvim_set_hl, 0, group, restore)
    return entry and entry.base
end

--- Persist to disk if auto-save is on (called after committed edits).
function M.autosave()
    if state.auto_save then
        M.save()
    end
end

--- Encode one override object compactly on a single line, e.g.
--- `{ "fg": "#rrggbb", "bg": "#rrggbb" }` (fg/bg first, then any other keys).
local function encode_entry(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    local rank = { fg = 1, bg = 2 }
    table.sort(keys, function(a, b)
        local ra, rb = rank[a] or 3, rank[b] or 3
        if ra ~= rb then
            return ra < rb
        end
        return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = vim.json.encode(k) .. ": " .. vim.json.encode(t[k])
    end
    if #parts == 0 then
        return "{}"
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

--- Pretty-print the overrides table: schemes and groups expanded (sorted, one per
--- line, 2-space indent); each group's colors compact on a single line.
local function encode_pretty(all)
    local schemes = {}
    for s in pairs(all) do
        schemes[#schemes + 1] = s
    end
    table.sort(schemes)
    if #schemes == 0 then
        return "{}\n"
    end
    local out = { "{" }
    for si, sname in ipairs(schemes) do
        local groups = {}
        for g in pairs(all[sname]) do
            groups[#groups + 1] = g
        end
        table.sort(groups)
        out[#out + 1] = "  " .. vim.json.encode(sname) .. ": {"
        for gi, g in ipairs(groups) do
            local sep = gi < #groups and "," or ""
            out[#out + 1] = "    " .. vim.json.encode(g) .. ": " .. encode_entry(all[sname][g]) .. sep
        end
        out[#out + 1] = "  }" .. (si < #schemes and "," or "")
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
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
    f:write(encode_pretty(data()))
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
