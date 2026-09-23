--- changed: files git reports as modified, added, deleted or untracked.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

return {
	list = {
		changed = {
			git = function(ctx, cb)
				run.raw({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, ctx.root, function(stdout)
					return parse.status(stdout, ctx.root)
				end, cb)
			end,
		},
	},
}
