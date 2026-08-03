# tweaker.nvim

> Meet your new favorite color scheme editor. Tweak Neovim highlight groups from
> a floating window and see them update live — then bake your edits into a real colorscheme.

Don't stop what you're doing and stew in frustration whenever you come across a color
that grates on your eyes! Just tweak it to your liking real quick and get back to 
whatever you were doing. 

When you're happy with your color scheme and ready to bake it, run `:TweakerBake` to turn
your Tweaker overrides into a new color scheme file!

> [!NOTE]
> **Status: early development.** Live editing (`:Tweaker`), persistence, and
> exporting to a standalone colorscheme (`:TweakerBake`) work today.

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

    -- Extra/override anchor colors ({ name = "#hex" }) used to name palette
    -- variables in :TweakerBake. Merged over the built-in anchors.
    colors = {},
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
| `:TweakerBake[!] [name]` | Export the current highlights + your tweaks to a standalone colorscheme `colors/<name>.lua` (bang to overwrite). |

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

## Export

`:TweakerBake[!] [name]` writes a **standalone** colorscheme to
`stdpath("config")/colors/<name>.lua` (default name `<current>-tweaked`), snapshotting
every highlight group in the current session — base colorscheme + your applied
tweaks — so it loads with no dependency on tweaker or the base scheme.

Every unique color is hoisted into a named **palette variable** referenced by the
`set` calls, so no hex appears twice:

```lua
local p = {
  black_1     = "#000000", -- 1 group: Normal
  gray_1      = "#767676", -- 2 groups: Comment, LineNr
  white_1     = "#ffffff", -- 1 group: CursorLine
  red_1       = "#ff0000", -- 1 group: Error
  blue_1      = "#0078d4", -- 3 groups: Function, Identifier, Type
  blue_2      = "#5599dd", -- 1 group: Special
  light_blue_1 = "#00a2ff", -- 1 group: Title
  -- … grouped by name, laid out as a gradient …
}
local set = vim.api.nvim_set_hl
set(0, "Normal",  { fg = p.light_blue_1, bg = p.black_1 })
set(0, "Comment", { fg = p.gray_1, italic = true })
```

Each palette entry carries a comment listing how many highlight groups use that
color and which ones (links carry no color, so they're excluded). Variable names
come from the nearest match in a perceptual color space (OKLCh):
low-chroma colors are named among the neutrals (`black`/`gray`/`white`) by
lightness, and chromatic colors pick a family by hue (`red`/`blue`/`purple`/…),
then a `dark_`/`light_` variant relative to that family's own lightness. The
palette is laid out as a **gradient**: grouped by name, the groups ordered
around the spectrum, and the shades within each name numbered `_1`, `_2`, … from
darkest to lightest. The anchor colors are fully overridable via the `colors`
option.

It refuses to overwrite an existing file unless you use the bang (`:TweakerBake! name`).

## Roadmap

- [x] `:Tweaker [group…]` — editable table with live fg/bg preview
- [x] Persist overrides across restarts (reapply on `ColorScheme`/startup)
- [x] Toggle overrides on/off; save/load
- [x] Export overrides to a standalone colorscheme (named palette variables)
- [ ] Editable priority

## How it works

Highlight sources are gathered with `vim.inspect_pos`, which reports treesitter
captures, LSP semantic tokens, `:syntax` groups, and extmarks — each already
carrying its highlight group and draw priority. Priorities follow Neovim's
ladder (`vim.hl.priorities`): syntax `50`, treesitter `100`, semantic tokens
`125`, up to user extmarks `200`.
