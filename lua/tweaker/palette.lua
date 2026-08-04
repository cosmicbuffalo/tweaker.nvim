--- Maps arbitrary hex colors to human-readable names by matching them in a
--- perceptual color space (OKLCh), and provides the ordering used to lay the
--- baked palette out as a smooth gradient. Used by the exporter to name and
--- order palette variables (red_1, red_2, light_blue_1, ...).
local M = {}

-- Chromatic families: { name, hue (OKLab degrees), representative lightness }.
-- A color's name is chosen by the nearest family *hue*; lightness then picks the
-- dark_/light_ variant, and neutrals (grays) are split off first by low chroma.
-- Hues/lightnesses are calibrated against many CSS/named reference colors (not
-- sRGB primaries, whose OKLab hues are skewed — e.g. #0000ff reads as violet) so
-- the boundaries match perception: e.g. the red/orange split sits near 38° so
-- coral/sienna/chocolate read as orange, not red. Users can add/override families
-- via setup() with { name = "#hex" } (its hue/lightness are measured from the hex).
local DEFAULT = {
    { "red", 27, 0.55 },
    { "orange", 50, 0.72 },
    { "yellow", 100, 0.90 },
    { "green", 142, 0.55 },
    { "cyan", 195, 0.68 },
    { "blue", 253, 0.55 },
    { "purple", 310, 0.53 },
    { "pink", 350, 0.70 },
}

-- Neutral (gray) names from darkest to lightest, with the upper OKLab-lightness
-- bound of each. A color counts as neutral when its chroma is below
-- NEUTRAL_CHROMA; then its lightness picks the name. Kept low so visibly tinted
-- colors are named by their hue rather than lumped into gray.
local NEUTRALS = { "black", "dark_gray", "gray", "light_gray", "white" }
local NEUTRAL_L = { black = 0.15, dark_gray = 0.40, gray = 0.65, light_gray = 0.90, white = 1.01 }
local NEUTRAL_CHROMA = 0.025

-- How far a color's lightness must differ from its anchor's to earn a
-- dark_/light_ prefix (OKLab L units).
local VAR_MARGIN = 0.13

--- Numeric value of a "#rrggbb" string.
local function val(hex)
    return tonumber(hex:sub(2), 16) or 0
end

local function channels(hex)
    local n = val(hex)
    return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

-- sRGB (0..255) -> OKLab, a perceptual space where hue, chroma, and lightness
-- are separated, so nearest-color naming and gradient ordering match human
-- perception (unlike RGB, where gray acts as a magnet for desaturated colors).
local function srgb_to_linear(c)
    c = c / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

--- OKLab L, a, b for a "#rrggbb" hex.
local function oklab(hex)
    local ri, gi, bi = channels(hex)
    local r, g, b = srgb_to_linear(ri), srgb_to_linear(gi), srgb_to_linear(bi)
    local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
    local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
    local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
end

--- OKLCh: lightness (0..1), chroma, hue (degrees 0..360) for a "#rrggbb" hex.
local function oklch(hex)
    local L, a, b = oklab(hex)
    local C = math.sqrt(a * a + b * b)
    local h = math.deg(math.atan2(b, a))
    if h < 0 then
        h = h + 360
    end
    return L, C, h
end

--- Perceptual lightness (OKLab L, ~0..1) of a "#rrggbb" hex. Used to order the
--- shades within a color name as a clean dark -> light gradient.
---@param hex string
---@return number
function M.lightness(hex)
    return (oklab(hex))
end

-- Built from the anchors in setup(): per-anchor hue/lightness, and the anchor
-- order around the hue wheel (for gradient layout).
local anchors = nil -- { { name, hue, L }, ... } sorted by hue
local anchor_by_name = nil -- { [name] = { hue, L } }
local family_order = nil -- { [family] = index } chromatic families in hue order

--- Configure the family list. `custom` is a { name = "#hex" } map merged over the
--- built-in families (each custom entry's hue/lightness is measured from its hex).
function M.setup(custom)
    local map = {}
    for _, d in ipairs(DEFAULT) do
        map[d[1]] = { hue = d[2], L = d[3] }
    end
    for name, hex in pairs(custom or {}) do
        local L, _, h = oklch(hex)
        map[name] = { hue = h, L = L }
    end

    anchors, anchor_by_name = {}, {}
    for name, a in pairs(map) do
        local anc = { name = name, hue = a.hue, L = a.L }
        anchors[#anchors + 1] = anc
        anchor_by_name[name] = anc
    end
    table.sort(anchors, function(a, b)
        return a.hue < b.hue
    end)
    family_order = {}
    for i, a in ipairs(anchors) do
        family_order[a.name] = i
    end
end

local function ensure()
    if not anchors then
        M.setup()
    end
end

local function hue_dist(a, b)
    local d = math.abs(a - b)
    return d > 180 and (360 - d) or d
end

--- Nearest human-readable name for a "#rrggbb" hex. Low-chroma colors are named
--- among the neutrals by lightness; chromatic colors pick a family by hue, then a
--- dark_/base/light_ variant relative to that anchor's own lightness. Dark
--- oranges are named brown.
---@param hex string
---@return string name
function M.nearest(hex)
    ensure()
    local L, C, h = oklch(hex)

    if C < NEUTRAL_CHROMA then
        for _, name in ipairs(NEUTRALS) do
            if L < NEUTRAL_L[name] then
                return name
            end
        end
        return "white"
    end

    local fam, fd
    for _, a in ipairs(anchors) do
        local d = hue_dist(h, a.hue)
        if not fd or d < fd then
            fd, fam = d, a
        end
    end

    -- Brown is dark orange (kept off the red hue so dark reds stay dark_red).
    if fam.name == "orange" and L < 0.55 then
        return L < 0.32 and "dark_brown" or "brown"
    end

    if L < fam.L - VAR_MARGIN then
        return "dark_" .. fam.name
    elseif L > fam.L + VAR_MARGIN then
        return "light_" .. fam.name
    end
    return fam.name
end

-- Ordering ranks so the baked palette reads as a gradient: neutrals first
-- (black -> white), then chromatic families around the hue wheel, and within a
-- family the dark_ -> base -> light_ variants.
local NEUTRAL_RANK = { black = 0, dark_gray = 1, gray = 2, light_gray = 3, white = 4 }
local VARIANT_RANK = { dark = 0, base = 1, light = 2 }

--- Sort rank for a color *name* (as returned by nearest()). Colors are grouped
--- by name (all shades of a name share a rank); ranks order the groups into a
--- gradient. Within a name, order by lightness (see M.lightness).
---@param name string
---@return number
function M.name_rank(name)
    ensure()
    if NEUTRAL_RANK[name] then
        return NEUTRAL_RANK[name]
    end
    local variant, core = "base", name
    local d = name:match("^dark_(.+)$")
    local l = name:match("^light_(.+)$")
    if d then
        variant, core = "dark", d
    elseif l then
        variant, core = "light", l
    end
    -- Brown slots just after orange in the spectrum.
    local fo
    if core == "brown" then
        fo = (family_order.orange or 0) + 0.5
    else
        fo = family_order[core] or 999
    end
    return 100 + fo * 3 + VARIANT_RANK[variant]
end

return M
