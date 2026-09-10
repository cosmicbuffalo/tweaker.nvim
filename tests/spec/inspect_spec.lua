-- Ordering behavior of tweaker.inspect.collect: the group that actually paints
-- the cell must come first (so it's in the obvious position and the cursor,
-- which starts on the first row, lands on it). vim.inspect_pos is stubbed so the
-- test doesn't depend on treesitter parsers being installed.
describe("inspect ordering", function()
    local inspect = require("tweaker.inspect")
    local PRI = (vim.hl or vim.highlight).priorities

    local saved_inspect_pos
    local groups = {} -- names we set, to clean up

    -- Register a real highlight group so util.resolve() sees its attributes.
    local function hl(name, attrs)
        groups[#groups + 1] = name
        vim.api.nvim_set_hl(0, name, attrs)
    end

    -- Build a fake vim.inspect_pos payload. `ts` is a list of treesitter groups
    -- in application order (later = drawn on top); each is { group } or
    -- { group, priority }. `extra` may add semantic_tokens / syntax / extmarks.
    local function stub(ts, extra)
        extra = extra or {}
        local treesitter = {}
        for i, t in ipairs(ts) do
            treesitter[i] = {
                hl_group = t[1],
                id = i,
                metadata = t[2] and { priority = t[2] } or {},
            }
        end
        vim.inspect_pos = function()
            return {
                treesitter = treesitter,
                syntax = extra.syntax or {},
                semantic_tokens = extra.semantic_tokens or {},
                extmarks = extra.extmarks or {},
            }
        end
    end

    before_each(function()
        saved_inspect_pos = vim.inspect_pos
    end)

    after_each(function()
        vim.inspect_pos = saved_inspect_pos
        for _, name in ipairs(groups) do
            pcall(vim.api.nvim_set_hl, 0, name, {})
        end
        groups = {}
    end)

    it("puts the fg-painting group first even when a color-less group is on top", function()
        -- Mirrors a markdown link: transparent captures (@spell/@nospell) sit
        -- above the one group that defines the visible foreground.
        hl("@spell", {})
        hl("@markup.link", {})
        hl("@markup.link.url", { fg = tonumber("ff0000", 16) }) -- the red one
        hl("@nospell", {})
        stub({
            { "@spell" }, -- order 1 (bottom)
            { "@markup.link" }, -- order 2
            { "@markup.link.url" }, -- order 3 (paints fg)
            { "@nospell" }, -- order 4 (top, but transparent)
        })

        local items = inspect.collect(0, 0, 0)
        assert.equals("@markup.link.url", items[1].group)
    end)

    it("later of two equal-priority captures with fg wins", function()
        hl("@comment", { fg = tonumber("888888", 16) })
        hl("@comment.documentation", { fg = tonumber("00ff00", 16) })
        stub({
            { "@comment" }, -- order 1
            { "@comment.documentation" }, -- order 2 (drawn on top)
        })

        local items = inspect.collect(0, 0, 0)
        assert.equals("@comment.documentation", items[1].group)
    end)

    it("a higher-priority contribution wins over a lower-priority colored one", function()
        hl("@variable", { fg = tonumber("ff0000", 16) })
        hl("SemanticProperty", { fg = tonumber("0000ff", 16) })
        stub({ { "@variable" } }, {
            semantic_tokens = {
                { opts = { hl_group = "SemanticProperty", priority = PRI.semantic_tokens } },
            },
        })

        local items = inspect.collect(0, 0, 0)
        assert.equals("SemanticProperty", items[1].group)
    end)

    it("falls back to the bg provider when nothing defines an fg", function()
        hl("@spell", {})
        hl("CursorLine", { bg = tonumber("222222", 16) })
        stub({
            { "@spell" }, -- order 1
            { "CursorLine" }, -- order 2 (paints bg)
        })

        local items = inspect.collect(0, 0, 0)
        assert.equals("CursorLine", items[1].group)
    end)
end)
