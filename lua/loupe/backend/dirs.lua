--- dirs: every directory under the root.
---
--- Only `fd` enumerates directories directly. With no directory enumerator
--- available (or when it finds nothing) the facade derives them from the file
--- list instead — see `M.list` in `loupe.backend`.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

return {
	list = {
		dirs = {
			fd = function(ctx, cb)
				run.raw({ "fd", "--type", "d" }, ctx.root, function(stdout)
					return parse.paths(stdout, ctx.root, true)
				end, cb)
			end,
		},
	},
}
