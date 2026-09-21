local h = require("tests.harness")
local parse = require("loupe.backend.parse")

h.test("paths parses, strips ./ and builds abs", function()
	local out = parse.paths("./a.lua\nsrc/b.lua\n", "/root", false)
	h.eq(#out, 2)
	h.eq(out[1], { rel = "a.lua", abs = "/root/a.lua", dir = false })
	h.eq(out[2], { rel = "src/b.lua", abs = "/root/src/b.lua", dir = false })
end)

h.test("paths marks directories and strips the trailing slash", function()
	local out = parse.paths("src/\nlib/\n", "/root", true)
	h.eq(out[1], { rel = "src", abs = "/root/src", dir = true })
	h.eq(out[2], { rel = "lib", abs = "/root/lib", dir = true })
end)

h.test("paths dedupes and drops blank lines", function()
	local out = parse.paths("a\n\na\nb\n", "/r", false)
	h.eq(#out, 2)
	h.eq(out[1].rel, "a")
	h.eq(out[2].rel, "b")
end)

h.test("paths tolerates empty output", function()
	h.eq(parse.paths("", "/r", false), {})
	h.eq(parse.paths(nil, "/r", true), {})
end)

h.test("derive_dirs extracts parents, ignoring root files", function()
	local files = {
		{ rel = "a.lua", abs = "/r/a.lua" },
		{ rel = "src/b.lua", abs = "/r/src/b.lua" },
		{ rel = "src/deep/c.lua", abs = "/r/src/deep/c.lua" },
	}
	local out = parse.derive_dirs(files, "/r")
	h.eq(#out, 2)
	h.eq(out[1], { rel = "src", abs = "/r/src", dir = true })
	h.eq(out[2], { rel = "src/deep", abs = "/r/src/deep", dir = true })
end)

h.test("relpath strips the root prefix, falls back to basename", function()
	h.eq(parse.relpath("/r", "/r/src/a.lua"), "src/a.lua")
	h.eq(parse.relpath("/r", "/elsewhere/a.lua"), "a.lua")
end)

h.test("status parses porcelain -z including renames", function()
	-- " M a.lua", "?? b.lua", "R  c.lua" + original "old.lua"
	local s = " M a.lua\0?? b.lua\0R  c.lua\0old.lua\0"
	local out = parse.status(s, "/r")
	h.eq(#out, 3)
	h.eq(out[1], { rel = "a.lua", abs = "/r/a.lua", label = "a.lua", dir = false })
	h.eq(out[2].rel, "b.lua")
	h.eq(out[3].rel, "c.lua")
end)

h.test("status preserves paths with spaces", function()
	local out = parse.status("?? my file.lua\0", "/r")
	h.eq(out[1].rel, "my file.lua")
end)

h.test("rgjson parses match events with submatch ranges", function()
	local ev = vim.json.encode({
		type = "match",
		data = {
			path = { text = "lua/a.lua" },
			lines = { text = "local M = {}\n" },
			line_number = 12,
			submatches = { { start = 6, ["end"] = 7 } },
		},
	})
	local out = parse.rgjson(ev, "/r")
	h.eq(#out, 1)
	h.eq(out[1], {
		rel = "lua/a.lua",
		abs = "/r/lua/a.lua",
		label = "lua/a.lua:12: local M = {}",
		lnum = 12,
		col = 6,
		col_end = 7,
		dir = false,
	})
end)

h.test("rgjson yields one candidate per submatch, ignoring other events", function()
	local begin = vim.json.encode({ type = "begin", data = { path = { text = "a.lua" } } })
	local match = vim.json.encode({
		type = "match",
		data = {
			path = { text = "a.lua" },
			lines = { text = "x x x\n" },
			line_number = 1,
			submatches = { { start = 0, ["end"] = 1 }, { start = 2, ["end"] = 3 } },
		},
	})
	local out = parse.rgjson(begin .. "\n" .. match, "/r")
	h.eq(#out, 2)
	h.eq(out[2].col, 2)
	h.eq(out[2].col_end, 3)
end)

h.test("rgjson tolerates empty and malformed output", function()
	h.eq(parse.rgjson("", "/r"), {})
	h.eq(parse.rgjson("not json\n", "/r"), {})
end)

h.test("gitgrep parses path:line:text with column 0", function()
	local out = parse.gitgrep("lua/a.lua:12:local M = {}\n", "/r")
	h.eq(#out, 1)
	h.eq(out[1], {
		rel = "lua/a.lua",
		abs = "/r/lua/a.lua",
		label = "lua/a.lua:12: local M = {}",
		lnum = 12,
		col = 0,
		dir = false,
	})
end)
