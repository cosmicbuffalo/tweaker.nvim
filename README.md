# tweaker.nvim

> Meet your new favorite color scheme editor. Tweak Neovim highlight groups from
> a floating window and see them update live — then bake your edits into a real colorscheme.

`tweaker.nvim` lets you see exactly which highlight groups paint the text under
your cursor (and at what priority), edit their colors in place, watch the change
render in real time, and persist those tweaks so they survive restarts.

Don't stop what you're doing and stew in frustration whenever you come across a color
that grates on your eyes! Just tweak it to your liking real quick and get back to 
whatever you were doing. Your Tweaker color overrides will be ready and waiting for
whenever you want to actually update your color scheme at
`~/.local/share/nvim/tweaker/overrides.json`

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
    opts = {
        auto_save = false,
    },
}
```

### Local development

```lua
{
    dir = vim.fn.expand("~/tweaker.nvim"),
    lazy = false,
    opts = {},
}
```

## Configuration

`opts` is passed to `require("tweaker").setup()`. Defaults:

```lua
{
    -- Persist overrides to disk on every committed edit. When false, edits stay
    -- in the session until you run :TweakerSave (and :TweakerLoad discards them).
    auto_save = false,

    -- Where overrides are stored (JSON, keyed per colorscheme).
    path = vim.fn.stdpath("data") .. "/tweaker/overrides.json",
}
```

### Appearance

The window's colors come from dedicated, overridable highlight groups (they are
intentionally **not** linked to `Normal`). Set them yourself to restyle the
window — for example:

```lua
vim.api.nvim_set_hl(0, "TweakerBorder", { fg = "#e6c200", bg = "#101010" })
```

| Group              | Default                    | Used for                              |
| ------------------ | -------------------------- | ------------------------------------- |
| `TweakerNormal`    | white on black             | window background                     |
| `TweakerBorder`    | yellow on black            | border + title                        |
| `TweakerConnector` | yellow on black            | the leader line to the cursor         |
| `TweakerCursor`    | black on white             | the source cursor location marker     |
| `TweakerHeader`    | links `Title`              | the column header row                 |
| `TweakerSource`    | links `Comment`            | the SOURCE column                     |
| `TweakerPriority`  | links `Number`             | the PRIORITY column                   |
| `TweakerEmpty`     | links `Comment`            | the `-` placeholder for empty cells   |

## Commands

| Command             | Description                                                          |
| ------------------- | ------------------------------------------------------------------- |
| `:Tweaker [group…]` | Open an editable float. With no arguments, edit the groups under the cursor; with group names, edit those groups. |
| `:TweakerToggle`    | Toggle application of your overrides on/off (persisted + session).   |
| `:TweakerSave`      | Persist the current overrides to disk.                               |
| `:TweakerLoad`      | Discard unsaved tweaks and reload the persisted overrides from disk. |
| `:TweakerOpenOverrides` | Open the overrides JSON file in the current window.             |

Table columns: `SOURCE · GROUP · FG · BG · PRIORITY`. **FG and BG are editable**
(PRIORITY is read-only for now). Navigate between the FG/BG cells with normal Vim
motions (or `<Tab>`/`<S-Tab>`); edit a cell with normal editing. Accepted values:
a hex color `#rrggbb` or `NONE` (clears the attribute). Changes apply to the
running session live via `nvim_set_hl` as you edit; an empty cell shows `-` until
you type into it. Color cells keep a fixed width while you edit, so the other
columns stay aligned. With the cursor over a hex code, `<M-Up>` / `<M-Down>`
increment / decrement the R/G/B component under the cursor (clamped `00`–`ff`).

A group that only **links** to another is shown as `group → target` with blank
FG/BG cells (its colors come from the target). Typing a color into one of those
cells **unlinks** the group and gives it that color directly.

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
