--- File-type glyphs for the result list.
---
--- Self-contained: a small filetype -> glyph map with sensible fallbacks, so
--- the plugin needs no icon library. Glyphs are Nerd Font private-use code
--- points; the highlight group is a standard group so colours follow the theme.

local M = {}

local FILE = { glyph = "󰈔", hl = "Comment" }
local DIR = { glyph = "󰉋", hl = "Directory" }

-- filetype -> { glyph, hl }
local BY_FILETYPE = {
	lua = { glyph = "󰢱", hl = "Function" },
	rust = { glyph = "󱘗", hl = "Constant" },
	go = { glyph = "󰟓", hl = "Function" },
	python = { glyph = "󰌠", hl = "Type" },
	javascript = { glyph = "󰌞", hl = "Type" },
	javascriptreact = { glyph = "", hl = "Function" },
	typescript = { glyph = "󰛦", hl = "Function" },
	typescriptreact = { glyph = "", hl = "Directory" },
	markdown = { glyph = "󰍔", hl = "Comment" },
	json = { glyph = "󰘦", hl = "Type" },
	jsonc = { glyph = "󰘦", hl = "Type" },
	toml = { glyph = "", hl = "Constant" },
	yaml = { glyph = "", hl = "Keyword" },
	html = { glyph = "󰌝", hl = "Constant" },
	css = { glyph = "󰌜", hl = "Function" },
	scss = { glyph = "󰟬", hl = "Statement" },
	bash = { glyph = "", hl = "String" },
	sh = { glyph = "", hl = "Comment" },
	zsh = { glyph = "", hl = "String" },
	ruby = { glyph = "󰴭", hl = "Statement" },
	java = { glyph = "󰬷", hl = "Constant" },
	kotlin = { glyph = "󱈙", hl = "Directory" },
	c = { glyph = "󰙱", hl = "Directory" },
	cpp = { glyph = "󰙲", hl = "Function" },
	h = { glyph = "󰫵", hl = "Function" },
	zig = { glyph = "", hl = "Constant" },
	nix = { glyph = "󱄅", hl = "Function" },
	vim = { glyph = "", hl = "String" },
	sql = { glyph = "󰆼", hl = "Comment" },
	xml = { glyph = "󰗀", hl = "Constant" },
	dockerfile = { glyph = "󰡨", hl = "Directory" },
	make = { glyph = "󱁤", hl = "Comment" },
	gitcommit = { glyph = "󰊢", hl = "String" },
	gitconfig = { glyph = "󰒓", hl = "Constant" },
	gitignore = { glyph = "󰊢", hl = "Keyword" },
}

-- Exact filename overrides (filetype detection misses these).
local BY_NAME = {
	Makefile = BY_FILETYPE.make,
	Dockerfile = BY_FILETYPE.dockerfile,
	[".gitignore"] = BY_FILETYPE.gitignore,
}

--- Return (glyph, hl_group) for a candidate { rel, dir }.
function M.get(cand)
	if cand.dir then
		return DIR.glyph, DIR.hl
	end
	local special = BY_NAME[vim.fn.fnamemodify(cand.rel, ":t")]
	if special then
		return special.glyph, special.hl
	end
	local data = BY_FILETYPE[vim.filetype.match({ filename = cand.rel })]
	if data then
		return data.glyph, data.hl
	end
	return FILE.glyph, FILE.hl
end

--- Resolve a candidate's glyph, preferring an explicit `cand.icon`.
--- Symbol and diagnostic sources set their own kind/severity icon; everything
--- else falls back to filetype detection.
function M.for_candidate(cand)
	if cand.icon then
		return cand.icon, cand.icon_hl
	end
	return M.get(cand)
end

return M
