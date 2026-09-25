--- Bottom drawer: a real horizontal split holding the picker chrome.
---
--- The buffer is a `nofile` scratch buffer drawn as a fixed-size viewport, not
--- a scrolling list: it always holds exactly as many lines as the window is
--- tall, and only the visible slice of matches is built. The window itself
--- never scrolls (the cursor stays on line 1), so the selection is painted
--- rather than followed.
---
---   row 1         prompt: source glyph, query, caret, count
---   rows 2..h     matches, one per line
---
--- The window bar is the picker's only chrome: source tabs, the keys that
--- open each menu, and the menus themselves when one is open. It costs no
--- list rows of its own.

local hl = require("loupe.util.hl")
local buf = require("loupe.util.buf")
local win = require("loupe.util.win")
local display = require("loupe.display")
local parse = require("loupe.backend.parse")

local M = {}

local ns = vim.api.nvim_create_namespace("loupe_matches")

-- One space of breathing room either side of every row.
local PAD = 1
-- Gap between the left text and the right-hand metadata column.
local GAP = 2

--- Resolved attributes of `group`, links followed.
local function resolve(group)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
	return ok and hl or {}
end
--- `rgb` moved `amount` towards white when it is dark, towards black when it
--- is light: the same nudge reads as "lifted" in either kind of theme.
local function shade(rgb, amount)
	local r, g, b = math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
	local target = (0.299 * r + 0.587 * g + 0.114 * b) < 128 and 255 or 0
	local function mix(c)
		return math.floor(c + (target - c) * amount + 0.5)
	end
	return mix(r) * 65536 + mix(g) * 256 + mix(b)
end

--- `fg` moved `amount` of the way towards `bg`: the same colour, further
--- back. Unlike picking a grey, this keeps whatever tint the theme's chrome
--- text has, so a muted label still belongs to the bar it sits on.
local function mute(fg, bg, amount)
	local function channel(shift)
		local from, to = math.floor(fg / shift) % 256, math.floor(bg / shift) % 256
		return math.floor(from + (to - from) * amount + 0.5) * shift
	end
	return channel(65536) + channel(256) + channel(1)
end

--- The bar's own colours: the ground it is drawn on, the text it lends to
--- anything that sets no colour of its own, that text muted for the parts
--- meant to recede, and the ground of the list the bar sits against.
---
--- A mute is measured against the bar, because that is what the muted text
--- is drawn on. A lift is measured against `list`, because what a lit strip
--- has to separate itself from is the row beneath it. Returns nil for a
--- theme that leaves any of them unset, which the callers read as "fall back
--- to a link and let the theme decide".
local function chrome()
	local bar = resolve("LoupeBorder")
	local list = resolve("Normal").bg
	if not (bar.fg and bar.bg and list) then
		return nil
	end
	return { fg = bar.fg, bg = bar.bg, dim = mute(bar.fg, bar.bg, 0.3), list = list }
end

--- Highlights for the strip while a menu is open.
---
--- The strip lights up. Its ground lifts away from the list it borders,
--- far enough to read as its own surface: lift it against the buffer above
--- the drawer instead and it lands on the list's own colour, where the bar
--- stops being a bar at all. Its text comes up to full chrome strength,
--- because a menu makes every entry on the strip a live choice and nothing
--- on it should be receding any more. The key to press is marked by weight
--- and by sitting at `Normal`'s own brightness, rather than by a colour of
--- its own, so the strip gains no hue the closed one did not have.
---
--- Themes without a background of their own fall back to CursorLine, which
--- is the same idea already solved by the theme.
local function select_highlights(bar)
	if not bar then
		vim.api.nvim_set_hl(0, "LoupeTabSelect", { link = "CursorLine", default = true })
		vim.api.nvim_set_hl(0, "LoupeTabSelectActive", { link = "CursorLine", default = true })
		vim.api.nvim_set_hl(0, "LoupeTabSelectKey", { bold = true, underline = true, default = true })
		return
	end
	local bg = shade(bar.list, 0.06)
	vim.api.nvim_set_hl(0, "LoupeTabSelect", { fg = bar.fg, bg = bg, default = true })
	vim.api.nvim_set_hl(0, "LoupeTabSelectActive", {
		fg = resolve("Title").fg,
		bg = bg,
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "LoupeTabSelectKey", {
		fg = resolve("Normal").fg or bar.fg,
		bg = bg,
		bold = true,
		underline = true,
		default = true,
	})
end

local function define_highlights()
	vim.api.nvim_set_hl(0, "LoupeMatch", { link = "Search", default = true })
	vim.api.nvim_set_hl(0, "LoupePrompt", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "LoupePromptCaret", { link = "LoupePrompt", default = true })
	vim.api.nvim_set_hl(0, "LoupeCursor", { blend = 100, nocombine = true })
	-- StatusLine, not FloatBorder: the drawer is a real split, and a theme
	-- tunes StatusLine for exactly this — a strip of chrome across one. A
	-- border's foreground is picked to be nearly invisible because it only
	-- ever draws box corners, and every chunk of the bar that sets no colour
	-- of its own inherits this group's. The parked bar borrows StatusLineNC,
	-- the theme's own "inactive chrome".
	vim.api.nvim_set_hl(0, "LoupeBorder", { link = "StatusLine", default = true })
	vim.api.nvim_set_hl(0, "LoupeBorderNC", { link = "StatusLineNC", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitMod", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitAdd", { link = "DiagnosticOk", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitDel", { link = "DiagnosticError", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitNew", { link = "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "LoupeGitRename", { link = "DiagnosticInfo", default = true })
	-- chrome
	vim.api.nvim_set_hl(0, "LoupeSelection", { link = "Visual", default = true })
	vim.api.nvim_set_hl(0, "LoupeDir", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "LoupeMeta", { link = "LineNr", default = true })
	vim.api.nvim_set_hl(0, "LoupeMetaFlag", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "LoupeGhost", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "LoupeCount", { link = "LineNr", default = true })
	local bar = chrome()
	-- a parked drawer recedes: its base text is the theme's own, muted towards
	-- its background. Explicitly highlighted rows (selection, matches) keep
	-- their colour, so a parked list still reads as a list, just a quiet one.
	local normal = resolve("Normal")
	if normal.fg and normal.bg then
		vim.api.nvim_set_hl(0, "LoupeDrawerNC", {
			fg = mute(normal.fg, normal.bg, 0.4),
			bg = normal.bg,
			default = true,
		})
	else
		vim.api.nvim_set_hl(0, "LoupeDrawerNC", { link = "Comment", default = true })
	end
	-- an inactive tab recedes by being muted chrome text, not by borrowing
	-- Comment: Comment is built to sit at the edge of legibility so the eye
	-- skips it, which is right for a hint and wrong for a label to read
	local tab = bar and { fg = bar.dim, default = true } or { link = "Comment", default = true }
	vim.api.nvim_set_hl(0, "LoupeTab", tab)
	vim.api.nvim_set_hl(0, "LoupeTabActive", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "LoupeEmpty", { link = "Comment", default = true })
	select_highlights(bar)
end

--- Open the split at `height` lines and return { win, buf }.
function M.open(height)
	define_highlights()

	local bufnr = buf.scratch({ bufhidden = "hide" })

	vim.cmd(("botright %dsplit"):format(height))
	local winid = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(winid, bufnr)

	win.set(winid, {
		winfixheight = true,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		wrap = false,
		-- the selected row is painted, so Neovim's own cursor line would only
		-- highlight the prompt
		cursorline = false,
		foldenable = false,
		spell = false,
		list = false,
		scrolloff = 0,
		winhighlight = "Normal:Normal,NormalNC:LoupeDrawerNC,WinBar:LoupeBorder,WinBarNC:LoupeBorderNC",
		-- claimed up front so the row it costs is in the geometry from the
		-- first render, before there are tabs to put in it
		winbar = " ",
	})

	return { win = winid, buf = bufnr }
end

--- How many match rows fit: everything but the prompt.
---
--- A window bar takes a row from the text area while `nvim_win_get_height()`
--- keeps reporting the full height, so it has to be subtracted by hand — miss
--- it and the last row is drawn below the fold, where nothing shows it.
function M.capacity(winid)
	if not (winid and vim.api.nvim_win_is_valid(winid)) then
		return 1
	end
	local bar = (vim.wo[winid].winbar or "") ~= "" and 1 or 0
	return math.max(1, vim.api.nvim_win_get_height(winid) - bar - 1)
end

-- ---------------------------------------------------------------------------
-- text helpers

--- `text` cut to `width` display cells, with an ellipsis when it did not fit.
local function fit(text, width)
	if width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	local out, w, i = {}, 0, 0
	while true do
		local ch = vim.fn.strcharpart(text, i, 1)
		if ch == "" then
			break
		end
		local cw = vim.fn.strdisplaywidth(ch)
		if w + cw > width - 1 then
			break
		end
		out[#out + 1] = ch
		w = w + cw
		i = i + 1
	end
	return table.concat(out) .. "…"
end

local function spaces(n)
	return string.rep(" ", math.max(0, n))
end

-- ---------------------------------------------------------------------------
-- chrome

--- The count shown at the right of the prompt: `shown/total` for list sources,
--- `found` for live ones (`+` when the search stopped at the cap, `…` while it
--- is still running).
function M.count_text(session)
	local shown, total = #session.matches, #(session.candidates or {})
	if session.source and session.source.search then
		return tostring(total) .. (session.truncated and "+" or "") .. (session.searching and " …" or "")
	end
	if not session.loaded then
		return "…"
	end
	if total > shown then
		return shown .. "/" .. total
	end
	return tostring(shown)
end

--- Root shown in the window bar when browsing away from the project root.
local function root_text(session)
	if not (session.root and session.project_root) or session.root == session.project_root then
		return ""
	end
	if session.root:sub(1, #session.project_root + 1) == session.project_root .. "/" then
		return parse.relpath(session.project_root, session.root) .. "/"
	end
	return vim.fn.fnamemodify(session.root, ":~")
end

--- Render `blocks` as a window-bar string, sliced to `width` around the one
--- named `focus` so a narrow window keeps showing where you are rather than
--- the first few entries. `right` is pinned to the right edge.
local function strip(blocks, width, focus, right, fill)
	local col = 0
	for _, b in ipairs(blocks) do
		b.from, b.to = col, col + #b.text
		col = col + #b.text
	end

	right = right or ""
	local avail = math.max(1, width - (right == "" and 0 or #right + 2))
	local offset = 0
	if col > avail and focus then
		local from, to
		for _, b in ipairs(blocks) do
			if b.name == focus then
				from = math.min(from or b.from, b.from)
				to = math.max(to or b.to, b.to)
			end
		end
		if from then
			offset = math.min(math.max(math.floor((from + to) / 2) - math.floor(avail / 2), 0), col - avail)
		end
	end

	local parts = {}
	for _, b in ipairs(blocks) do
		local from, to = math.max(b.from, offset), math.min(b.to, offset + avail)
		if to > from then
			local text = b.text:sub(from - b.from + 1, to - b.from)
			parts[#parts + 1] = ("%%#%s#%s"):format(b.group, text:gsub("%%", "%%%%"))
		end
	end
	-- the fill before `%=` carries the last highlight, so a lit strip runs the
	-- whole width rather than stopping at the last entry
	parts[#parts + 1] = "%#" .. fill .. "#%="
	if right ~= "" then
		parts[#parts + 1] = right:gsub("%%", "%%%%") .. " "
	end
	return table.concat(parts)
end

--- Whether `key` is the letter `label` starts with. Only the first letter is
--- ever marked: underlining the `c` of "do[c]_symbols" would name the key
--- without pointing at anything a reader can follow. A shifted key is never
--- marked either — the `d` of "dirs" is not `D`.
local function starts_with_key(label, key)
	return key ~= nil and #key == 1 and not key:match("%u") and label:sub(1, 1):lower() == key:lower()
end

--- One entry, split so its key can be marked without moving the label: the
--- text stays put and only that letter changes weight. A key that is not the
--- first letter is appended, and a named key (`enter`, `ctrl+o`) leads.
local function entry_blocks(label, key, group, name, marked)
	local function block(text, g)
		return { text = text, group = g or group, name = name }
	end
	if not marked or not key or key == "" then
		return { block(" " .. label .. " ") }
	end
	if starts_with_key(label, key) then
		return {
			block(" "),
			block(label:sub(1, 1), "LoupeTabSelectKey"),
			block(label:sub(2) .. " "),
		}
	end
	if #key > 1 then
		return { block(" "), block(key, "LoupeTabSelectKey"), block(" " .. label .. " ") }
	end
	return { block(" " .. label .. " "), block(key, "LoupeTabSelectKey"), block(" ") }
end

--- Source tabs, the active source highlighted. `opts` is
--- `{ right, hint, select, keys }`: `hint` is the key that opens the source
--- menu, shown at the left so the row says how to change it. While `select`
--- is set the strip keeps its text and takes a lifted background, and each
--- tab's key is marked in place.
function M.tabs(sources, active, width, opts)
	opts = opts or {}
	local select = opts.select == true
	local normal = select and "LoupeTabSelect" or "LoupeTab"
	local current = select and "LoupeTabSelectActive" or "LoupeTabActive"

	local blocks = {}
	if opts.hint and opts.hint ~= "" then
		blocks[#blocks + 1] = { text = " " .. opts.hint .. " ", group = normal }
	end
	for _, src in ipairs(sources) do
		local label = src.tab or src.label or src.name
		local key = opts.keys and opts.keys[src.name]
		local group = src.name == active and current or normal
		vim.list_extend(blocks, entry_blocks(label, key, group, src.name, select))
	end
	return strip(blocks, width, active, opts.right, normal)
end

--- Key notation as a person would say it: `<C-O>` -> `ctrl+o`.
function M.friendly_key(lhs)
	local named = {
		["<CR>"] = "enter",
		["<Tab>"] = "tab",
		["<Esc>"] = "esc",
		["<BS>"] = "bs",
		["<Space>"] = "space",
	}
	local key = named[lhs]
	if key then
		return key
	end
	local ctrl = lhs:match("^<[Cc]%-(.)>$")
	if ctrl then
		return "ctrl+" .. ctrl:lower()
	end
	-- a bare character is the key itself: `D` is not `d`
	if not lhs:match("^<.*>$") then
		return lhs
	end
	return (lhs:gsub("^<(.*)>$", "%1"):lower())
end

--- First key bound to `action` in `map`, in a stable order. `<Esc>` wins when
--- it is one of them: it is the one people reach for.
local function key_for(map, action)
	local found
	for lhs, name in pairs(map) do
		if name == action then
			if lhs:lower() == "<esc>" then
				return lhs
			end
			if not found or lhs < found then
				found = lhs
			end
		end
	end
	return found
end

--- Source name -> the key that switches to it.
local function source_keys(map)
	local out = {}
	for lhs, name in pairs(map or {}) do
		if not out[name] or lhs < out[name] then
			out[name] = lhs
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- lines

--- Prompt line: glyph, query, caret, and the count at the right.
--- Returns the text plus the spans to highlight.
local function prompt_line(session, cfg)
	local caret = cfg.prompt_caret or "▏"
	local spans = {}

	local icon = cfg.icons and session.source and session.source.icon
	local prefix = (icon and icon ~= "") and (" " .. icon .. " ") or (" " .. cfg.prompt)
	local value = session.query or ""
	local cursor = session.caret or vim.fn.strchars(value)

	local text = prefix .. vim.fn.strcharpart(value, 0, cursor)
	spans[#spans + 1] = { 0, #prefix, "LoupePrompt" }
	spans[#spans + 1] = { #text, #text + #caret, "LoupePromptCaret" }
	text = text .. caret .. vim.fn.strcharpart(value, cursor)

	if value == "" and session.source then
		local ghost = session.source.label or ""
		if ghost ~= "" then
			ghost = " " .. ghost
			spans[#spans + 1] = { #text, #text + #ghost, "LoupeGhost" }
			text = text .. ghost
		end
	end
	return text, spans
end

--- The right-hand column never takes more than this share of the row: a long
--- path should cost the text it sits beside a little room, not most of it.
local META_SHARE = 0.4

--- One match row: padded, the left text in chunks (a dimmed directory, or a
--- matched line) and the metadata column right-aligned. Returns the line plus
--- its highlight spans.
local function match_line(session, cfg, item, width, selected)
	local cand = item.cand
	local parts = display.row(cand, { git = cfg.git and session.git or nil, icons = cfg.icons })

	local inner = math.max(1, width - PAD * 2)
	local meta_text = {}
	for _, chunk in ipairs(parts.meta) do
		meta_text[#meta_text + 1] = chunk[1]
	end
	local right = fit(table.concat(meta_text, "  "), math.floor(inner * META_SHARE))

	local prefix = parts.icon ~= "" and (parts.icon .. " ") or ""
	local right_room = right ~= "" and (vim.fn.strdisplaywidth(right) + GAP) or 0
	local room = math.max(1, inner - vim.fn.strdisplaywidth(prefix) - right_room)

	-- chunks are laid out left to right until the room runs out, so their
	-- highlights can be placed as they are built
	local left, chunks = "", {}
	for _, chunk in ipairs(parts.left) do
		local text = fit(chunk[1], math.max(0, room - vim.fn.strdisplaywidth(left)))
		if text ~= "" then
			chunks[#chunks + 1] = { #left, #left + #text, chunk[2] }
			left = left .. text
		end
	end

	local body = prefix .. left
	local gap = math.max(GAP, inner - vim.fn.strdisplaywidth(body) - vim.fn.strdisplaywidth(right))
	local line = spaces(PAD) .. body .. spaces(right ~= "" and gap or (inner - vim.fn.strdisplaywidth(body)))
	local right_start = #line
	line = line .. right
	line = line .. spaces(width - vim.fn.strdisplaywidth(line))

	local spans = {}
	if selected then
		spans[#spans + 1] = { 0, #line, "LoupeSelection", 90 }
	end
	local at = PAD
	if parts.icon ~= "" then
		spans[#spans + 1] = { at, at + #parts.icon, parts.icon_hl }
		at = at + #parts.icon + 1
	end
	-- `at` now sits where the left text starts, so offsets into it — the
	-- matcher's and the source's own — land without translation
	for _, chunk in ipairs(chunks) do
		if chunk[3] then
			spans[#spans + 1] = { at + chunk[1], at + chunk[2], chunk[3] }
		end
	end
	local shown = #left
	for _, range in ipairs(parts.marks or {}) do
		if range[1] < shown then
			spans[#spans + 1] = { at + range[1], at + math.min(range[2], shown), range[3], 200 }
		end
	end
	for _, col in ipairs(item.positions) do
		if col < math.min(shown, parts.match_len) then
			spans[#spans + 1] = { at + col, at + col + 1, "LoupeMatch", 200 }
		end
	end
	if right ~= "" then
		local col = right_start
		for i, chunk in ipairs(parts.meta) do
			if i > 1 then
				col = col + 2
			end
			local to = math.min(col + #chunk[1], right_start + #right)
			if col < to then
				spans[#spans + 1] = { col, to, chunk[2] or "LoupeMeta" }
			end
			col = col + #chunk[1]
		end
	end
	return line, spans
end

--- The window bar: the source tabs, lit while the source menu is open. It is
--- the picker's only chrome, so the key that opens that menu lives here too,
--- at the left, with the root at the right when there is one to show.
local function winbar_text(session, cfg, width)
	local maps = cfg.mappings or {}
	local function browse_key(action)
		return M.friendly_key(key_for(maps.browse or {}, action) or "")
	end
	-- `<Esc>` (park) is the key people reach for to cancel the menu; it is
	-- handled by the menu itself, which closes without parking. If park is
	-- unbound, fall back to the close key so the hint still names something.
	local cancel_key = browse_key("park")
	if cancel_key == "" then
		cancel_key = browse_key("close")
	end
	local cancel = cancel_key .. " cancel"

	local select = session.menu == "sources"
	local right = root_text(session)
	return M.tabs(session.sources or {}, session.source and session.source.name, width, {
		right = select and cancel or right,
		-- kept while selecting: dropping it would slide every tab left, and
		-- the one thing this state must not do is move
		hint = browse_key("sources"),
		select = select,
		keys = source_keys(maps.sources),
	})
end

--- First visible match, kept so the selection stays on screen.
local function viewport(session, rows)
	local top = math.max(1, session.top or 1)
	local n = #session.matches
	if session.index < top then
		top = session.index
	elseif session.index > top + rows - 1 then
		top = session.index - rows + 1
	end
	top = math.max(1, math.min(top, math.max(1, n - rows + 1)))
	session.top = top
	return top
end

-- ---------------------------------------------------------------------------

--- Redraw the whole drawer.
function M.render(session, cfg)
	local bufnr = session.list_buf
	local winid = session.drawer_win
	if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
		return
	end
	if not (winid and vim.api.nvim_win_is_valid(winid)) then
		return
	end

	local width = vim.api.nvim_win_get_width(winid)
	-- set before measuring: the bar takes one of the window's rows
	vim.wo[winid].winbar = winbar_text(session, cfg, width)
	local rows = M.capacity(winid)
	local lines, all = {}, {}

	local head, head_spans = prompt_line(session, cfg)
	lines[1] = head
	all[1] = head_spans

	if #session.matches == 0 then
		lines[2] = spaces(PAD) .. (session.loaded and "(no matches)" or "(loading…)")
		all[2] = { { PAD, #lines[2], "LoupeEmpty" } }
		for i = 3, rows do
			lines[i] = ""
		end
	else
		local top = viewport(session, rows)
		for i = 0, rows - 1 do
			local item = session.matches[top + i]
			if not item then
				lines[#lines + 1] = ""
			else
				local line, spans = match_line(session, cfg, item, width, top + i == session.index)
				lines[#lines + 1] = line
				all[#lines] = spans
			end
		end
	end
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	for row, spans in pairs(all) do
		local len = #(lines[row] or "")
		for _, s in ipairs(spans) do
			local from, to = s[1], math.min(s[2], len)
			if s[3] and from < to then
				hl.range(bufnr, ns, row - 1, from, to, s[3], s[4] and { priority = s[4] } or nil)
			end
		end
	end
	hl.virt_text(bufnr, ns, 0, M.count_text(session) .. " ", "LoupeCount", { virt_text_pos = "right_align" })

	-- the viewport is drawn, never scrolled to
	pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })

	vim.cmd("redraw")
end

--- Close the split and wipe the list buffer.
function M.close(session)
	if session.drawer_win and vim.api.nvim_win_is_valid(session.drawer_win) then
		vim.api.nvim_win_close(session.drawer_win, true)
	end
	if session.list_buf and vim.api.nvim_buf_is_valid(session.list_buf) then
		pcall(vim.api.nvim_buf_delete, session.list_buf, { force = true })
	end
end

return M
