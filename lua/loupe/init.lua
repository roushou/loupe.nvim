--- Loupe: bottom-docked fuzzy finder with a full-viewport live preview.
---
--- Public API:
---   require("loupe").setup(opts)
---   require("loupe").open({ source = "files" })
---   require("loupe").close()
---   require("loupe").park()
---   require("loupe").toggle()
---   require("loupe").is_active()
---   require("loupe").is_focused()
---
--- The session state machine lives in `loupe.session`; this module only wires
--- the public entry points to it.

local session = require("loupe.session")

local M = {}

--- Configure the picker.
function M.setup(opts)
	session.setup(opts)
end

--- Open the picker. `opts.source` selects the initial source by name. When a
--- picker already exists this focuses it (a parked drawer keeps its state).
function M.open(opts)
	session.open(opts)
end

--- Leave filter mode but keep the drawer, its list and its selection. The
--- preview withdraws and the cursor returns to the editor; `open()` / focusing
--- the drawer restores filter mode over the same state.
function M.park()
	session.park()
end

--- Close the picker and return to the window it was opened from.
--- `opts.restore_cursor = false` keeps the origin window's cursor (used by
--- location jumps).
function M.close(opts)
	session.close(opts)
end

--- Toggle the picker: park it when focused, focus or open it otherwise.
function M.toggle(opts)
	session.toggle(opts)
end

--- Whether a picker exists (focused or parked).
function M.is_active()
	return session.is_active()
end

--- Whether the picker currently owns the input focus.
function M.is_focused()
	return session.is_focused()
end

return M
