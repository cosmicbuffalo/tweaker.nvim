# tweaker.nvim

> Get your colorscheme faded. Inspect, tweak, and live-preview Neovim highlight
> groups from a floating window — then bake your edits into a real colorscheme.

`tweaker.nvim` lets you see exactly which highlight groups paint the text under
your cursor (and at what priority), edit their colors in place, watch the change
render in real time, and persist those tweaks so they survive restarts.

> [!NOTE]
> **Status: early development.** The read-only `:TweakerInspect` command works
> today. The interactive editor, persistence, and colorscheme export are on the
> roadmap below.

## Requirements

- Neovim >= 0.10 (uses `vim.inspect_pos`, `vim.hl.priorities`)

## Install (lazy.nvim)

```lua
{
    "yourname/tweaker.nvim",
    cmd = { "TweakerInspect" },
    config = function()
        require("tweaker").setup()
    end,
}
```

### Local development

```lua
{
    dir = vim.fn.expand("~/tweaker.nvim"),
    cmd = { "TweakerInspect" },
    config = function()
        require("tweaker").setup()
    end,
}
```

## Commands

| Command           | Description                                                            |
| ----------------- | --------------------------------------------------------------------- |
| `:TweakerInspect` | Open a float near the cursor listing every highlight group under it, sorted by priority (highest — the one that actually wins — first). |

Inside the float: `q` / `<Esc>` to close.

## Roadmap

- [x] `:TweakerInspect` — read-only inspection of groups under the cursor
- [ ] `:Tweaker [groups...]` — editable table with live preview
- [ ] Persist overrides across restarts
- [ ] Export overrides to a standalone colorscheme

## How it works

Highlight sources are gathered with `vim.inspect_pos`, which reports treesitter
captures, LSP semantic tokens, `:syntax` groups, and extmarks — each already
carrying its highlight group and draw priority. Priorities follow Neovim's
ladder (`vim.hl.priorities`): syntax `50`, treesitter `100`, semantic tokens
`125`, up to user extmarks `200`.
