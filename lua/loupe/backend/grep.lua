--- grep: live content search, re-run on each keystroke.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

return {
	search = {
		grep = {
			--- JSON output gives the full line plus exact byte ranges for each
			--- submatch, so the preview can highlight the occurrence. Results
			--- stream in as rg finds them and the process is stopped once
			--- `ctx.limit` candidates exist. Returns a cancel function.
			rg = function(query, ctx, cb)
				if query == "" then
					cb({}, true, true)
					return
				end
				return run.stream({ "rg", "--json", "--smart-case", "--", query }, ctx.root, function(lines)
					return parse.rgjson_lines(lines, ctx.root)
				end, cb, ctx.limit)
			end,

			--- Fallback (`git grep` uses basic regex and reports no columns).
			git = function(query, ctx, cb)
				if query == "" then
					cb({}, true)
					return
				end
				run.raw({ "git", "grep", "-n", "--no-color", "-e", query }, ctx.root, function(stdout)
					return parse.gitgrep(stdout, ctx.root)
				end, cb)
			end,
		},
	},
}
