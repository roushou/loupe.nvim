--- Buffers source: open, listed buffers.
---
--- Candidates carry `bufnr`; the session opens them by switching the target
--- window's buffer, so an already-loaded (even modified) buffer is reused
--- instead of being re-read from disk.

return {
	name = "buffers",
	label = "Buffers",
	icon = "",
	backend = { "nvim" },
}
