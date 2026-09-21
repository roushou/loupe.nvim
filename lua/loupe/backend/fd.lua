--- fd backend: the primary file and directory enumerator.
---
--- `fd` is purpose-built for path finding, respects `.gitignore` and skips
--- hidden entries by default, and is fast on large trees. With no search
--- pattern it lists everything under the cwd, relative and unprefixed.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "fd" }

M.list = {
	files = function(ctx, cb)
		run.raw({ "fd", "--type", "f" }, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, false)
		end, cb)
	end,
	dirs = function(ctx, cb)
		run.raw({ "fd", "--type", "d" }, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, true)
		end, cb)
	end,
}

return M
