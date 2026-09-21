--- Directories source: directories under the project root.
---
--- Delegates to `backend.list(root, "dirs")`, which enumerates with fd and
--- falls back to deriving parents from the file list when fd is unavailable.

local backend = require("loupe.backend")

return {
	name = "dirs",
	label = "Directories",
	icon = "",
	list = function(ctx, cb)
		backend.list(ctx, "dirs", function(cands)
			cb(cands, true)
		end)
	end,
}
