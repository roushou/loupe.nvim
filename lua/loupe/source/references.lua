--- References source: every reference to the symbol at the cursor, across
--- attached language servers.
---
--- Static: the picker captures the cursor when it opens, asks each capable
--- client once (`textDocument/references`) and the session fuzzy-filters the
--- returned locations client-side. Candidates carry `lnum`/`col`, so choosing
--- jumps to the reference.

return {
	name = "references",
	label = "References",
	tab = "Refs",
	icon = "󰌷",
	backend = { "lsp" },
}
