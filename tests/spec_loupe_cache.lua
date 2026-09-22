local h = require("tests.harness")
local cache = require("loupe.cache")
local frecency = require("loupe.frecency")

h.test("cache stores per root and source", function()
	cache.clear()
	local a = { { rel = "a" } }
	cache.put("/r", "files", a)
	h.eq(cache.get("/r", "files"), a)
	h.eq(cache.get("/r", "dirs"), nil)
	h.eq(cache.get("/other", "files"), nil)
	cache.clear()
	h.eq(cache.get("/r", "files"), nil)
end)

h.test("frecency.promote moves scored entries to the front in score order", function()
	frecency.path = vim.fn.tempname()
	local cands = {
		{ rel = "a", abs = "/p/a" },
		{ rel = "b", abs = "/p/b" },
		{ rel = "c", abs = "/p/c" },
		{ rel = "d", abs = "/p/d" },
	}
	h.eq(frecency.promote(cands), cands, "no scores: same table back")
	frecency.record("/p/c")
	frecency.record("/p/d")
	frecency.record("/p/d")
	local out = frecency.promote(cands)
	h.eq(
		vim.tbl_map(function(c)
			return c.rel
		end, out),
		{ "d", "c", "a", "b" }
	)
	h.eq(
		vim.tbl_map(function(c)
			return c.rel
		end, frecency.sort(vim.deepcopy(cands))),
		{ "d", "c", "a", "b" },
		"same order as a full sort"
	)
end)
