--- Maps arbitrary hex colors to human-readable base names by nearest match
--- against a master list of named colors. Used by the exporter to name palette
--- variables (red_1, red_2, light_blue_1, ...).
local M = {}

-- Master colors: { name, "#hex" }, kept sorted by hex value. Each core color
-- (red/green/blue/orange/pink/purple/yellow/brown/gray) has dark_/light_
-- variants, plus black and white. Users can extend/override via setup().
local DEFAULT = {
    { "black", "#000000" },
    { "dark_green", "#006400" },
    { "green", "#008000" },
    { "dark_cyan", "#008b8b" },
    { "blue", "#0000ff" },
    { "cyan", "#00ffff" },
    { "dark_blue", "#1f3a5f" },
    { "dark_gray", "#404040" },
    { "dark_purple", "#4b0082" },
    { "dark_brown", "#5c4033" },
    { "purple", "#800080" },
    { "gray", "#808080" },
    { "dark_red", "#8b0000" },
    { "light_green", "#90ee90" },
    { "brown", "#a52a2a" },
    { "light_blue", "#add8e6" },
    { "dark_yellow", "#b8860b" },
    { "light_brown", "#c19a6b" },
    { "dark_pink", "#c71585" },
    { "light_gray", "#d3d3d3" },
    { "light_purple", "#d8bfd8" },
    { "light_cyan", "#e0ffff" },
    { "red", "#ff0000" },
    { "dark_orange", "#ff8c00" },
    { "light_red", "#ff9999" },
    { "orange", "#ffa500" },
    { "pink", "#ffc0cb" },
    { "light_orange", "#ffcc80" },
    { "light_pink", "#ffddee" },
    { "yellow", "#ffff00" },
    { "light_yellow", "#ffffe0" },
    { "white", "#ffffff" },
}

--- Numeric value of a "#rrggbb" string, for sorting.
function M.val(hex)
    return tonumber(hex:sub(2), 16) or 0
end

local function channels(hex)
    local n = M.val(hex)
    return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

-- sRGB (0..255) -> OKLab, a perceptual space where hue is separated from
-- lightness, so nearest-color naming matches human perception (unlike RGB, where
-- gray acts as a magnet for any desaturated-ish color).
local function srgb_to_linear(c)
    c = c / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function oklab(hex)
    local ri, gi, bi = channels(hex)
    local r, g, b = srgb_to_linear(ri), srgb_to_linear(gi), srgb_to_linear(bi)
    local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
    local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
    local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
    return {
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    }
end

--- Perceptual lightness (OKLab L, ~0..1) of a "#rrggbb" hex. Used to order the
--- shades within a color name as a clean dark -> light gradient.
---@param hex string
---@return number
function M.lightness(hex)
    return oklab(hex).L
end

-- Master colors grouped for naming: neutrals (by lightness) and chromatic
-- families (base name without dark_/light_), each with a representative hue.
local neutrals = nil -- { {name, L}, ... }
local families = nil -- { [family] = { hue = <rad>, members = { {name, L}, ... } } }

-- A color counts as "neutral" (gray/black/white family) when its OKLab chroma is
-- below this; otherwise it's chromatic and named by hue.
local CHROMA_THRESHOLD = 0.03

local function chroma(lab)
    return math.sqrt(lab.a * lab.a + lab.b * lab.b)
end

--- Configure the master color list. `custom` is a { name = "#hex" } map merged
--- over the defaults.
function M.setup(custom)
    local map = {}
    for _, c in ipairs(DEFAULT) do
        map[c[1]] = c[2]
    end
    for name, hex in pairs(custom or {}) do
        map[name] = hex
    end

    neutrals, families = {}, {}
    for name, hex in pairs(map) do
        local lab = oklab(hex)
        if chroma(lab) < CHROMA_THRESHOLD then
            neutrals[#neutrals + 1] = { name = name, L = lab.L }
        else
            local family = name:gsub("^dark_", ""):gsub("^light_", "")
            local fam = families[family]
            if not fam then
                fam = { members = {}, sin = 0, cos = 0, base = nil }
                families[family] = fam
            end
            local hue = math.atan2(lab.b, lab.a)
            fam.members[#fam.members + 1] = { name = name, L = lab.L }
            fam.sin = fam.sin + math.sin(hue)
            fam.cos = fam.cos + math.cos(hue)
            if name == family then
                fam.base = hue
            end
        end
    end
    -- Representative hue per family: the base variant's hue, else circular average.
    for _, fam in pairs(families) do
        fam.hue = fam.base or math.atan2(fam.sin, fam.cos)
    end
    table.sort(neutrals, function(a, b)
        return a.L < b.L
    end)
end

local function ensure()
    if not families then
        M.setup()
    end
end

local function hue_dist(a, b)
    local d = math.abs(a - b)
    return d > math.pi and (2 * math.pi - d) or d
end

--- Nearest master color name for a "#rrggbb" hex. Low-chroma colors are matched
--- among neutrals by lightness; chromatic colors pick a family by hue, then the
--- dark_/base/light_ variant within it by lightness — so a color is never named a
--- shade that's the wrong brightness.
---@param hex string
---@return string name
function M.nearest(hex)
    ensure()
    local t = oklab(hex)
    if chroma(t) < CHROMA_THRESHOLD then
        local best, best_d
        for _, n in ipairs(neutrals) do
            local d = math.abs(t.L - n.L)
            if not best_d or d < best_d then
                best_d, best = d, n.name
            end
        end
        return best
    end

    local th = math.atan2(t.b, t.a)
    local fam, fam_d
    for _, f in pairs(families) do
        local d = hue_dist(th, f.hue)
        if not fam_d or d < fam_d then
            fam_d, fam = d, f
        end
    end
    local best, best_d
    for _, m in ipairs(fam.members) do
        local d = math.abs(t.L - m.L)
        if not best_d or d < best_d then
            best_d, best = d, m.name
        end
    end
    return best
end

return M
