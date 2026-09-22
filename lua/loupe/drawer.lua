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

local function define_highlights()
	vim.api.nvim_set_hl(0, "LoupeMatch", { link = "Search", default = true })
	vim.api.nvim_set_hl(0, "LoupeMark", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "LoupePrompt", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "LoupePromptCaret", { link = "LoupePrompt", default = true })
	vim.api.nvim_set_hl(0, "LoupeCursor", { blend = 100, nocombine = true })
	vim.api.nvim_set_hl(0, "LoupeBorder", { link = "FloatBorder", default = true })
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
	vim.api.nvim_set_hl(0, "LoupeTab", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "LoupeTabActive", { link = "Title", default = true })
	-- while the source menu is open the whole strip lights up
	vim.api.nvim_set_hl(0, "LoupeTabSelect", { link = "Visual", default = true })
	vim.api.nvim_set_hl(0, "LoupeTabSelectActive", { link = "PmenuSel", default = true })
	vim.api.nvim_set_hl(0, "LoupeEmpty", { link = "Comment", default = true })
end

--- Open the split at `height` lines and return { win, buf }.
function M.open(height)
	define_highlights()

	local bufnr = buf.scratch({ bufhidden = "wipe" })

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
		winhighlight = "Normal:Normal,WinBar:LoupeBorder,WinBarNC:LoupeBorder",
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

--- A tab's label with its key marked. The key is bracketed in place when it
--- is the label's first letter (`[B]uffers`), and prefixed when it is not
--- (`[t] Doc`) — which happens whenever a source's key was chosen for the
--- source name rather than the tab's.
function M.mnemonic(label, key)
	if not key or key == "" then
		return label
	end
	-- a shifted key always shows as itself: bracketing `Y` inside "yank rel"
	-- would read as `[y]`, which is a different key
	local shifted = key:match("^%u$") ~= nil
	if #key == 1 and not shifted and label:sub(1, 1):lower() == key:lower() then
		return "[" .. label:sub(1, 1) .. "]" .. label:sub(2)
	end
	return "[" .. key .. "] " .. label
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
		for _, b in ipairs(blocks) do
			if b.name == focus then
				offset = math.min(math.max(math.floor((b.from + b.to) / 2) - math.floor(avail / 2), 0), col - avail)
				break
			end
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

--- Source tabs, the active source highlighted. `opts` is
--- `{ right, hint, select, keys }`: `hint` is the key that opens the source
--- menu, shown at the left so the row says how to change it; while `select`
--- is set the whole strip is lit and every tab shows its key.
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
		if select then
			label = M.mnemonic(label, opts.keys and opts.keys[src.name])
		end
		blocks[#blocks + 1] = {
			text = " " .. label .. " ",
			group = src.name == active and current or normal,
			name = src.name,
		}
	end
	return strip(blocks, width, active, opts.right, normal)
end

--- The action menu as a lit strip, each entry marked with its key.
function M.menu(entries, width, right)
	local blocks = {}
	for _, entry in ipairs(entries) do
		blocks[#blocks + 1] = {
			text = " " .. M.mnemonic(entry[2], M.friendly_key(entry[1])) .. " ",
			group = "LoupeTabSelect",
		}
	end
	return strip(blocks, width, nil, right, "LoupeTabSelect")
end

--- Key notation as a person would say it: `<C-X>` -> `ctrl+x`.
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

-- The order actions are offered in: the ones that change a file first, then
-- the ways to copy its path, then the rest. Anything unlisted follows.
local ACTION_ORDER = {
	"rename",
	"delete",
	"create",
	"duplicate",
	"open_external",
	"quickfix",
	"yank",
	"yank_rel",
	"yank_name",
	"yank_dir",
}

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

--- The action menu's `{ key, label }` pairs, in the order they are offered.
function M.action_entries(session, cfg)
	local map = (cfg.mappings or {}).menu or {}
	local out, seen = {}, {}
	for _, action in ipairs(ACTION_ORDER) do
		local key = key_for(map, action)
		if key then
			seen[key] = true
			out[#out + 1] = { key, M.action_label(session, action) }
		end
	end
	local rest = {}
	for key in pairs(map) do
		if not seen[key] then
			rest[#rest + 1] = key
		end
	end
	table.sort(rest)
	for _, key in ipairs(rest) do
		out[#out + 1] = { key, M.action_label(session, map[key]) }
	end
	return out
end

-- Action names are identifiers; these are what they are called on screen.
local ACTION_NAMES = {
	open_external = "open ext",
	yank = "yank path",
	yank_rel = "yank rel",
	yank_name = "yank name",
	yank_dir = "yank dir",
}

--- Name an action as the active source performs it, so the hint never
--- promises something the key does not do (`delete` closes a buffer in the
--- buffers source).
function M.action_label(session, name)
	if name == "delete" and session.source and session.source.delete == "buffer" then
		return "close"
	end
	return ACTION_NAMES[name] or name
end

-- ---------------------------------------------------------------------------
-- lines

--- Prompt line: glyph, query, caret, and the count at the right.
--- Returns the text plus the spans to highlight.
local function prompt_line(session, cfg)
	local caret = cfg.prompt_caret or "▏"
	local spans = {}

	local prefix, value, cursor
	if session.prompt then
		prefix = " " .. session.prompt.label
		value = session.prompt.value or ""
		cursor = session.prompt.caret or vim.fn.strchars(value)
	else
		local icon = cfg.icons and session.source and session.source.icon
		prefix = (icon and icon ~= "") and (" " .. icon .. " ") or (" " .. cfg.prompt)
		value = session.query or ""
		cursor = session.caret or vim.fn.strchars(value)
	end

	local text = prefix .. vim.fn.strcharpart(value, 0, cursor)
	spans[#spans + 1] = { 0, #prefix, "LoupePrompt" }
	spans[#spans + 1] = { #text, #text + #caret, "LoupePromptCaret" }
	text = text .. caret .. vim.fn.strcharpart(value, cursor)

	if not session.prompt and value == "" and session.source then
		local ghost = session.source.label or ""
		if ghost ~= "" then
			ghost = " " .. ghost
			spans[#spans + 1] = { #text, #text + #ghost, "LoupeGhost" }
			text = text .. ghost
		end
	end
	return text, spans
end

--- One match row: padded, with the parent directory dimmed and the metadata
--- column right-aligned. Returns the line plus its highlight spans.
local function match_line(session, cfg, item, width, selected)
	local cand = item.cand
	local parts = display.row(cand, { git = cfg.git and session.git or nil, icons = cfg.icons })

	local mark = ""
	if session.marked and next(session.marked) ~= nil then
		mark = session.marked[cand.abs] and "● " or "  "
	end

	local meta_text = {}
	for _, chunk in ipairs(parts.meta) do
		meta_text[#meta_text + 1] = chunk[1]
	end
	local right = table.concat(meta_text, "  ")

	local inner = math.max(1, width - PAD * 2)
	local left_prefix = mark .. (parts.icon ~= "" and (parts.icon .. " ") or "")
	local right_room = right ~= "" and (vim.fn.strdisplaywidth(right) + GAP) or 0
	local left_room = math.max(1, inner - vim.fn.strdisplaywidth(left_prefix) - right_room)
	local label = fit(parts.dir .. parts.name, left_room)

	local left = left_prefix .. label
	local gap = math.max(GAP, inner - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
	local line = spaces(PAD) .. left .. spaces(right ~= "" and gap or (inner - vim.fn.strdisplaywidth(left)))
	local right_start = #line
	line = line .. right
	line = line .. spaces(width - vim.fn.strdisplaywidth(line))

	local spans = {}
	if selected then
		spans[#spans + 1] = { 0, #line, "LoupeSelection", 90 }
	end
	local at = PAD
	if mark ~= "" then
		if session.marked[cand.abs] then
			spans[#spans + 1] = { at, at + #mark, "LoupeMark" }
		end
		at = at + #mark
	end
	if parts.icon ~= "" then
		spans[#spans + 1] = { at, at + #parts.icon, parts.icon_hl }
		at = at + #parts.icon + 1
	end
	-- `at` now sits where the matched text starts, so matcher offsets land
	-- without translation.
	if #parts.dir > 0 then
		spans[#spans + 1] = { at, at + math.min(#parts.dir, #label), "LoupeDir" }
	end
	for _, col in ipairs(item.positions) do
		if col < #label then
			spans[#spans + 1] = { at + col, at + col + 1, "LoupeMatch", 200 }
		end
	end
	if right ~= "" then
		local col = right_start
		for i, chunk in ipairs(parts.meta) do
			if i > 1 then
				col = col + 2
			end
			spans[#spans + 1] = { col, col + #chunk[1], chunk[2] or "LoupeMeta" }
			col = col + #chunk[1]
		end
	end
	return line, spans
end

--- The window bar: source tabs, or the action menu while it is open. It is
--- the picker's only chrome, so the keys that open each menu live here too —
--- the source key at the left, and, when the root has nothing to say, the
--- action key at the right.
local function winbar_text(session, cfg, width)
	local maps = cfg.mappings or {}
	local function browse_key(action)
		return M.friendly_key(key_for(maps.browse or {}, action) or "")
	end
	local cancel = browse_key("close") .. " cancel"

	if session.prompt then
		local prompt_map = maps.prompt or {}
		local entries = {}
		for _, pair in ipairs({ { "submit", "confirm" }, { "cancel", "cancel" } }) do
			local key = key_for(prompt_map, pair[1])
			if key then
				entries[#entries + 1] = { key, pair[2] }
			end
		end
		return M.menu(entries, width, "")
	end

	if session.menu == "actions" then
		return M.menu(M.action_entries(session, cfg), width, cancel)
	end

	local select = session.menu == "sources"
	local right = root_text(session)
	if right == "" and not select then
		right = browse_key("menu") .. " actions"
	end
	return M.tabs(session.sources or {}, session.source and session.source.name, width, {
		right = select and cancel or right,
		-- while the menu is open the key has already been pressed: the room is
		-- better spent on the tabs it is about
		hint = not select and browse_key("sources") or nil,
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
