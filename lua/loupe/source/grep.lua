--- Grep source: live content search across the project.
---
--- Dynamic (re-queries on each keystroke, debounced by the session). Candidates
--- carry `lnum`/`col` so the preview jumps to the match. rg is primary; git
--- grep is the fallback.

return {
	name = "grep",
	label = "Grep",
	icon = "",
	backend = { "rg", "git" },
	search = "grep",
}
