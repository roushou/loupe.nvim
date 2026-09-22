--- Buffers source: open, listed buffers.
---
--- Candidates carry `bufnr`; the session opens them by switching the target
--- window's buffer, so an already-loaded (even modified) buffer is reused
--- instead of being re-read from disk.
---
--- The delete action closes the buffer and leaves the file on disk alone: the
--- entries stand for buffers, and someone tidying a buffer list is not asking
--- to lose files.

return {
	name = "buffers",
	label = "Buffers",
	icon = "󰈙",
	backend = { "nvim" },
	delete = "buffer",
}
