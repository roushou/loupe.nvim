--- Bottom drawer: a real horizontal split holding the picker chrome.
---
--- The buffer is a `nofile` scratch buffer drawn as a fixed-size viewport, not
--- a scrolling list: it always holds exactly as many lines as the window is
--- tall, and only the visible slice of matches is built. The window itself
--- never scrolls (the cursor stays on line 1), so the selection is painted
--- rather than followed.
---
---   row 1         prompt: source glyph, query, caret, count
---   rows 2..h-1   matches, one per line
---   row h         hint bar: what the keys do right now
---
--- The source tabs live in the window bar, where they cost no list rows.

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
	vim.api.nvim_set_hl(0, "LoupeKey", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "LoupeHint", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "LoupeTab", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "LoupeTabActive", { link = "Title", default = true })
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
		winbar = "",
	})

	return { win = winid, buf = bufnr }
end

--- How many match rows fit: everything but the prompt and the hint bar.
function M.capacity(winid)
	if not (winid and vim.api.nvim_win_is_valid(winid)) then
		return 1
	end
	return math.max(1, vim.api.nvim_win_get_height(winid) - 2)
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

--- Source tabs as a window-bar string, the active source highlighted. The
--- strip is sliced to `width` around the active tab, so a narrow window keeps
--- showing where you are rather than the first few sources.
function M.tabs(sources, active, width, right)
	local blocks, col = {}, 0
	for _, src in ipairs(sources) do
		local text = " " .. (src.tab or src.label or src.name) .. " "
		blocks[#blocks + 1] = { text = text, from = col, to = col + #text, active = src.name == active }
		col = col + #text
	end

	right = right or ""
	local avail = math.max(1, width - (right == "" and 0 or #right + 2))
	local offset = 0
	if col > avail then
		for _, b in ipairs(blocks) do
			if b.active then
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
			parts[#parts + 1] = ("%%#%s#%s"):format(
				b.active and "LoupeTabActive" or "LoupeTab",
				text:gsub("%%", "%%%%")
			)
		end
	end
	if right ~= "" then
		parts[#parts + 1] = "%=%#LoupeTab#" .. right:gsub("%%", "%%%%") .. " "
	end
	return table.concat(parts)
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

--- First key bound to `action` in `map`, in a stable order.
local function key_for(map, action)
	local found
	for lhs, name in pairs(map) do
		if name == action and (not found or lhs < found) then
			found = lhs
		end
	end
	return found
end

--- The hint bar: `{ key, label }` pairs for whatever the next keypress can do.
--- While a submenu is open it lists that menu; otherwise the handful of keys
--- worth advertising.
function M.hints(session, cfg)
	local maps = cfg.mappings or {}
	local out = {}
	if session.prompt then
		for _, pair in ipairs({ { "submit", "confirm" }, { "cancel", "cancel" } }) do
			local key = key_for(maps.prompt or {}, pair[1])
			if key then
				out[#out + 1] = { key, pair[2] }
			end
		end
		return out
	end
	if session.menu == "sources" then
		-- listed in tab order, so the menu and the strip agree
		for _, src in ipairs(session.sources or {}) do
			local key = key_for(maps.sources or {}, src.name)
			if key then
				out[#out + 1] = { key, src.tab or src.label or src.name }
			end
		end
		return out
	end
	if session.menu == "actions" then
		local map = maps.menu or {}
		local seen = {}
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
	for _, pair in ipairs({
		{ "open", "open" },
		{ "menu", "actions" },
		{ "sources", "sources" },
		{ "mark", "mark" },
	}) do
		local key = key_for(maps.browse or {}, pair[1])
		if key then
			out[#out + 1] = { key, pair[2] }
		end
	end
	return out
end

--- Name an action as the active source performs it, so the hint never
--- promises something the key does not do (`delete` closes a buffer in the
--- buffers source).
function M.action_label(session, name)
	if name == "delete" and session.source and session.source.delete == "buffer" then
		return "close"
	end
	return name
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

--- Hint bar line: `key label` pairs, keys bright and labels dim.
local function bar_line(session, cfg, width)
	local spans, parts, col = {}, {}, PAD
	for _, hint in ipairs(M.hints(session, cfg)) do
		local key = M.friendly_key(hint[1])
		local text = key .. " " .. hint[2]
		if #parts > 0 then
			parts[#parts + 1] = "  "
			col = col + 2
		end
		parts[#parts + 1] = text
		spans[#spans + 1] = { col, col + #key, "LoupeKey" }
		spans[#spans + 1] = { col + #key, col + #text, "LoupeHint" }
		col = col + #text
	end
	local line = spaces(PAD) .. fit(table.concat(parts), math.max(1, width - PAD * 2))
	return line .. spaces(width - vim.fn.strdisplaywidth(line)), spans
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
	local rows = M.capacity(winid)
	local lines, all = {}, {}

	local head, head_spans = prompt_line(session, cfg)
	lines[1] = head
	all[1] = head_spans

	if #session.matches == 0 then
		lines[2] = spaces(PAD) .. (session.loaded and "(no matches)" or "(loading…)")
		all[2] = { { PAD, #lines[2], "LoupeEmpty" } }
		for i = 3, rows + 1 do
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
	lines[rows + 2], all[rows + 2] = bar_line(session, cfg, width)

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

	vim.wo[winid].winbar =
		M.tabs(session.sources or {}, session.source and session.source.name, width, root_text(session))
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
