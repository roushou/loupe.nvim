local h = require("tests.harness")
local backend = require("loupe.backend")

local CANDS = {
	{ rel = "src/main.lua", abs = "/x/src/main.lua" },
	{ rel = "README.md", abs = "/x/README.md" },
	{ rel = "src/util.lua", abs = "/x/src/util.lua" },
}

h.test("match ranks candidates and returns positions", function()
	local out = backend.match("main", CANDS, 10)
	h.eq(#out, 1)
	h.eq(out[1].cand.rel, "src/main.lua")
	h.ok(#out[1].positions > 0)
end)

h.test("empty query returns candidates in order, capped", function()
	local cands = {}
	for i = 1, 10 do
		cands[i] = { rel = "f" .. i, abs = "/x/f" .. i }
	end
	local out = backend.match("", cands, 3)
	h.eq(#out, 3)
	h.eq(out[1].cand.rel, "f1")
end)

h.test("match returns nothing for no hits", function()
	h.eq(backend.match("zzzzz", CANDS, 10), {})
end)

h.test("resolve prefers the first available backend", function()
	backend.registry.fake = { list = {
		files = function(_, cb)
			cb({ { rel = "x" } }, true)
		end,
	} }
	local id, fn = backend.resolve("files", { "ghost", "fake" })
	h.eq(id, "fake")
	h.ok(fn)
	local got
	fn({ root = "/r" }, function(cands)
		got = cands
	end)
	h.eq(got[1].rel, "x")
	backend.registry.fake = nil
end)

h.test("resolve skips backends whose executable is missing", function()
	backend.registry.ghost = { exe = "loupe-no-such-binary", list = { files = function() end } }
	h.eq(backend.resolve("files", { "ghost" }), nil)
	backend.registry.ghost = nil
end)

h.test("resolve_list cascades on failure", function()
	local calls = {}
	local function mk(name, ok)
		return {
			list = {
				files = function(_, cb)
					calls[#calls + 1] = name
					cb(ok and { { rel = name } } or {}, ok)
				end,
			},
		}
	end
	backend.registry.bad = mk("bad", false)
	backend.registry.good = mk("good", true)
	local got
	backend.resolve_list("files", { root = "/r" }, { "bad", "good" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(calls, { "bad", "good" })
	h.eq(got[2], true)
	h.eq(got[1][1].rel, "good")
	backend.registry.bad, backend.registry.good = nil, nil
end)

h.test("resolve_list reports failure when exhausted", function()
	local got
	backend.resolve_list("files", { root = "/r" }, { "nope" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got, { {}, false })
end)

h.test("resolve can select a search op", function()
	backend.registry.searchfake = { search = { grep = function() end } }
	local id, fn = backend.resolve("grep", { "searchfake" }, "search")
	h.eq(id, "searchfake")
	h.ok(fn)
	backend.registry.searchfake = nil
end)

h.test("resolve defaults to the list kind", function()
	backend.registry.kindfake = { list = { files = function() end }, search = { files = function() end } }
	local id, fn = backend.resolve("files", { "kindfake" })
	h.eq(id, "kindfake")
	h.ok(fn)
	backend.registry.kindfake = nil
end)
