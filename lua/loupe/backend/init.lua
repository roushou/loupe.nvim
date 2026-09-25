--- Backend registry and enumeration facade.
---
--- Operations are grouped by use case, one module per capability (`files`,
--- `grep`, `symbols`, ...), each gathering every tool that can answer it.
--- `loupe.backend.tools` holds the tool identities. This module assembles the
--- two into the registry the resolver reads: `registry[tool][kind][op]`.
---
--- `config.backends` holds per-capability preference lists — the same keys
--- the capability modules are named for — and the first available tool wins,
--- with a failing run cascading to the next. Fuzzy ranking lives in
--- `loupe.matcher`; this module only produces candidates.

local config = require("loupe.config")
local matcher = require("loupe.matcher")
local parse = require("loupe.backend.parse")

--- One module per use case. Adding a capability means adding it here and
--- writing the module; nothing else in the registry needs to know.
local CAPABILITIES = {
	"files",
	"dirs",
	"changed",
	"grep",
	"buffers",
	"diagnostics",
	"lsp",
	"recent",
}

local M = { registry = {} }

for id, tool in pairs(require("loupe.backend.tools")) do
	M.registry[id] = vim.tbl_extend("error", { list = {}, search = {} }, tool)
end

for _, capability in ipairs(CAPABILITIES) do
	for kind, ops in pairs(require("loupe.backend." .. capability)) do
		for op, tools in pairs(ops) do
			for id, fn in pairs(tools) do
				local tool = M.registry[id]
				assert(tool, ("%s.%s names no tool: %s"):format(capability, op, id))
				tool[kind][op] = fn
			end
		end
	end
end

--- A backend is available when its `available()` hook passes, or it declares
--- no exe, or its exe is on PATH.
local function available(b)
	if b == nil then
		return false
	end
	if b.available then
		return b.available()
	end
	return b.exe == nil or vim.fn.executable(b.exe) == 1
end

--- First available backend exposing `kind[op]` (`kind` is "list" or "search").
--- @return string|nil id, function|nil fn
function M.resolve(op, prefs, kind)
	kind = kind or "list"
	prefs = prefs or (config.get().backends and config.get().backends[op]) or {}
	for _, id in ipairs(prefs) do
		local b = M.registry[id]
		if available(b) and b[kind] and b[kind][op] then
			return id, b[kind][op]
		end
	end
	return nil, nil
end

--- Try each preferred backend in order until one succeeds.
--- `on_done(cands, ok)`; `ok = false` means every backend failed.
function M.resolve_list(op, ctx, prefs, on_done)
	prefs = prefs or (config.get().backends and config.get().backends[op]) or {}
	local function attempt(i)
		local id = prefs[i]
		if not id then
			on_done({}, false)
			return
		end
		local b = M.registry[id]
		if not (available(b) and b.list and b.list[op]) then
			attempt(i + 1)
			return
		end
		b.list[op](ctx, function(cands, ok)
			if ok then
				on_done(cands, true)
			else
				attempt(i + 1)
			end
		end)
	end
	attempt(1)
end

--- Enumerate `ctx.root` asynchronously; `on_done` receives the candidate list.
--- `mode` is "files" or "dirs"; when no directory enumerator is available (or
--- it finds nothing) directories are derived from the file list.
function M.list(ctx, mode, on_done)
	if matcher.fff_module() then
		on_done({})
		return
	end
	if mode == "dirs" then
		M.resolve_list("dirs", ctx, nil, function(cands, ok)
			if ok and #cands > 0 then
				on_done(cands)
			else
				M.resolve_list("files", ctx, nil, function(files)
					on_done(parse.derive_dirs(files, ctx.root))
				end)
			end
		end)
		return
	end
	M.resolve_list("files", ctx, nil, on_done)
end

--- Rank `cands` against `query` (delegates to `loupe.matcher`).
function M.match(query, cands, max, ctx)
	return matcher.match(query, cands, max, ctx)
end

return M
