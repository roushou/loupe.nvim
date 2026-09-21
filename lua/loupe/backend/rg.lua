--- rg backend: fallback file enumerator (and the future grep source).
---
--- `rg --files` respects `.gitignore` and skips hidden/binary files just like
--- fd, so it is a safe substitute when fd is unavailable.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "rg" }

M.list = {
	files = function(ctx, cb)
		run.raw({ "rg", "--files" }, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, false)
		end, cb)
	end,
}

M.search = {
	--- Live content search. JSON output gives the full line plus exact byte
	--- ranges for each submatch, so the preview can highlight the occurrence.
	grep = function(query, ctx, cb)
		if query == "" then
			cb({}, true)
			return
		end
		run.raw({ "rg", "--json", "--smart-case", "--max-count", "30", "--", query }, ctx.root, function(stdout)
			return parse.rgjson(stdout, ctx.root)
		end, cb)
	end,
}

return M
