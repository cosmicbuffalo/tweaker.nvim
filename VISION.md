# tweaker.nvim — Product Vision

> This is a living document. It captures, in plain language, the full shared
> vision for what `tweaker.nvim` is and how it should behave. It is updated
> whenever new requirements or expectations are described. Implementation status
> lives in the README roadmap; this file is about *intent*, not progress.

## The one-liner

`tweaker.nvim` lets you inspect, live-edit, and persist Neovim highlight-group
colors and priorities from a floating window — then bake your accumulated tweaks
into a real, shareable colorscheme.

## Why "tweaker"

The name plays on being "high" (as in highlights) and on "tweaking" — both the
drug-culture slang and the literal act of tweaking color values. You are, quite
literally, a tweaker fine-tuning your highlights.

## Who it's for

Someone who lives in their editor and wants to adjust their colorscheme *in
context* — seeing a real buffer, pointing at text whose color feels wrong, and
changing it on the spot with immediate visual feedback — instead of blindly
editing a colorscheme file and reloading to see the effect.

## Core concepts

- **Highlight groups under the cursor.** At any cursor position, multiple
  highlight sources can contribute: treesitter captures, LSP semantic tokens,
  `:syntax` groups, and extmarks. Each has a **priority**; the highest-priority
  one is what you actually see. The plugin surfaces all of them so you understand
  *why* text looks the way it does.
- **Priority ladder.** Neovim's `vim.hl.priorities`: syntax `50`, treesitter
  `100`, semantic tokens `125`, diagnostics `150`, user extmarks `200`.

## Commands

1. **Inspect (read-only).** Opens a floating window near the cursor showing the
   highlight groups affecting the text under the cursor, with their details. A
   quick "what is this color?" peek.
2. **Tweak (editable, live).** Opens a similar floating window that additionally
   lets you edit values and see the changes reflected in the rendered
   colorscheme in **real time**.
   - By default it loads the highlight groups under the cursor.
   - It also accepts arguments: any number of highlight group names, to edit
     those specific groups instead of the ones under the cursor.

## The floating window UX

- **Placement.** Opens **two lines below** the cursor's location (offset slightly
  right), so the code under inspection stays visible above it.
- **Leader line.** A connector is overlaid from the cursor down to the window,
  visually tying it to the exact location it describes, and **joins the window's
  border cleanly** (no gap). The window is **always** placed to the right of the
  cursor, and when there isn't room it is **clamped to the screen's right edge** —
  never moved to the left of the cursor. Two resulting joins:
  - **Window lands to the right of the cursor** (the common case): the connector
    drops, turns a rounded corner, and runs into the window's **left edge — the
    cell immediately below the top-left corner** — shown as a `┤` junction.

    ```
    this is an ex*mple line of text     (* = cursor)
                 │
                 │  ╭──── Tweaker · under cursor ──╮
                 ╰──┤  … table …                   │
                    ╰───────────────────────────────╯
    ```
  - **Window is clamped to the right edge** (cursor too far right): the cursor now
    sits over the window's span, so the connector drops **straight down into the
    top border** at the cursor's column, shown as a `┴` junction (or `├`/`┤` if it
    lands exactly on a corner). The title is placed on the side away from the join.

    ```
    … a very long line of text … here*
                                     │
        ╭──── Tweaker … ────────────┴────╮
        │  … table …                     │
        ╰─────────────────────────────────╯
    ```
- **Source indicator.** The original cursor location in the underlying buffer is
  highlighted prominently (an obvious marker) while focus is in the tweaker
  window, so it's always clear which location the window is describing.
- **Source stays active.** Opening the tweaker window must not cause the window
  it was invoked from to dim to its "inactive" colors, even though the float
  takes focus. The source window keeps its active appearance for as long as the
  tweaker window is open, and is restored to normal behavior afterward.
- **Colors are explicit and customizable.** The window background, border, leader
  line, and cursor marker are driven by dedicated `Tweaker*` highlight groups —
  deliberately **not** tied to `Normal` — so they look consistent across
  colorschemes and can be customized by the user. Defaults:
  - `TweakerNormal` — window background: black bg, white fg
  - `TweakerBorder` — border/title: black bg, yellow fg
  - `TweakerConnector` — leader line: black bg, yellow fg (matches the border)
  - `TweakerCursor` — source cursor location: white bg, black fg
- **Table layout.** Selected highlight groups are shown in a table, **sorted by
  priority**. Columns, left to right:
  - `SOURCE` — non-editable (treesitter / semantic / syntax / extmark)
  - `GROUP` — non-editable (rendered in its own highlight, as a live swatch)
  - `FG` (foreground color) — **editable**
  - `BG` (background color) — **editable**
  - `PRIORITY` — **editable**
- **Editable vs. non-editable.** Only `PRIORITY`, `FG`, and `BG` are editable.
  Everything else — labels, source, group name, column gaps — is rendered as
  **virtual text** (the same technique the oil.nvim virtual-columns fork uses).
  Because non-editable content isn't real buffer text, the cursor simply cannot
  land on it.
- **Cursor confinement.** The cursor can only land on editable cells. Navigation
  uses normal Vim motions; the cursor snaps across the virtual (non-editable)
  regions between editable cells.
- **Editing.** Editable cell contents are changed with normal Vim buffer editing.
- **Empty cells.** If a group lacks a value (e.g. no background color), the cell
  renders a `-` as **virtual text** — but the cell still has a real, landable
  starting position. The moment the user edits that cell, the `-` placeholder
  stops rendering.
- **No reflow on edit.** Every cell that *could* hold a color string is padded to
  at least the width of a color string (`#rrggbb`). Adding a color to a
  previously-empty cell must never resize the floating window. Editable cells also
  hold their fixed width *while being edited* (overtype-style: typing consumes a
  trailing pad, deleting restores one) so the other columns never shift mid-edit.
- **Stepping colors.** With the cursor over a hex color, `<M-Up>` / `<M-Down>`
  increment / decrement the individual R, G, or B component the cursor is on,
  clamped to the `00`–`ff` range, for quick fine-tuning without retyping.

## Live preview

Edits are applied to the running Neovim session immediately (via `nvim_set_hl`),
so the actual rendered colorscheme updates as you type.

## Persistence

- All edits to the current colorscheme are stored in a persisted file so that,
  if Neovim is restarted, the edits are re-applied on the next startup.
- Overrides re-apply on colorscheme load so they survive both restarts and
  colorscheme switches.

## Export to a colorscheme

The user can take all their accumulated highlight-group changes from the
persisted file and use them to create or edit an actual colorscheme plugin —
turning ad-hoc tweaks into a real, shareable artifact.

## Guiding principles

- **In-context editing.** Always tie changes back to real, visible text.
- **Immediate feedback.** See it as you change it.
- **Non-destructive & recoverable.** Tweaks live in a file you own and can
  export, reset, or hand-edit.
- **Native feel.** Normal Vim motions and editing; behavior consistent with
  plugins like oil.nvim.
