--- git backend: tracked-file enumerator (last-resort file fallback).
---
--- `git ls-files` only lists tracked files, so it misses untracked-but-not-
--- ignored ones; it exists purely to keep the picker usable with neither fd
--- nor rg installed.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "git" }

M.list = {
	files = function(ctx, cb)
		run.raw({ "git", "ls-files" }, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, false)
		end, cb)
	end,
	changed = function(ctx, cb)
		run.raw({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, ctx.root, function(stdout)
			return parse.status(stdout, ctx.root)
		end, cb)
	end,
}

M.search = {
	--- Fallback content search (`git grep` uses basic regex, no columns).
	grep = function(query, ctx, cb)
		if query == "" then
			cb({}, true)
			return
		end
		run.raw({ "git", "grep", "-n", "--no-color", "-e", query }, ctx.root, function(stdout)
			return parse.gitgrep(stdout, ctx.root)
		end, cb)
	end,
}

return M
