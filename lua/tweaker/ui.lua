local util = require("tweaker.util")

local M = {}

local ns_src = vim.api.nvim_create_namespace("tweaker.source") -- source-buffer cursor indicator
local ns = vim.api.nvim_create_namespace("tweaker.render") -- float chrome (persistent extmarks)

-- Editable color fields are fixed-width so columns never reflow and byte offsets
-- stay constant. The field is one cell wider than a color ("#rrggbb" = 7), so a
-- complete color always has a trailing pad space *inside* the field — that gives
-- the cursor a real place to rest right after the last hex digit (before the gap),
-- and removes the fg/bg boundary ambiguity. Real text of a data row is two fields:
-- FG = [0, FIELD_W), BG = [FIELD_W, LINE_LEN). Everything else (source, group,
-- priority, gaps, swatches, "-") is virtual "chrome".
local COLOR_W = 7 -- width of "#rrggbb"
local FIELD_W = COLOR_W + 1 -- color + trailing pad
local GAP = 2
local FG_S = 0
local BG_S = FIELD_W
local LINE_LEN = FIELD_W * 2
local CELLS = { { FG_S, BG_S }, { BG_S, LINE_LEN } }

M.FIELD_W = FIELD_W
M.LINE_LEN = LINE_LEN

-- Per-buffer session state (cell ranges, data-line bounds, cleanup info).
---@type table<integer, table>
local sessions = {}

-- Define default highlight groups (user-overridable). Colors are explicit and
-- decoupled from Normal so the float looks consistent across colorschemes.
local function ensure_hl()
    local defs = {
        TweakerNormal = { fg = "#ffffff", bg = "#000000" }, -- window background
        TweakerBorder = { fg = "#ffff00", bg = "#000000" }, -- border (black bg, yellow fg)
        TweakerConnector = { fg = "#ffff00", bg = "#000000" }, -- leader line (matches border)
        TweakerCursor = { fg = "#000000", bg = "#ffffff" }, -- source cursor location
        TweakerHeader = { link = "Title" },
        TweakerSource = { link = "Comment" },
        TweakerPriority = { link = "Number" },
        TweakerEmpty = { link = "Comment" },
    }
    -- Struck-through "→ target" when an edit stages an unlink. Grayed like a
    -- comment, with italic + strikethrough; the arrow is also swapped for "✗" so
    -- the broken-link state shows even where strikethrough doesn't render.
    local ok_c, comment = pcall(vim.api.nvim_get_hl, 0, { name = "Comment", link = false })
    defs.TweakerStrike = { fg = (ok_c and comment.fg) or "#808080", strikethrough = true, italic = true }
    for name, val in pairs(defs) do
        val.default = true
        vim.api.nvim_set_hl(0, name, val)
    end
end

-- Cache of on-the-fly swatch groups (fg = the actual color).
local swatch_cache = {}
local function swatch_hl(color)
    if not color then
        return nil
    end
    local name = "TweakerSwatch_" .. color:sub(2)
    if not swatch_cache[name] then
        vim.api.nvim_set_hl(0, name, { fg = color })
        swatch_cache[name] = true
    end
    return name
end

--- Highlight for a group *name* label in the table. Active side: drawn in the
--- group's real (resolved) color so you can see what it looks like. Inactive
--- side: gray. Used to show which side of a `group → target` link is being edited.
local function name_hl(group, active)
    if not active then
        return "TweakerSource"
    end
    local r = util.resolve(group)
    local sw = r.fg and swatch_hl(util.hex(r.fg))
    return sw or (group ~= "" and group) or "TweakerSource"
end

local function padr(s, w)
    return s .. string.rep(" ", math.max(0, w - #s))
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

M.padr = padr
M.trim = trim

--- Build the buffer lines, per-row read-only data, and column widths. The real
--- text carries only the editable fields (fg, bg); all other columns are chrome
--- drawn by the decoration provider.
---@param items tweaker.Item[]
---@return table layout
local function build(items)
    local rows = {}
    local has_link = false
    local sw, gw, pw = #"SOURCE", #"GROUP", #"PRIORITY"
    for _, it in ipairs(items) do
        local own = it.hl or {}
        -- A group's own explicit link, or — when it has no definition of its own
        -- (e.g. a treesitter capture colored via the @-hierarchy) — the resolved
        -- provider that inspect_pos reported. Either way its color is inherited,
        -- so show it as a link with blank, editable cells.
        local link = own.link
        if not link and vim.tbl_isempty(own) and it.link and it.link ~= "" and it.link ~= it.group then
            link = it.link
        end
        has_link = has_link or (link ~= nil and link ~= "")
        local r = {
            source = it.source or "",
            group = it.group or "",
            link = link,
            priority = it.priority ~= nil and tostring(it.priority) or "",
            -- Linked groups have no own colors: show blank, editable cells.
            fg = not link and util.hex(own.fg) or nil,
            bg = not link and util.hex(own.bg) or nil,
        }
        sw = math.max(sw, #r.source)
        gw = math.max(gw, vim.fn.strdisplaywidth(r.group .. (link and (" → " .. link) or "")))
        pw = math.max(pw, #r.priority)
        rows[#rows + 1] = r
    end

    local widths = { sw = sw, gw = gw, pw = pw }
    local total_w = sw + GAP + gw + GAP + FIELD_W + GAP + FIELD_W + GAP + pw

    local lines = { "" } -- header line (chrome only)
    local descs = {} -- lnum -> { source, group, link, priority }
    local cells = {} -- lnum -> editable byte-ranges
    for i, r in ipairs(rows) do
        local lnum = i + 1
        lines[lnum] = padr(r.fg or "", FIELD_W) .. padr(r.bg or "", FIELD_W)
        descs[lnum] = { source = r.source, group = r.group, link = r.link, priority = r.priority }
        cells[lnum] = CELLS
    end

    return {
        lines = lines,
        rows = descs,
        widths = widths,
        cells = cells,
        first = 2,
        last = #rows + 1,
        width = total_w,
        has_data = #rows > 0,
        has_link = has_link,
    }
end

--- Draw the (all-virtual) header row.
local function render_header(buf, w)
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
        virt_text = {
            { padr("SOURCE", w.sw), "TweakerHeader" },
            { string.rep(" ", GAP) },
            { padr("GROUP", w.gw), "TweakerHeader" },
            { string.rep(" ", GAP) },
            { padr("FG", FIELD_W), "TweakerHeader" },
            { string.rep(" ", GAP) },
            { padr("BG", FIELD_W), "TweakerHeader" },
            { string.rep(" ", GAP) },
            { padr("PRIORITY", w.pw), "TweakerHeader" },
        },
        virt_text_pos = "inline",
    })
end

local function draw_field(buf, row, start, val)
    if val == "" then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, start, {
            virt_text = { { "-", "TweakerEmpty" } },
            virt_text_pos = "overlay",
        })
    else
        local color = util.parse_color(val)
        local hl = color and color ~= "NONE" and swatch_hl(color)
        if hl then
            pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, start, { end_col = start + #val, hl_group = hl })
        end
    end
end

--- Byte bounds of the fg/bg fields on a data line. Normally fixed (7/7); while a
--- field is being edited it absorbs the length delta, so the chrome follows it
--- without mutating the buffer mid-insert.
---@return integer fg_end, integer bg_start, integer bg_end
local function field_bounds(line, s, lnum)
    local n = #line
    if s and s.field and s.active_lnum == lnum and n ~= LINE_LEN then
        if s.field == 1 then
            local e = math.max(0, n - FIELD_W)
            return e, e, n
        end
        return FIELD_W, FIELD_W, n
    end
    return FIELD_W, FIELD_W, LINE_LEN
end

--- (Re)draw one data line's chrome from the current buffer text + read-only desc.
--- Uses dynamic field bounds so it stays correct even while a field is being
--- edited (line temporarily != LINE_LEN). Clears and rebuilds this line's marks.
local function render_line(buf, lnum, desc, w)
    local s = sessions[buf]
    local row = lnum - 1
    vim.api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local fg_end, bg_start, bg_end = field_bounds(line, s, lnum)

    -- SOURCE + GROUP prefix (before the fg field). Linked groups show
    -- "group → target"; the active side (the origin, or the link target when
    -- toggled with <C-t>) is drawn in its real color and the inactive side gray.
    -- A staged unlink (a deliberate value typed while editing the origin) strikes
    -- through "→ target".
    local origin_active = not desc.editing_target
    local vt = {
        { padr(desc.source, w.sw), "TweakerSource" },
        { string.rep(" ", GAP) },
        { desc.group, name_hl(desc.group, origin_active) },
    }
    local used = vim.fn.strdisplaywidth(desc.group)
    if desc.link and desc.link ~= "" then
        local pending = false
        if origin_active then
            local fgv = util.parse_color(trim(line:sub(FG_S + 1, fg_end)))
            local bgv = util.parse_color(trim(line:sub(bg_start + 1, bg_end)))
            pending = fgv ~= nil or bgv ~= nil
        end
        -- Swapping the arrow for ✗ is the primary, attribute-independent signal;
        -- the italic + strikethrough on TweakerStrike are extra cues on top.
        local arrow = pending and " ✗ " or " → "
        local arrow_hl = pending and "TweakerStrike" or "TweakerSource"
        local target_hl = pending and "TweakerStrike" or name_hl(desc.link, not origin_active)
        vt[#vt + 1] = { arrow, arrow_hl }
        vt[#vt + 1] = { desc.link, target_hl }
        used = used + vim.fn.strdisplaywidth(" → " .. desc.link)
    end
    if used < w.gw then
        vt[#vt + 1] = { string.rep(" ", w.gw - used) }
    end
    vt[#vt + 1] = { string.rep(" ", GAP) }
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, FG_S, {
        virt_text = vt,
        virt_text_pos = "inline",
        right_gravity = false,
    })
    draw_field(buf, row, FG_S, trim(line:sub(FG_S + 1, fg_end)))
    -- Gap between the fg and bg fields.
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, bg_start, {
        virt_text = { { string.rep(" ", GAP) } },
        virt_text_pos = "inline",
        right_gravity = false,
    })
    draw_field(buf, row, bg_start, trim(line:sub(bg_start + 1, bg_end)))
    -- PRIORITY suffix (read-only) after the bg field.
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, bg_end, {
        virt_text = { { string.rep(" ", GAP) }, { padr(desc.priority, w.pw), "TweakerPriority" } },
        virt_text_pos = "inline",
    })
end

--- Public: get a buffer's session (used by the editor module).
function M.get_session(buf)
    return sessions[buf]
end

--- Public: re-render all chrome from the current buffer text. Clears the whole
--- namespace first so nothing lingers — a full-line edit can push line-end inline
--- extmarks onto the next line, and a per-line clear would miss those.
function M.rerender(buf)
    local s = sessions[buf]
    if not s or not s.rows or not s.has_data then
        return
    end
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    render_header(buf, s.widths)
    for lnum, desc in pairs(s.rows) do
        render_line(buf, lnum, desc, s.widths)
    end
end

--- The fixed-width real text (fg + bg fields) a row should have, derived from the
--- live highlight state (edits apply live, so this is the source of truth). Linked
--- rows are blank; a row toggled to its target shows the target's own colors.
local function row_content(desc)
    local fg, bg = "", ""
    local group
    if desc.editing_target and desc.link and desc.link ~= "" then
        group = desc.link
    elseif desc.link and desc.link ~= "" then
        group = nil -- shown as a link: blank cells
    else
        group = desc.group
    end
    if group then
        local own = util.resolve(group)
        if not own.link then
            fg = util.hex(own.fg) or ""
            bg = util.hex(own.bg) or ""
        end
    end
    return padr(fg, FIELD_W) .. padr(bg, FIELD_W)
end

--- Public: self-heal the buffer structure. If an edit ever corrupts it — a row
--- joined into the header (line count shrank) or the header line got text — the
--- fixed-width layout is unrecoverable from the buffer, so rebuild every line
--- from the live highlight state and re-render. Returns true if it repaired
--- something (callers should then skip their normal edit handling). Cheap no-op
--- when the structure is intact.
function M.resync(buf)
    local s = sessions[buf]
    if not s or not s.has_data or not s.rows then
        return false
    end
    local total = vim.api.nvim_buf_line_count(buf)
    local header = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    if total == s.last and header == "" then
        return false -- structure intact
    end
    local lines = { "" } -- header (chrome only)
    for lnum = s.first, s.last do
        lines[lnum] = row_content(s.rows[lnum] or {})
    end
    s.adjusting = true
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, lines)
    s.adjusting = false
    M.rerender(buf)
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) == buf then
        pcall(vim.api.nvim_win_set_cursor, win, { s.first, FG_S })
    end
    return true
end

-- Leader-line geometry (all in screen cells relative to the cursor).
local GAP_ROWS = 1 -- rows of vertical connector between the cursor and the window top
local SIDE_OFF = 3 -- preferred gap: window corner this many cols right of the cursor
local ROUNDED = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" } -- tl,top,tr,r,br,bottom,bl,l
local CONNECTOR = { v = "│", h = "─", corner = "╰" }
-- Junction glyphs (all drawn as a 1x1 overlay over the border cell).
local JOIN_SIDE = "┤" -- into the left edge, below the top-left corner
local JOIN_TOP = "┴" -- straight down into the middle of the top border
local JOIN_TOP_L = "├" -- straight down onto the top-left corner
local JOIN_TOP_R = "┤" -- straight down onto the top-right corner

--- Clamp the cursor to editable cells. In normal mode it may sit on any cell;
--- while a field is being edited it is confined to that one field, so it can rest
--- right behind the last character but never cross into the gap/next column.
local function confine(buf)
    local s = sessions[buf]
    if not s or not s.has_data or s.normalizing then
        return
    end
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) ~= buf then
        return
    end
    local total = vim.api.nvim_buf_line_count(buf)
    local pos = vim.api.nvim_win_get_cursor(win)

    if s.field and vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
        -- Insert mode: keep the cursor inside the field being edited. Clamp the
        -- line to what the buffer actually has, so a transient bad state can't
        -- throw "out of range" (and never move to a nonexistent line).
        local fstart = (s.field == 1) and FG_S or BG_S
        local lnum = math.max(1, math.min(s.active_lnum or pos[1], total))
        local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
        local col = math.max(fstart, math.min(pos[2], fstart + FIELD_W - 1, #line))
        if pos[1] ~= lnum or pos[2] ~= col then
            pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
        end
        return
    end

    local lnum = math.max(s.first, math.min(pos[1], s.last, total))
    local ranges = s.cells[lnum]
    if not ranges then
        return
    end
    local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    local min_c = ranges[1][1]
    local max_c = math.min(ranges[#ranges][2] - 1, #line)
    local col = math.max(min_c, math.min(pos[2], max_c))
    if lnum ~= pos[1] or col ~= pos[2] then
        pcall(vim.api.nvim_win_set_cursor, win, { lnum, col })
    end
end

--- Jump to the next/previous editable cell (Tab / S-Tab).
local function jump_cell(buf, dir)
    local s = sessions[buf]
    if not s or not s.has_data then
        return
    end
    local win = vim.api.nvim_get_current_win()
    local pos = vim.api.nvim_win_get_cursor(win)
    local lnum, col = pos[1], pos[2]
    local ranges = s.cells[lnum] or {}
    local idx
    for i, rng in ipairs(ranges) do
        if col >= rng[1] and col < rng[2] then
            idx = i
            break
        end
    end
    idx = (idx or 1) + dir
    if ranges[idx] then
        vim.api.nvim_win_set_cursor(win, { lnum, ranges[idx][1] })
    elseif dir > 0 and lnum < s.last then
        vim.api.nvim_win_set_cursor(win, { lnum + 1, s.cells[lnum + 1][1][1] })
    elseif dir < 0 and lnum > s.first then
        local prev = s.cells[lnum - 1]
        vim.api.nvim_win_set_cursor(win, { lnum - 1, prev[#prev][1] })
    end
end

--- Decide where the float opens and how the leader line joins it. Positions are
--- absolute (relative="editor") so the window stays put even though we focus it.
--- The window is always placed to the right of the cursor, clamped to the screen's
--- right edge (never to the left of the cursor):
---   * lands right of the cursor -> connector runs into the LEFT edge, one cell
---     below the top-left corner (a `┤` junction).
---   * clamping pulls it onto/over the cursor -> connector drops straight down
---     into the TOP border at the cursor's column (`┴`, or `├`/`┤` at a corner).
--- Junctions are always drawn as a 1x1 overlay, so the border stays plain.
local function compute_placement(src, width, height)
    local fallback = {
        case = "none",
        cfg = {
            relative = "cursor",
            row = GAP_ROWS + 1,
            col = SIDE_OFF,
            border = vim.deepcopy(ROUNDED),
            title_pos = "left",
        },
    }
    if not src then
        return fallback
    end
    local sp = vim.fn.screenpos(src.win, src.row + 1, src.col + 1)
    if not sp or sp.row == 0 then
        return fallback
    end
    local cr, cc = sp.row - 1, sp.col - 1 -- 0-indexed cursor screen cell
    local corner_row = cr + GAP_ROWS + 1 -- screen row of the window's top border

    local outer_w = width + 2 -- content + left/right border
    local max_left = math.max(0, vim.o.columns - outer_w) -- rightmost corner that still fits
    local corner_col = math.max(0, math.min(cc + SIDE_OFF, max_left))
    local outer_right = corner_col + outer_w - 1

    local cfg =
        { relative = "editor", row = corner_row, col = corner_col, border = vim.deepcopy(ROUNDED), title_pos = "left" }

    if corner_col > cc then
        -- Window sits to the right of the cursor: join the left edge below the corner.
        return {
            case = "left",
            cfg = cfg,
            elbow_dashes = corner_col - cc - 1,
            overlay = { row = corner_row + 1, col = corner_col, char = JOIN_SIDE },
        }
    end

    -- Clamped to the right edge and the cursor overlaps the window: drop straight
    -- into the top border at the cursor's column.
    local jc = math.min(math.max(cc, corner_col), outer_right)
    local char = JOIN_TOP
    if jc == corner_col then
        char = JOIN_TOP_L
    elseif jc == outer_right then
        char = JOIN_TOP_R
    end
    -- Keep the title clear of the junction by placing it on the farther side.
    cfg.title_pos = (jc - corner_col) <= (width / 2) and "right" or "left"
    return { case = "top", cfg = cfg, overlay = { row = corner_row, col = jc, char = char } }
end

--- Highlight the originating cursor position and draw the leader line down to
--- the float. The connector stops one cell short of the window; the overlay join
--- glyph completes the connection.
local function draw_source(src, placement)
    if not src then
        return
    end
    -- 1) The cursor cell itself.
    local line = vim.api.nvim_buf_get_lines(src.buf, src.row, src.row + 1, false)[1] or ""
    if src.col < #line then
        pcall(vim.api.nvim_buf_set_extmark, src.buf, ns_src, src.row, src.col, {
            end_col = src.col + 1,
            hl_group = "TweakerCursor",
            priority = 300,
        })
    else
        pcall(vim.api.nvim_buf_set_extmark, src.buf, ns_src, src.row, src.col, {
            virt_text = { { " ", "TweakerCursor" } },
            virt_text_pos = "overlay",
            priority = 300,
        })
    end

    -- 2) The leader line.
    if not src.dcol or not placement or placement.case == "none" then
        return
    end
    local dcol = math.max(0, src.dcol)
    local n_lines = vim.api.nvim_buf_line_count(src.buf)
    local corner_brow = src.row + GAP_ROWS + 1 -- buffer row aligned with the window's top border
    local function put(brow, text)
        if brow >= 0 and brow < n_lines then
            pcall(vim.api.nvim_buf_set_extmark, src.buf, ns_src, brow, 0, {
                virt_text = { { text, "TweakerConnector" } },
                virt_text_win_col = dcol,
                priority = 300,
            })
        end
    end

    if placement.case == "left" then
        -- Vertical drop to the corner row, then an elbow into the left edge.
        for r = src.row + 1, corner_brow do
            put(r, CONNECTOR.v)
        end
        put(corner_brow + 1, CONNECTOR.corner .. string.rep(CONNECTOR.h, math.max(0, placement.elbow_dashes or 0)))
    else -- case "top": straight down into the top border (overlay draws the join)
        for r = src.row + 1, corner_brow - 1 do
            put(r, CONNECTOR.v)
        end
    end
end

--- Open a floating window rendering the given items as a table.
---@param title string
---@param items tweaker.Item[]
---@param opts { source?: table, editable?: boolean }|nil
---@return integer? win, integer? buf
function M.open(title, items, opts)
    opts = opts or {}
    ensure_hl()
    local editable = opts.editable or false

    local buf = vim.api.nvim_create_buf(false, true)
    local layout
    if #items == 0 then
        layout = {
            lines = { " No highlights under cursor." },
            cells = {},
            rows = {},
            widths = {},
            has_data = false,
            width = 28,
        }
    else
        layout = build(items)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, layout.lines)
    vim.bo[buf].modifiable = editable
    vim.bo[buf].filetype = "tweaker"
    vim.bo[buf].bufhidden = "wipe"
    -- No autocompletion in the tweaker window (blink.cmp / nvim-cmp both honor
    -- this buffer-local flag).
    vim.b[buf].completion = false

    sessions[buf] = {
        cells = layout.cells,
        rows = layout.rows,
        widths = layout.widths,
        first = layout.first or 1,
        last = layout.last or 1,
        has_data = layout.has_data,
        editable = editable,
        src = opts.source,
    }

    if layout.has_data then
        render_header(buf, layout.widths)
        for lnum, desc in pairs(layout.rows) do
            render_line(buf, lnum, desc, layout.widths)
        end
    end

    local height = math.min(#layout.lines, vim.o.lines - 4)
    local width = math.min(layout.width + 1, vim.o.columns - 4)
    local placement = compute_placement(opts.source, width, height)
    local cfg = vim.tbl_extend("force", placement.cfg, {
        width = width,
        height = height,
        style = "minimal",
        title = " " .. title .. " ",
        noautocmd = true,
    })
    -- Only hint at the link toggle when there's actually a linked row to toggle.
    if layout.has_link then
        cfg.footer = " <C-t> edit linked group "
        cfg.footer_pos = "right"
    end

    draw_source(opts.source, placement)

    -- Keep the source window looking "active" while the float is focused: remap
    -- its NormalNC (and WinBarNC) to the active groups so colorschemes that dim
    -- inactive windows don't repaint it. Restored on close.
    local prev_wh
    if opts.source and vim.api.nvim_win_is_valid(opts.source.win) then
        prev_wh = vim.wo[opts.source.win].winhighlight
        local undim = "NormalNC:Normal,WinBarNC:WinBar"
        vim.wo[opts.source.win].winhighlight = (prev_wh ~= "" and (prev_wh .. ",") or "") .. undim
    end

    local win = vim.api.nvim_open_win(buf, true, cfg)
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = false
    -- Route the float's colors through the explicit Tweaker groups (not Normal).
    vim.wo[win].winhighlight =
        "NormalFloat:TweakerNormal,FloatBorder:TweakerBorder,FloatTitle:TweakerBorder,FloatFooter:TweakerBorder"

    -- Overlay the junction glyph onto the window border where the connector meets
    -- it (edge cells can't be set via the border option, so we cover the cell).
    local overlay_win
    if placement.overlay then
        local obuf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(obuf, 0, -1, false, { placement.overlay.char })
        vim.bo[obuf].bufhidden = "wipe"
        overlay_win = vim.api.nvim_open_win(obuf, false, {
            relative = "editor",
            row = placement.overlay.row,
            col = placement.overlay.col,
            width = 1,
            height = 1,
            style = "minimal",
            focusable = false,
            zindex = 60,
            noautocmd = true,
        })
        vim.wo[overlay_win].winhighlight = "NormalFloat:TweakerBorder"
    end

    if layout.has_data then
        vim.api.nvim_win_set_cursor(win, { layout.first, 0 })
    end

    local function close()
        if opts.source then
            pcall(vim.api.nvim_buf_clear_namespace, opts.source.buf, ns_src, 0, -1)
            if vim.api.nvim_win_is_valid(opts.source.win) then
                vim.wo[opts.source.win].winhighlight = prev_wh or ""
            end
        end
        sessions[buf] = nil
        if overlay_win and vim.api.nvim_win_is_valid(overlay_win) then
            vim.api.nvim_win_close(overlay_win, true)
        end
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    -- In an editable window, <Esc> must stay "leave insert mode", not close.
    local close_keys = editable and { "q", "<C-c>" } or { "q", "<Esc>", "<C-c>" }
    for _, key in ipairs(close_keys) do
        vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
    end
    vim.keymap.set("n", "<Tab>", function()
        jump_cell(buf, 1)
    end, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<S-Tab>", function()
        jump_cell(buf, -1)
    end, { buffer = buf, nowait = true, silent = true })

    -- The table is fixed and fits the window: block scrolling entirely.
    for _, k in ipairs({ "<C-e>", "<C-y>", "<C-d>", "<C-u>", "<C-f>", "<C-b>", "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
        vim.keymap.set({ "n", "i" }, k, "<Nop>", { buffer = buf, nowait = true, silent = true })
    end

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = buf,
        callback = function()
            confine(buf)
        end,
    })
    -- Belt-and-suspenders: snap the view back if anything scrolls it.
    vim.api.nvim_create_autocmd("WinScrolled", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win then
                local v = vim.fn.winsaveview()
                if v.topline ~= 1 or v.leftcol ~= 0 then
                    v.topline, v.leftcol = 1, 0
                    pcall(vim.fn.winrestview, v)
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })

    if editable then
        require("tweaker.editor").attach(buf)
    end

    return win, buf
end

return M
