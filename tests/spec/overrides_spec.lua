describe("overrides", function()
    local overrides
    local tmp
    local notify

    local function fresh(cfg)
        package.loaded["tweaker.overrides"] = nil
        overrides = require("tweaker.overrides")
        overrides.setup(vim.tbl_extend("force", { path = tmp, auto_save = false }, cfg or {}))
    end

    before_each(function()
        notify = _G.test_helpers.silence_notify()
        tmp = vim.fn.tempname()
        vim.g.colors_name = "ovtest"
        fresh()
    end)

    after_each(function()
        notify.restore()
        vim.fn.delete(tmp)
    end)

    it("set() records and applies an override live", function()
        overrides.set("OvA", "#ff0000", nil)
        assert.is_true(overrides.has("OvA"))
        assert.equals(tonumber("ff0000", 16), vim.api.nvim_get_hl(0, { name = "OvA" }).fg)
    end)

    it("captures base for a linked group and relinks on clear", function()
        vim.api.nvim_set_hl(0, "OvTarget", { fg = tonumber("00ff00", 16) })
        vim.api.nvim_set_hl(0, "OvLink", { link = "OvTarget" })
        overrides.set("OvLink", "#ff0000", nil)
        assert.is_true(overrides.has_base("OvLink"))
        assert.equals(tonumber("ff0000", 16), vim.api.nvim_get_hl(0, { name = "OvLink" }).fg)

        overrides.clear("OvLink")
        assert.is_false(overrides.has("OvLink"))
        assert.equals("OvTarget", vim.api.nvim_get_hl(0, { name = "OvLink" }).link)
    end)

    it("captures inherit base for an empty group and clears to empty", function()
        overrides.set("OvEmpty", "#ff0000", nil) -- OvEmpty is undefined => inherited
        assert.is_true(overrides.has_base("OvEmpty"))
        overrides.clear("OvEmpty")
        assert.are.same({}, vim.api.nvim_get_hl(0, { name = "OvEmpty" }))
    end)

    it("records no base for a group with its own colors", function()
        vim.api.nvim_set_hl(0, "OvOwn", { fg = tonumber("0000ff", 16) })
        overrides.set("OvOwn", "#ff0000", nil)
        assert.is_true(overrides.has("OvOwn"))
        assert.is_false(overrides.has_base("OvOwn"))
    end)

    it("clear(group, orig) restores the explicit original", function()
        overrides.set("OvB", "#ff0000", { link = "Comment" })
        overrides.clear("OvB", { link = "Comment" })
        assert.equals("Comment", vim.api.nvim_get_hl(0, { name = "OvB" }).link)
    end)

    it("save() writes valid, structured JSON", function()
        overrides.set("OvSave", "#123456", nil)
        overrides.save()
        local f = assert(io.open(tmp, "r"))
        local content = f:read("*a")
        f:close()
        local decoded = vim.json.decode(content)
        assert.is_table(decoded.ovtest)
        assert.equals("#123456", decoded.ovtest.OvSave.fg)
    end)

    it("setup() loads persisted overrides from disk and applies them", function()
        -- Write a store, then start a fresh module pointed at it.
        local f = assert(io.open(tmp, "w"))
        f:write(vim.json.encode({ ovtest = { OvDisk = { fg = "#abcdef" } } }))
        f:close()
        fresh()
        assert.is_true(overrides.has("OvDisk"))
        assert.equals(tonumber("abcdef", 16), vim.api.nvim_get_hl(0, { name = "OvDisk" }).fg)
    end)
end)
