describe("export", function()
    local export

    local function fresh(cfg)
        package.loaded["tweaker.overrides"] = nil
        require("tweaker").setup(vim.tbl_extend("force", { path = vim.fn.tempname() }, cfg or {}))
        package.loaded["tweaker.export"] = nil
        export = require("tweaker.export")
    end

    local function set_line(src, group)
        for line in src:gmatch("[^\n]+") do
            if line:find('set%(0, "' .. group .. '"', 1) then
                return line
            end
        end
    end

    before_each(function()
        vim.g.colors_name = "exptest"
        fresh()
        vim.api.nvim_set_hl(0, "Normal", { fg = tonumber("c0caf5", 16), bg = tonumber("1a1b26", 16) })
    end)

    it("emits a palette table and references it from set() calls (no raw hex in set)", function()
        local src = export.generate("t")
        assert.matches("local p = {", src, 1, true)
        local line = set_line(src, "Normal")
        assert.is_not_nil(line)
        assert.matches("p%.", line) -- references a palette var
        assert.is_nil(line:find("#", 1, true)) -- ...not a literal hex
    end)

    it("skips machine-generated transient groups", function()
        vim.api.nvim_set_hl(0, "LspDocumentColor_ff0000_background", { bg = tonumber("ff0000", 16) })
        vim.api.nvim_set_hl(0, "TweakerSwatch_00ff00", { fg = tonumber("00ff00", 16) })
        local src = export.generate("t")
        assert.is_nil(src:find("LspDocumentColor", 1, true))
        assert.is_nil(src:find("TweakerSwatch", 1, true))
        assert.is_not_nil(set_line(src, "Normal")) -- real groups still present
    end)

    it("honors the bake_ignore config option", function()
        vim.api.nvim_set_hl(0, "ZZZCustomTransient", { fg = tonumber("112233", 16) })
        fresh({ bake_ignore = { "^ZZZ" } })
        local src = export.generate("t")
        assert.is_nil(src:find("ZZZCustomTransient", 1, true))
    end)

    it("preserves links in the output", function()
        vim.api.nvim_set_hl(0, "ExpTarget", { fg = tonumber("00aaff", 16) })
        vim.api.nvim_set_hl(0, "ExpLinked", { link = "ExpTarget" })
        local src = export.generate("t")
        assert.matches('set%(0, "ExpLinked", { link = "ExpTarget" }', src)
    end)
end)
