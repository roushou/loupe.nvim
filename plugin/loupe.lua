-- Auto-loaded command stub. Kept tiny so `:Loupe` exists without requiring the
-- plugin eagerly; the module is loaded on first use.

if vim.g.loaded_loupe then
	return
end
vim.g.loaded_loupe = true

vim.api.nvim_create_user_command("Loupe", function(args)
	local opts = args.args ~= "" and { source = args.args } or nil
	require("loupe").open(opts)
end, {
	nargs = "?",
	desc = "Open the Loupe picker (optionally on a source)",
	complete = function()
		local names = vim.tbl_keys(require("loupe.source").registry)
		table.sort(names)
		return names
	end,
})
