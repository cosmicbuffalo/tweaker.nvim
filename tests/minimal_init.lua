-- Minimal init for running the test suite with plenary.
-- Usage: PLENARY_DIR=/path/to/plenary.nvim nvim --headless --noplugin \
--   -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec"

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local plugin_dir = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h:h")

vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(plugin_dir)
vim.cmd("runtime! plugin/plenary.vim")

-- tweaker needs truecolor for its highlight handling.
vim.o.termguicolors = true

_G.test_helpers = {
    -- Capture vim.notify calls; returns { restore = fn }.
    silence_notify = function()
        local original = vim.notify
        vim.notify = function() end
        return {
            restore = function()
                vim.notify = original
            end,
        }
    end,
}
