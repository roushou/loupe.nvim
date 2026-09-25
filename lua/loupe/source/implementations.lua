--- Implementations source: implementations of the symbol at the cursor,
--- across attached language servers.
---
--- Static: the picker captures the cursor when it opens, asks each capable
--- client once (`textDocument/implementation`) and the session fuzzy-filters
--- the returned locations client-side. Candidates carry `lnum`/`col`, so
--- choosing jumps to the implementation.

return {
	name = "implementations",
	label = "Implementations",
	tab = "Impl",
	icon = "󰡱",
	backend = { "lsp" },
}
