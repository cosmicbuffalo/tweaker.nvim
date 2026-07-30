# tweaker.nvim

> Get your colorscheme faded. Inspect, tweak, and live-preview Neovim highlight
> groups from a floating window — then bake your edits into a real colorscheme.

`tweaker.nvim` lets you see exactly which highlight groups paint the text under
your cursor (and at what priority), edit their colors in place, watch the change
render in real time, and persist those tweaks so they survive restarts.

> [!NOTE]
> **Status: early development.** Live editing of foreground/background colors
> (`:Tweaker`) and persistence of overrides work today; colorscheme export is on
> the roadmap below.

## Requirements

- Neovim >= 0.10 (uses `vim.inspect_pos`, `vim.hl.priorities`)

## Install (lazy.nvim)

```lua
{
    "cosmicbuffalo/tweaker.nvim",
    -- Load at startup so persisted overrides are re-applied to your colorscheme.
    lazy = false,
    config = function()
        require("tweaker").setup({
            auto_save = false, -- persist only on :TweakerSave (true = persist on every edit)
            -- path = vim.fn.stdpath("data") .. "/tweaker/overrides.json",
        })
    end,
}
```

### Local development

```lua
{
    dir = vim.fn.expand("~/tweaker.nvim"),
    lazy = false,
    config = function()
        require("tweaker").setup()
    end,
}
```

## Commands

| Command             | Description                                                          |
| ------------------- | ------------------------------------------------------------------- |
| `:Tweaker [group…]` | Open an editable float. With no arguments, edit the groups under the cursor; with group names, edit those groups. |
| `:TweakerToggle`    | Toggle application of your overrides on/off (persisted + session).   |
| `:TweakerSave`      | Persist the current overrides to disk.                               |
| `:TweakerLoad`      | Discard unsaved tweaks and reload the persisted overrides from disk. |

Table columns: `SOURCE · GROUP · FG · BG · PRIORITY`. **FG and BG are editable**
(PRIORITY is read-only for now). Navigate between the FG/BG cells with normal Vim
motions (or `<Tab>`/`<S-Tab>`); edit a cell with normal editing. Accepted values:
a hex color `#rrggbb` or `NONE` (clears the attribute). Changes apply to the
running session live via `nvim_set_hl` as you edit; an empty cell shows `-` until
you type into it. Color cells keep a fixed width while you edit, so the other
columns stay aligned. With the cursor over a hex code, `<M-Up>` / `<M-Down>`
increment / decrement the R/G/B component under the cursor (clamped `00`–`ff`).

Inside the float: `q` / `<C-c>` to close.

## Persistence

Overrides are stored per-colorscheme in a JSON file (default
`stdpath("data")/tweaker/overrides.json`) and re-applied to the matching
colorscheme on startup and whenever the colorscheme changes.

- `auto_save = true` writes to disk on every committed edit.
- `auto_save = false` (default) keeps edits in the session until `:TweakerSave`;
  `:TweakerLoad` throws away unsaved edits and restores the last saved state.
- `:TweakerToggle` flips all overrides off/on (handy on a keymap) so you can
  compare against the untouched colorscheme.

## Roadmap

- [x] `:Tweaker [group…]` — editable table with live fg/bg preview
- [x] Persist overrides across restarts (reapply on `ColorScheme`/startup)
- [x] Toggle overrides on/off; save/load
- [ ] Export overrides to a standalone colorscheme
- [ ] Editable priority

## How it works

Highlight sources are gathered with `vim.inspect_pos`, which reports treesitter
captures, LSP semantic tokens, `:syntax` groups, and extmarks — each already
carrying its highlight group and draw priority. Priorities follow Neovim's
ladder (`vim.hl.priorities`): syntax `50`, treesitter `100`, semantic tokens
`125`, up to user extmarks `200`.
