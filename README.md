# tweaker.nvim

> Get your colorscheme faded. Inspect, tweak, and live-preview Neovim highlight
> groups from a floating window — then bake your edits into a real colorscheme.

`tweaker.nvim` lets you see exactly which highlight groups paint the text under
your cursor (and at what priority), edit their colors in place, watch the change
render in real time, and persist those tweaks so they survive restarts.

> [!NOTE]
> **Status: early development.** Inspecting (`:TweakerInspect`) and live editing
> of foreground/background colors (`:Tweaker`) work today. Persistence across
> restarts and colorscheme export are on the roadmap below.

## Requirements

- Neovim >= 0.10 (uses `vim.inspect_pos`, `vim.hl.priorities`)

## Install (lazy.nvim)

```lua
{
    "cosmicbuffalo/tweaker.nvim",
    cmd = { "TweakerInspect", "Tweaker" },
    config = function()
        require("tweaker").setup()
    end,
}
```

### Local development

```lua
{
    dir = vim.fn.expand("~/tweaker.nvim"),
    cmd = { "TweakerInspect", "Tweaker" },
    config = function()
        require("tweaker").setup()
    end,
}
```

## Commands

| Command             | Description                                                          |
| ------------------- | ------------------------------------------------------------------- |
| `:TweakerInspect`   | Open a read-only float near the cursor listing every highlight group under it, sorted by priority (highest — the one that actually wins — first). |
| `:Tweaker [group…]` | Open an editable float. With no arguments, edit the groups under the cursor; with group names, edit those groups. |

Table columns: `SOURCE · GROUP · FG · BG · PRIORITY`. **FG and BG are editable**
(PRIORITY is read-only for now). Navigate between the FG/BG cells with normal Vim
motions (or `<Tab>`/`<S-Tab>`); edit a cell with normal editing. Accepted values:
a hex color `#rrggbb` or `NONE` (clears the attribute). Changes apply to the
running session live via `nvim_set_hl` as you edit; an empty cell shows `-` until
you type into it.

Inside the float: `q` / `<Esc>` to close.

## Roadmap

- [x] `:TweakerInspect` — read-only inspection of groups under the cursor
- [x] `:Tweaker [group…]` — editable table with live fg/bg preview
- [ ] Persist overrides across restarts (reapply on `ColorScheme`/startup)
- [ ] Export overrides to a standalone colorscheme
- [ ] Editable priority

## How it works

Highlight sources are gathered with `vim.inspect_pos`, which reports treesitter
captures, LSP semantic tokens, `:syntax` groups, and extmarks — each already
carrying its highlight group and draw priority. Priorities follow Neovim's
ladder (`vim.hl.priorities`): syntax `50`, treesitter `100`, semantic tokens
`125`, up to user extmarks `200`.
