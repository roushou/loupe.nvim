--- Recent source: files ranked by loupe's own frecency store.
---
--- Reads the persisted frecency data (not an external tool), so it goes
--- through the builtin `internal` backend.

return {
	name = "recent",
	label = "Recent",
	icon = "",
	backend = { "internal" },
}
