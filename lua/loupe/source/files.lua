--- Files source: every file under the project root.
---
--- Uses the filesystem enumeration facade (`backend.list`), which handles the
--- fd → rg → git preference cascade and directory derivation.

local backend = require("loupe.backend")

return {
	name = "files",
	label = "Files",
	icon = "",
	list = function(ctx, cb)
		backend.list(ctx, "files", function(cands)
			cb(cands, true)
		end)
	end,
}
