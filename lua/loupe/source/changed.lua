--- Changed source: files with pending git changes (staged, unstaged, untracked).
---
--- Backed by `git status --porcelain -z`; staged and unstaged changes are
--- merged into a single list for now.

return {
	name = "changed",
	label = "Changed",
	icon = "",
	backend = { "git" },
}
