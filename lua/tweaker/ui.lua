local util = require("tweaker.util")

local M = {}

local ns = vim.api.nvim_create_namespace("tweaker.render") -- float decorations
local ns_src = vim.api.nvim_create_namespace("tweaker.source") -- source-buffer cursor indicator

-- Fixed width of a color cell: wide enough to hold "#rrggbb" so filling an empty
-- cell never resizes the float.
local COLOR_W = 7
local GAP = 2

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

local function padr(s, w)
    return s .. string.rep(" ", math.max(0, w - #s))
end

--- Build the buffer lines, extmarks, and cell ranges for the given items.
---@param items tweaker.Item[]
---@return table layout
local function build(items)
    local rows = {}
    local pw, sw, gw = #"PRIORITY", #"SOURCE", #"GROUP"
    for _, it in ipairs(items) do
        local r = {
            pri = tostring(it.priority),
            source = it.source,
            group = it.group,
            fg = util.hex(it.hl.fg), -- nil when unset
            bg = util.hex(it.hl.bg),
        }
        pw = math.max(pw, #r.pri)
        sw = math.max(sw, #r.source)
        gw = math.max(gw, #r.group)
        rows[#rows + 1] = r
    end

    -- Byte offsets of each real (editable) cell within a data line. Editable
    -- cells (fg, bg, priority) are contiguous real text, rendered after the
    -- virtual source/group block.
    local fg_start = 0
    local bg_start = fg_start + COLOR_W
    local pri_start = bg_start + COLOR_W
    local total_w = sw + GAP + gw + GAP + COLOR_W + GAP + COLOR_W + GAP + pw

    local lines = {}
    local marks = {} -- { row, col, opts }
    local cells = {} -- lnum(1-based) -> { {s,e}, ... }

    -- Header line (all virtual; cursor never lands here).
    lines[1] = ""
    marks[#marks + 1] = {
        row = 0,
        col = 0,
        opts = {
            virt_text = {
                { padr("SOURCE", sw), "TweakerHeader" },
                { string.rep(" ", GAP) },
                { padr("GROUP", gw), "TweakerHeader" },
                { string.rep(" ", GAP) },
                { padr("FG", COLOR_W), "TweakerHeader" },
                { string.rep(" ", GAP) },
                { padr("BG", COLOR_W), "TweakerHeader" },
                { string.rep(" ", GAP) },
                { padr("PRIORITY", pw), "TweakerHeader" },
            },
            virt_text_pos = "inline",
        },
    }

    for i, r in ipairs(rows) do
        local row0 = i -- 0-based buffer line (header is 0)
        -- Real text: fg | bg | priority. FG/BG are padded to a fixed width so
        -- columns align and filling an empty cell never resizes the float. The
        -- priority is last, so it gets no trailing pad — the row ends at its
        -- final value and the cursor can't move past it.
        local real = padr(r.fg or "", COLOR_W) .. padr(r.bg or "", COLOR_W) .. r.pri
        lines[#lines + 1] = real
        cells[i + 1] = {
            { fg_start, bg_start },
            { bg_start, pri_start },
            { pri_start, pri_start + #r.pri },
        }

        -- Virtual, non-editable SOURCE + GROUP block, rendered before the cells.
        marks[#marks + 1] = {
            row = row0,
            col = fg_start,
            opts = {
                virt_text = {
                    { padr(r.source, sw), "TweakerSource" },
                    { string.rep(" ", GAP) },
                    { padr(r.group, gw), r.group }, -- rendered in its own colors
                    { string.rep(" ", GAP) },
                },
                virt_text_pos = "inline",
                right_gravity = false,
            },
        }

        -- FG cell: color the value, or show a virtual "-" placeholder.
        if r.fg then
            marks[#marks + 1] =
                { row = row0, col = fg_start, opts = { end_col = fg_start + #r.fg, hl_group = swatch_hl(r.fg) } }
        else
            marks[#marks + 1] = {
                row = row0,
                col = fg_start,
                opts = { virt_text = { { "-", "TweakerEmpty" } }, virt_text_pos = "overlay" },
            }
        end

        -- Gap between FG and BG (virtual, so the cursor skips it).
        marks[#marks + 1] = {
            row = row0,
            col = bg_start,
            opts = { virt_text = { { string.rep(" ", GAP) } }, virt_text_pos = "inline", right_gravity = false },
        }

        -- BG cell: color the value, or show a virtual "-" placeholder.
        if r.bg then
            marks[#marks + 1] =
                { row = row0, col = bg_start, opts = { end_col = bg_start + #r.bg, hl_group = swatch_hl(r.bg) } }
        else
            marks[#marks + 1] = {
                row = row0,
                col = bg_start,
                opts = { virt_text = { { "-", "TweakerEmpty" } }, virt_text_pos = "overlay" },
            }
        end

        -- Gap between BG and PRIORITY (virtual).
        marks[#marks + 1] = {
            row = row0,
            col = pri_start,
            opts = { virt_text = { { string.rep(" ", GAP) } }, virt_text_pos = "inline", right_gravity = false },
        }

        -- Priority text highlight.
        marks[#marks + 1] =
            { row = row0, col = pri_start, opts = { end_col = pri_start + #r.pri, hl_group = "TweakerPriority" } }
    end

    return {
        lines = lines,
        marks = marks,
        cells = cells,
        first = 2, -- first data line (1-based)
        last = #rows + 1,
        width = total_w,
        has_data = #rows > 0,
    }
end

--- Clamp the cursor to editable cells / data lines.
local function confine(buf)
    local s = sessions[buf]
    if not s or not s.has_data then
        return
    end
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) ~= buf then
        return
    end
    local pos = vim.api.nvim_win_get_cursor(win)
    local lnum = math.max(s.first, math.min(pos[1], s.last))
    local ranges = s.cells[lnum]
    if not ranges then
        return
    end
    local min_c = ranges[1][1]
    local max_c = ranges[#ranges][2] - 1
    local col = math.max(min_c, math.min(pos[2], max_c))
    if lnum ~= pos[1] or col ~= pos[2] then
        vim.api.nvim_win_set_cursor(win, { lnum, col })
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
---@param opts { source?: { win:integer, buf:integer, row:integer, col:integer } }|nil
---@return integer? win, integer? buf
function M.open(title, items, opts)
    opts = opts or {}
    ensure_hl()

    local buf = vim.api.nvim_create_buf(false, true)
    local layout

    if #items == 0 then
        layout = { lines = { " No highlights under cursor." }, marks = {}, cells = {}, has_data = false, width = 28 }
    else
        layout = build(items)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, layout.lines)
    for _, m in ipairs(layout.marks) do
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.row, m.col, m.opts)
    end

    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "tweaker"
    vim.bo[buf].bufhidden = "wipe"

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
    vim.wo[win].winhighlight = "NormalFloat:TweakerNormal,FloatBorder:TweakerBorder,FloatTitle:TweakerBorder"

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

    sessions[buf] = {
        cells = layout.cells,
        first = layout.first or 1,
        last = layout.last or 1,
        has_data = layout.has_data,
        src = opts.source,
    }

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

    for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
        vim.keymap.set("n", key, close, { buffer = buf, nowait = true, silent = true })
    end
    vim.keymap.set("n", "<Tab>", function()
        jump_cell(buf, 1)
    end, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<S-Tab>", function()
        jump_cell(buf, -1)
    end, { buffer = buf, nowait = true, silent = true })

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = buf,
        callback = function()
            confine(buf)
        end,
    })
    vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })

    return win, buf
end

return M
