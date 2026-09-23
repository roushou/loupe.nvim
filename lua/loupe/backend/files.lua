--- files: every file under the root, one candidate per path.
---
--- `fd` is purpose-built for path finding, respects `.gitignore` and skips
--- hidden entries by default, and is fast on large trees. `rg --files` obeys
--- the same rules, so it substitutes cleanly. `git ls-files` only sees
--- tracked files, so it misses untracked-but-not-ignored ones; it is here to
--- keep the picker usable with neither of the others installed.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

--- Run `argv` in the root and read its output as a list of paths.
local function paths(argv)
	return function(ctx, cb)
		run.raw(argv, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, false)
		end, cb)
	end
end

return {
	list = {
		files = {
			fd = paths({ "fd", "--type", "f" }),
			rg = paths({ "rg", "--files" }),
			git = paths({ "git", "ls-files" }),
		},
	},
}
