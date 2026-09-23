local h = require("tests.harness")
local drawer = require("loupe.drawer")
local source = require("loupe.source")

local function session(over)
	return vim.tbl_extend("force", {
		source = source.get("files"),
		sources = source.order,
		loaded = true,
		matches = { {}, {} },
		candidates = { {}, {}, {}, {} },
		root = "/p",
		project_root = "/p",
		index = 1,
		top = 1,
		query = "",
		caret = 0,
		marked = {},
	}, over or {})
end

h.test("count_text shows shown/total for static sources", function()
	h.eq(drawer.count_text(session()), "2/4")
	h.eq(drawer.count_text(session({ candidates = { {}, {} } })), "2")
	h.eq(drawer.count_text(session({ loaded = false, matches = {} })), "…")
end)

h.test("count_text marks truncated and streaming dynamic results", function()
	local s = session({ source = source.get("grep"), truncated = true, searching = true })
	h.eq(drawer.count_text(s), "4+ …")
	s.truncated, s.searching = false, false
	h.eq(drawer.count_text(s), "4")
end)

h.test("tabs highlight the active source", function()
	local bar = drawer.tabs(source.order, "buffers", 200)
	h.ok(bar:find("%%#LoupeTabActive# Buffers "), "active tab not highlighted: " .. bar)
	h.ok(bar:find("%%#LoupeTab# Files "), "inactive tab not dim: " .. bar)
end)

h.test("tabs keep the active source visible when the strip does not fit", function()
	local bar = drawer.tabs(source.order, "diagnostics", 24)
	h.ok(bar:find("LoupeTabActive"), "active tab scrolled out of view")
	h.ok(not bar:find("Files"), "narrow strip still starts at the first tab")
end)

h.test("tabs append right-hand text", function()
	h.ok(drawer.tabs(source.order, "files", 200, { right = "src/x/" }):find("%%=src/x/ "), "root missing")
end)

h.test("tabs show the key that opens the source menu", function()
	h.ok(drawer.tabs(source.order, "files", 200, { hint = "ctrl+o" }):find(" ctrl+o ", 1, true))
end)

--- The strip's text with the highlight markers taken out.
local function plain(bar)
	return (bar:gsub("%%#[%w]+#", ""):gsub("%%=", ""))
end

h.test("selecting keeps the strip's text exactly where it was", function()
	local keys = { files = "f", dirs = "d", buffers = "b" }
	local sources = { source.get("files"), source.get("dirs"), source.get("buffers") }
	local idle = drawer.tabs(sources, "files", 200, { hint = "ctrl+o", keys = keys })
	local lit = drawer.tabs(sources, "files", 200, { hint = "ctrl+o", keys = keys, select = true })
	-- nothing may move between the two states: only the colours change
	h.eq(plain(lit), plain(idle))
	h.ok(lit:find("LoupeTabSelectKey#F", 1, true), "key not marked in place: " .. lit)
	h.ok(lit:find("LoupeTabSelectKey#B", 1, true), "key not marked in place: " .. lit)
	h.ok(lit:find("LoupeTabSelectActive", 1, true), "active tab not marked")
	h.ok(not idle:find("LoupeTabSelect", 1, true), "idle strip is lit")
end)

h.test("a key that is not in the label is appended to it", function()
	local sources = { source.get("doc_symbols") }
	local lit = drawer.tabs(sources, "doc_symbols", 200, { keys = { doc_symbols = "t" }, select = true })
	h.eq(plain(lit), " Doc t ")
	h.ok(lit:find("LoupeTabSelectKey#t", 1, true), "appended key not marked: " .. lit)
end)

h.test("friendly_key spells keys the way people say them", function()
	h.eq(drawer.friendly_key("<C-X>"), "ctrl+x")
	h.eq(drawer.friendly_key("<CR>"), "enter")
	h.eq(drawer.friendly_key("<Tab>"), "tab")
	h.eq(drawer.friendly_key("r"), "r")
end)

--- Render a session into a real drawer split and return its lines.
local function render(over)
	local buf = require("loupe.util.buf").scratch({})
	vim.cmd("botright 8split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	local s = session(vim.tbl_extend("force", { drawer_win = win, list_buf = buf }, over or {}))
	drawer.render(s, require("loupe.config").get())
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local marks =
		vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("loupe_matches"), 0, -1, { details = true })
	-- how many lines the window can actually show, window bar deducted
	local visible = vim.fn.line("w$", win)
	vim.api.nvim_win_close(win, true)
	return lines, marks, s, visible
end

local function cands(n)
	local out = {}
	for i = 1, n do
		out[i] = { cand = { rel = ("dir/file%02d.lua"):format(i), abs = "/p/f" .. i }, positions = {} }
	end
	return out
end

h.test("render draws every line where it can be seen", function()
	local lines, _, _, visible = render({ matches = cands(3), candidates = {} })
	-- the window bar costs a text row: draw one line too many and the hint bar
	-- lands below the fold, where it may as well not exist
	h.eq(#lines, visible, "the last line is drawn outside the visible area")
	h.ok(lines[2]:find("file01.lua", 1, true), "first match missing: " .. lines[2])
	h.ok(lines[4]:find("file03.lua", 1, true), "last match missing: " .. lines[4])
	h.eq(lines[#lines], "", "short lists should pad with blank rows")

	-- a full list fills every row, the last one included
	local full, _, _, rows = render({ matches = cands(50), candidates = {} })
	h.eq(#full, rows)
	h.ok(full[#full]:find("file", 1, true), "last visible row is not a match: " .. full[#full])
end)

h.test("render scrolls the viewport to keep the selection visible", function()
	local lines, _, s, visible = render({ matches = cands(50), candidates = {}, index = 40 })
	local rows = visible - 1
	h.eq(s.top, 40 - rows + 1, "viewport did not follow the selection")
	h.ok(lines[visible]:find("file40.lua", 1, true), "selected row not in view: " .. lines[visible])
end)

h.test("render paints a selection band on the selected row", function()
	local _, marks = render({ matches = cands(3), candidates = {}, index = 2 })
	local band
	for _, m in ipairs(marks) do
		if m[4].hl_group == "LoupeSelection" then
			band = m[2]
		end
	end
	h.eq(band, 2, "band is not on the selected row")
end)

h.test("render shows the empty and loading states", function()
	h.ok(render({ matches = {}, candidates = {} })[2]:find("(no matches)", 1, true))
	h.ok(render({ matches = {}, candidates = {}, loaded = false })[2]:find("(loading…)", 1, true))
end)

h.test("render shows the source label as ghost text on an empty query", function()
	h.ok(render({ matches = cands(1), candidates = {} })[1]:find("Files", 1, true), "ghost label missing")
	h.ok(not render({ matches = cands(1), candidates = {}, query = "x", caret = 1 })[1]:find("Files", 1, true))
end)

h.test("render highlights matched characters at the right columns", function()
	local item = { cand = { rel = "dir/file.lua", abs = "/p/x" }, positions = { 0, 4 } }
	local _, marks = render({ matches = { item }, candidates = {}, query = "df", caret = 2 })
	local cols = {}
	for _, m in ipairs(marks) do
		if m[4].hl_group == "LoupeMatch" then
			cols[#cols + 1] = m[3]
		end
	end
	table.sort(cols)
	h.eq(#cols, 2, "expected one highlight per matched character")
	local line = render({ matches = { item }, candidates = {}, query = "df", caret = 2 })[2]
	h.eq(line:sub(cols[1] + 1, cols[1] + 1), "d", "first match is off: " .. line)
	h.eq(line:sub(cols[2] + 1, cols[2] + 1), "f", "second match is off: " .. line)
end)

h.test("render dims the parent directory of a path row", function()
	local item = { cand = { rel = "dir/file.lua", abs = "/p/x" }, positions = {} }
	local _, marks = render({ matches = { item }, candidates = {} })
	local dim
	for _, m in ipairs(marks) do
		if m[4].hl_group == "LoupeDir" then
			dim = { m[3], m[4].end_col }
		end
	end
	h.ok(dim, "no dimmed directory")
	local line = render({ matches = { item }, candidates = {} })[2]
	h.eq(line:sub(dim[1] + 1, dim[2]), "dir/")
end)

h.test("a named key leads its label", function()
	-- a source bound to something other than a bare letter: the key cannot be
	-- marked inside the label, so it goes in front of it
	local sources = { source.get("doc_symbols") }
	local lit = drawer.tabs(sources, "doc_symbols", 200, { keys = { doc_symbols = "ctrl+t" }, select = true })
	h.eq(plain(lit), " ctrl+t Doc ")
end)

h.test("a shifted key is appended rather than marked in place", function()
	-- the `d` of "Dirs" is not `D`, so pointing at it would name the wrong key
	local sources = { source.get("dirs") }
	local lit = drawer.tabs(sources, "dirs", 200, { keys = { dirs = "D" }, select = true })
	h.eq(plain(lit), " Dirs D ")
	h.ok(lit:find("LoupeTabSelectKey#D", 1, true), "shifted key not appended: " .. lit)
end)

h.test("a location row puts its text left and its location right", function()
	local item = {
		cand = {
			rel = "lua/a.lua",
			abs = "/p/lua/a.lua",
			text = "local M = {}",
			meta = "lua/a.lua:12",
			text_col = 6,
			text_col_end = 7,
			lnum = 12,
		},
		positions = {},
	}
	local lines, marks = render({ matches = { item }, candidates = {} })
	local row = lines[2]
	h.ok(row:find("local M = {}", 1, true), "text missing: " .. row)
	h.ok(row:find("lua/a.lua:12%s*$"), "location is not at the right edge: " .. row)

	local hit
	for _, m in ipairs(marks) do
		if m[4].hl_group == "LoupeMatch" and m[2] == 1 then
			hit = { m[3], m[4].end_col }
		end
	end
	h.ok(hit, "the match inside the line was not highlighted")
	h.eq(row:sub(hit[1] + 1, hit[2]), "M", "the highlight is off the match: " .. row)
end)

h.test("a location row highlights only what is on the left", function()
	-- the label spans both columns, so a match in the location must not be
	-- painted over the text that happens to sit at that offset
	local item = {
		cand = { rel = "a.lua", abs = "/p/a.lua", text = "abc", meta = "a.lua:1", lnum = 1 },
		positions = { 0, 10 },
	}
	local _, marks = render({ matches = { item }, candidates = {} })
	local n = 0
	for _, m in ipairs(marks) do
		if m[4].hl_group == "LoupeMatch" then
			n = n + 1
		end
	end
	h.eq(n, 1, "a position past the left column was highlighted anyway")
end)

-- The window bar is the picker's only chrome, and it borders the list rather
-- than the buffer further up. Both of its states have to stay legible and
-- stay distinguishable from that list, or the bar reads as part of it.
--
-- Driven through a palette of known colours rather than whatever theme is
-- loaded: what is under test is the arithmetic, not somebody's colourscheme.

local CHROME = {
	Normal = { fg = 0xdcd7ba, bg = 0x1f1f28 },
	StatusLine = { fg = 0xc8c093, bg = 0x16161d },
	Title = { fg = 0x7e9cd8, bold = true },
	Comment = { fg = 0x727169 },
}

--- Open the drawer with `CHROME` in place, so the bar groups are recomputed
--- from colours the assertions below can be written against.
local function open_with_palette()
	for name, attrs in pairs(CHROME) do
		vim.api.nvim_set_hl(0, name, attrs)
	end
	for _, group in ipairs({
		"LoupeBorder",
		"LoupeTab",
		"LoupeTabActive",
		"LoupeTabSelect",
		"LoupeTabSelectActive",
		"LoupeTabSelectKey",
	}) do
		vim.cmd("highlight clear " .. group)
	end
	drawer.open(10)
end

--- Relative luminance of a highlight group's resolved `key` colour.
local function luminance(group, key)
	local rgb = vim.api.nvim_get_hl(0, { name = group, link = false })[key]
	h.ok(rgb, group .. " has no " .. key)
	local function channel(shift)
		local c = (math.floor(rgb / shift) % 256) / 255
		return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(65536) + 0.7152 * channel(256) + 0.0722 * channel(1)
end

local function ratio(a, b)
	if a < b then
		a, b = b, a
	end
	return (a + 0.05) / (b + 0.05)
end

h.test("every label on the window bar clears the contrast floor", function()
	open_with_palette()
	for _, case in ipairs({
		-- { group, the ground it is drawn on }
		{ "LoupeTab", "LoupeBorder" },
		{ "LoupeTabActive", "LoupeBorder" },
		{ "LoupeTabSelect", "LoupeTabSelect" },
		{ "LoupeTabSelectActive", "LoupeTabSelectActive" },
		{ "LoupeTabSelectKey", "LoupeTabSelectKey" },
	}) do
		local r = ratio(luminance(case[1], "fg"), luminance(case[2], "bg"))
		h.ok(r >= 4.5, ("%s reads at %.2f:1 on %s, below 4.5:1"):format(case[1], r, case[2]))
	end
end)

h.test("the lit strip is a different surface from the list below it", function()
	open_with_palette()
	-- plain luminance, not the WCAG ratio: that formula's +0.05 term is there
	-- to model text on a ground, and it flattens two dark surfaces to within
	-- a hair of each other however far apart they actually are
	local lit, list = luminance("LoupeTabSelect", "bg"), luminance("Normal", "bg")
	local r = math.max(lit, list) / math.min(lit, list)
	-- 1.5 is well under what a lift aims for; it catches the strip landing on
	-- the list's own colour, which is what happens when the lift is measured
	-- against the buffer above the drawer instead
	h.ok(r >= 1.5, ("an open menu is indistinguishable from the list (%.2fx)"):format(r))
end)

h.test("the resting bar sits below the list rather than on it", function()
	open_with_palette()
	h.ok(
		luminance("LoupeBorder", "bg") < luminance("Normal", "bg"),
		"the window bar is not recessed from the list it borders"
	)
end)
