--- rg backend: fallback file enumerator and the primary live grep.
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
	--- Results stream in as rg finds them and the process is stopped once
	--- `ctx.limit` candidates exist. Returns a cancel function.
	grep = function(query, ctx, cb)
		if query == "" then
			cb({}, true, true)
			return
		end
		return run.stream({ "rg", "--json", "--smart-case", "--", query }, ctx.root, function(lines)
			return parse.rgjson_lines(lines, ctx.root)
		end, cb, ctx.limit)
	end,
}

return M
