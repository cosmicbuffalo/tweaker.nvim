-- Isolated Neovim config for recording the tweaker.nvim demo.
--
-- Loads ONLY inkline (original) + tweaker, with real treesitter highlighting for
-- the Lua source we tour. It reads no user config and writes no user data — the
-- recorder (demo/record.sh) points XDG_* at throwaway dirs and passes the plugin
-- locations via TWEAKER_DIR / INKLINE_DIR.

vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.hlsearch = false
vim.opt.signcolumn = "no"
vim.opt.laststatus = 0
vim.opt.ruler = false
vim.opt.showcmd = false
vim.opt.scrolloff = 4
vim.opt.fillchars = { eob = " " }

local function add(dir)
    if dir and dir ~= "" and vim.fn.isdirectory(dir) == 1 then
        vim.opt.rtp:prepend(dir)
    end
end
add(vim.env.TWEAKER_DIR ~= "" and vim.env.TWEAKER_DIR or vim.fn.getcwd())
add(vim.env.INKLINE_DIR)

-- Real treesitter highlighting for the Lua files we tour (built-in parser).
vim.api.nvim_create_autocmd("FileType", {
    pattern = "lua",
    callback = function(args)
        pcall(vim.treesitter.start)
        -- Force a synchronous parse so `:Tweaker` sees captures immediately.
        pcall(function()
            vim.treesitter.get_parser(args.buf):parse(true)
        end)
    end,
})

vim.cmd.colorscheme("inkline-original")
require("tweaker").setup({ auto_save = false })
