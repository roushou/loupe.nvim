--- Diagnostics source: every diagnostic across open documents.
---
--- Static; candidates carry `lnum`/`col`, so the session jumps to the
--- diagnostic on choose.

return {
	name = "diagnostics",
	label = "Diagnostics",
	icon = "",
	backend = { "nvim" },
}
