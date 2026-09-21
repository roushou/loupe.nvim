--- Document symbols source: symbols in the buffer the picker was opened from.
---
--- Static: the LSP returns the whole symbol tree at once and the session
--- fuzzy-filters it client-side. Candidates carry `lnum`, so the session jumps
--- to the symbol on choose.

return {
	name = "doc_symbols",
	label = "Document symbols",
	icon = "",
	backend = { "lsp" },
}
