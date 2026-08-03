local palette = require("tweaker.palette")

describe("palette", function()
    before_each(function()
        palette.setup({})
    end)

    describe("nearest", function()
        -- Cases pinned during naming tuning; keep them as regression anchors.
        local cases = {
            ["#000000"] = "black",
            ["#ffffff"] = "white",
            ["#808080"] = "gray",
            ["#ff0000"] = "red",
            ["#8b0000"] = "dark_red",
            ["#ffa500"] = "orange",
            ["#ffff00"] = "yellow",
            ["#0078d4"] = "blue",
            ["#9d7cd8"] = "purple",
        }
        for hex, name in pairs(cases) do
            it(("names %s -> %s"):format(hex, name), function()
                assert.equals(name, palette.nearest(hex))
            end)
        end

        it("keeps blues out of the purple family and vice versa", function()
            assert.matches("blue", palette.nearest("#0078d4"))
            assert.matches("purple", palette.nearest("#9d7cd8"))
        end)

        it("honors custom anchor colors", function()
            palette.setup({ hotpink = "#ff69b4" })
            assert.matches("hotpink", palette.nearest("#ff69b4"))
        end)
    end)

    describe("lightness", function()
        it("orders dark < mid < light", function()
            assert.is_true(palette.lightness("#000000") < palette.lightness("#808080"))
            assert.is_true(palette.lightness("#808080") < palette.lightness("#ffffff"))
        end)

        it("returns a number in ~0..1", function()
            local l = palette.lightness("#00aaff")
            assert.is_true(l > 0 and l < 1)
        end)
    end)
end)
