local h = require("tests.harness")
local source = require("loupe.source")

h.test("built-in sources are registered", function()
	for _, name in ipairs({
		"files",
		"dirs",
		"buffers",
		"recent",
		"changed",
		"grep",
		"symbols",
		"doc_symbols",
		"diagnostics",
	}) do
		local s = source.get(name)
		h.ok(s, name .. " missing")
		h.eq(s.name, name)
	end
end)

h.test("load dispatches a function source", function()
	local fake = {
		name = "fake_fn",
		list = function(_, cb)
			cb({ { rel = "x" } }, true)
		end,
	}
	local got
	source.load(fake, { root = "/r" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got[1][1].rel, "x")
	h.eq(got[2], true)
end)

h.test("load resolves a backend op source", function()
	local backend = require("loupe.backend")
	backend.registry.srcfake = { list = {
		srcop = function(_, cb)
			cb({ { rel = "op" } }, true)
		end,
	} }
	local got
	source.load({ name = "srcop", list = "srcop", backend = { "srcfake" } }, { root = "/r" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got[1][1].rel, "op")
	h.eq(got[2], true)
	backend.registry.srcfake = nil
end)

h.test("load reports failure when no backend is available", function()
	local got
	source.load({ name = "nope", list = "nope", backend = { "ghost" } }, { root = "/r" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got, { {}, false })
end)

h.test("search dispatches a function source", function()
	local fake = {
		name = "fake_search",
		search = function(q, ctx, cb)
			cb({ { rel = q .. ctx.root } }, true)
		end,
	}
	local got
	source.search(fake, "x", { root = "/r" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got[1][1].rel, "x/r")
end)

h.test("search resolves a backend search op", function()
	local backend = require("loupe.backend")
	backend.registry.srchfake = {
		search = {
			srop = function(q, _, cb)
				cb({ { rel = q } }, true)
			end,
		},
	}
	local got
	source.search(
		{ name = "srop", search = "srop", backend = { "srchfake" } },
		"q",
		{ root = "/r" },
		function(cands, ok)
			got = { cands, ok }
		end
	)
	h.eq(got[1][1].rel, "q")
	h.eq(got[2], true)
	backend.registry.srchfake = nil
end)

h.test("search reports failure when no backend is available", function()
	local got
	source.search({ name = "nope", search = "nope", backend = { "ghost" } }, "q", { root = "/r" }, function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got, { {}, false })
end)
