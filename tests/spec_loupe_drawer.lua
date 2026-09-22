local h = require("tests.harness")
local drawer = require("loupe.drawer")

local function session(over)
	return vim.tbl_extend("force", {
		source = { label = "Files", name = "files" },
		loaded = true,
		matches = { {}, {} },
		candidates = { {}, {}, {}, {} },
		root = "/p",
		project_root = "/p",
	}, over or {})
end

h.test("title shows shown/total for static sources", function()
	h.eq(drawer.title(session()), { "Loupe", "Files", "2/4" })
end)

h.test("title collapses the count when everything is shown", function()
	h.eq(drawer.title(session({ candidates = { {}, {} } })), { "Loupe", "Files", "2" })
end)

h.test("title shows an ellipsis while loading", function()
	h.eq(drawer.title(session({ loaded = false, matches = {} })), { "Loupe", "Files", "…" })
end)

h.test("title marks truncated and streaming dynamic results", function()
	local s =
		session({ source = { label = "Grep", name = "grep", search = "grep" }, truncated = true, searching = true })
	h.eq(drawer.title(s), { "Loupe", "Grep", "4+ …" })
	s.truncated, s.searching = false, false
	h.eq(drawer.title(s), { "Loupe", "Grep", "4" })
end)

h.test("title shows the root when browsing below the project root", function()
	h.eq(drawer.title(session({ root = "/p/src/x" })), { "Loupe", "Files", "2/4", "src/x/" })
end)

h.test("title shows the full path when browsing above the project root", function()
	local parts = drawer.title(session({ root = "/" }))
	h.eq(parts[4], "/")
end)

h.test("action_label renames delete where a source closes buffers", function()
	local buffers = require("loupe.source").get("buffers")
	h.eq(drawer.action_label({ source = buffers }, "delete"), "close")
	h.eq(drawer.action_label({ source = buffers }, "rename"), "rename")
	h.eq(drawer.action_label(session(), "delete"), "delete")
end)
