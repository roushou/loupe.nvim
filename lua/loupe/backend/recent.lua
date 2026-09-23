--- recent: files ranked by loupe's own frecency store.

local frecency = require("loupe.frecency")

return {
	list = {
		recent = {
			internal = function(ctx, cb)
				cb(frecency.recent(ctx.root), true)
			end,
		},
	},
}
