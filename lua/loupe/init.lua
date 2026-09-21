--- Loupe: bottom-docked fuzzy finder with a full-viewport live preview.
---
--- Public API:
---   require("loupe").setup(opts)
---   require("loupe").open({ source = "files" })
---   require("loupe").close()
---   require("loupe").toggle()
---   require("loupe").is_active()
---
--- The session state machine lives in `loupe.session`; this module only wires
--- the public entry points to it.

local session = require("loupe.session")

local M = {}

--- Configure the picker.
function M.setup(opts)
	session.setup(opts)
end

--- Open the picker. `opts.source` selects the initial source by name.
function M.open(opts)
	session.open(opts)
end

--- Close the picker and return to the window it was opened from.
--- `opts.restore_cursor = false` keeps the origin window's cursor (used by
--- location jumps).
function M.close(opts)
	session.close(opts)
end

--- Toggle the picker.
function M.toggle(opts)
	session.toggle(opts)
end

--- Whether the picker is open.
function M.is_active()
	return session.is_active()
end

return M
