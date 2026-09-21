--- Workspace symbols source: workspace/symbol across all capable clients.
---
--- Dynamic, like grep: each query change fires a debounced request. The session
--- jumps to a candidate's location on choose (it carries `lnum`).

return {
	name = "symbols",
	label = "Workspace symbols",
	icon = "",
	backend = { "lsp" },
	search = "symbols",
}
