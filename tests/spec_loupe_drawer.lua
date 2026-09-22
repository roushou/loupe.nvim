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
	h.ok(drawer.tabs(source.order, "files", 200, "src/x/"):find("%%=%%#LoupeTab#src/x/ "))
end)

h.test("friendly_key spells keys the way people say them", function()
	h.eq(drawer.friendly_key("<C-X>"), "ctrl+x")
	h.eq(drawer.friendly_key("<CR>"), "enter")
	h.eq(drawer.friendly_key("<Tab>"), "tab")
	h.eq(drawer.friendly_key("r"), "r")
end)

h.test("hints advertise the browse keys, then the open submenu", function()
	local cfg = require("loupe.config").get()
	local browse = drawer.hints(session(), cfg)
	h.eq(browse[1], { "<CR>", "open" })
	local labels = vim.tbl_map(function(hint)
		return hint[2]
	end, browse)
	h.eq(labels, { "open", "actions", "sources", "mark" })

	local menu = drawer.hints(session({ menu = "actions" }), cfg)
	h.ok(#menu > 4, "action menu not listed")
	h.eq(menu[1], { "r", "rename" }, "actions are not in their canonical order")
	h.eq(menu[2], { "d", "delete" })

	local sources = drawer.hints(session({ menu = "sources" }), cfg)
	h.eq(sources[1], { "f", "Files" }, "sources do not follow the tab order")
	h.eq(sources[2], { "d", "Dirs" })
end)

h.test("hints name delete as close where the source closes buffers", function()
	local cfg = require("loupe.config").get()
	local menu = drawer.hints(session({ source = source.get("buffers"), menu = "actions" }), cfg)
	local found
	for _, hint in ipairs(menu) do
		if hint[2] == "close" then
			found = hint[1]
		end
	end
	h.eq(found, "d")
end)

h.test("action_label renames delete where a source closes buffers", function()
	h.eq(drawer.action_label({ source = source.get("buffers") }, "delete"), "close")
	h.eq(drawer.action_label({ source = source.get("buffers") }, "rename"), "rename")
	h.eq(drawer.action_label(session(), "delete"), "delete")
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
	vim.api.nvim_win_close(win, true)
	return lines, marks, s
end

local function cands(n)
	local out = {}
	for i = 1, n do
		out[i] = { cand = { rel = ("dir/file%02d.lua"):format(i), abs = "/p/f" .. i }, positions = {} }
	end
	return out
end

h.test("render fills exactly the window height", function()
	local lines = render({ matches = cands(3), candidates = {} })
	h.eq(#lines, 8, "expected one line per window row")
	h.ok(lines[1]:find("…") == nil)
	h.ok(lines[2]:find("file01.lua", 1, true), "first match missing: " .. lines[2])
	h.ok(lines[8]:find("enter open", 1, true), "hint bar missing: " .. lines[8])
end)

h.test("render scrolls the viewport to keep the selection visible", function()
	local lines, _, s = render({ matches = cands(50), candidates = {}, index = 40 })
	h.eq(s.top, 35, "viewport did not follow the selection")
	h.ok(lines[7]:find("file40.lua", 1, true), "selected row not in view: " .. lines[7])
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
