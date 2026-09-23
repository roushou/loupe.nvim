--- The tools a backend operation can be served by.
---
--- A tool is an identity, not an implementation: what it is called, how to
--- tell whether it is usable here, and nothing else. The operations live in
--- the capability modules next to this one, each gathering every tool that
--- can answer one use case.
---
--- No `exe` means always available; an `available` hook decides for tools
--- whose presence is dynamic rather than a binary on PATH.

return {
	fd = { exe = "fd" },
	rg = { exe = "rg" },
	git = { exe = "git" },

	--- Neovim's own state: buffers, diagnostics.
	nvim = {},

	--- Loupe's own data: the frecency store.
	internal = {},

	--- Attached language servers, so availability is dynamic.
	lsp = {
		available = function()
			return #vim.lsp.get_clients({ method = "workspace/symbol" }) > 0
				or #vim.lsp.get_clients({ method = "textDocument/documentSymbol" }) > 0
		end,
	},
}
