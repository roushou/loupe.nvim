--- LSP-backed operations: symbols, references and implementations from
--- attached language servers.
---
--- Symbols come in two scopes — one document and the whole workspace — and
--- answer the same question, so both live here. References and implementations
--- are cursor-position queries: the picker captures the cursor when it opens
--- and asks each capable client once; the session fuzzy-filters the returned
--- locations client-side, like any other static source.
---
--- Requests target `ctx.buf`/`ctx.cursor` explicitly because the picker itself
--- runs in a scratch buffer with no LSP attachment and away from the origin
--- window. Responses from every client are merged; a 5s safety net delivers
--- whatever arrived if a server never answers.

local parse = require("loupe.backend.parse")

--- Deliver `cb(out, true)` once `n` responses have arrived (or after 5s).
local function collector(n, cb)
	local out = {}
	local state = { done = 0 }
	local delivered = false
	local timer = vim.uv.new_timer()

	local function deliver()
		if delivered then
			return
		end
		delivered = true
		timer:stop()
		timer:close()
		vim.schedule(function()
			cb(out, true)
		end)
	end

	timer:start(5000, 0, vim.schedule_wrap(deliver))

	return out, function()
		state.done = state.done + 1
		if state.done >= n then
			deliver()
		end
	end
end

--- Symbol-kind name, glyph and highlight. The glyph comes from `mini.icons`
--- when it is installed (optional dependency, so pcall).
local function kind_of(kind)
	local name = kind and vim.lsp.protocol.SymbolKind[kind]
	if not name then
		return nil, nil, nil
	end
	local ok, mini = pcall(require, "mini.icons")
	if ok and type(mini.get) == "function" then
		local icon, hl = mini.get("lsp", name)
		return name, icon, hl
	end
	return name, nil, nil
end

--- Clients attached to `buf` that support `method`.
local function capable(buf, method)
	return vim.tbl_filter(function(c)
		return c:supports_method(method, buf)
	end, vim.lsp.get_clients({ bufnr = buf }))
end

--- Flatten SymbolInformation / hierarchical DocumentSymbol results.
local function flatten(symbols, out, path, root, depth)
	for _, sym in ipairs(symbols) do
		local range = sym.range or (sym.location and sym.location.range)
		if sym.name and range then
			local kind, icon, icon_hl = kind_of(sym.kind)
			local text = string.rep("  ", depth) .. sym.name
			out[#out + 1] = {
				rel = parse.relpath(root, path),
				abs = path,
				text = text,
				meta = kind,
				label = kind and (text .. "  " .. kind) or text,
				lnum = (range.start and range.start.line + 1) or 1,
				col = 0,
				icon = icon,
				icon_hl = icon_hl,
				dir = false,
			}
		end
		if sym.children then
			flatten(sym.children, out, path, root, depth + 1)
		end
	end
end

--- The buffer region a reference or implementation points at: a `Location`
--- carries `uri`/`range`, a `LocationLink` a `targetUri` and target range.
local function target(item)
	if item.targetUri then
		return item.targetUri, item.targetSelectionRange or item.targetRange
	end
	return item.uri, item.range
end

--- Collapse `Location`/`LocationLink` results into location candidates,
--- deduped by file and position. Files that are not open are read once, up to
--- the furthest line any of their references needs, rather than once per
--- reference. Returns the candidates ordered by file then line.
local function locations(results, root)
	local seen, paths, groups = {}, {}, {}
	for _, item in ipairs(results) do
		local uri, range = target(item)
		if uri and range and range.start then
			local path = vim.uri_to_fname(uri)
			local lnum = range.start.line + 1
			local col = range.start.character or 0
			local key = ("%s:%d:%d"):format(path, lnum, col)
			if not seen[key] then
				seen[key] = true
				local group = groups[path]
				if not group then
					group = {}
					groups[path] = group
					paths[#paths + 1] = path
				end
				group[#group + 1] = { lnum = lnum, col = col }
			end
		end
	end

	local out = {}
	for _, path in ipairs(paths) do
		local group = groups[path]
		local buf = vim.fn.bufnr(path)
		local loaded = buf ~= -1 and vim.api.nvim_buf_is_loaded(buf)
		local max = 0
		for _, loc in ipairs(group) do
			max = math.max(max, loc.lnum)
		end
		-- an open buffer is read directly; a closed file once, up to `max`
		local lines = {}
		if not loaded then
			local ok, read = pcall(vim.fn.readfile, path, "", max)
			if ok then
				lines = read
			end
		end
		local rel = parse.relpath(root, path)
		for _, loc in ipairs(group) do
			local text
			if loaded then
				text = vim.api.nvim_buf_get_lines(buf, loc.lnum - 1, loc.lnum, false)[1] or ""
			else
				text = lines[loc.lnum] or ""
			end
			text = vim.trim(text)
			local where = parse.location(rel, loc.lnum)
			out[#out + 1] = {
				rel = rel,
				abs = path,
				text = text,
				meta = where,
				label = text .. "  " .. where,
				lnum = loc.lnum,
				col = loc.col,
				dir = false,
			}
		end
	end

	table.sort(out, function(a, b)
		if a.rel ~= b.rel then
			return a.rel < b.rel
		end
		if a.lnum ~= b.lnum then
			return a.lnum < b.lnum
		end
		return a.col < b.col
	end)
	return out
end

--- The cursor captured when the picker opened, as an LSP `Position`.
local function position(ctx)
	local cursor = ctx.cursor or { 1, 0 }
	return { line = math.max(0, (cursor[1] or 1) - 1), character = math.max(0, cursor[2] or 0) }
end

--- A cursor-position location query. `params(ctx)` builds the request, so the
--- per-client plumbing stays in one place.
local function query(method, params)
	return function(ctx, cb)
		local buf = ctx.buf
		if not (buf and vim.api.nvim_buf_is_valid(buf)) then
			cb({}, true)
			return
		end
		local clients = capable(buf, method)
		if #clients == 0 then
			cb({}, true)
			return
		end
		local out, finish = collector(#clients, function(raw, ok)
			cb(locations(raw, ctx.root), ok)
		end)
		local req = params(ctx)
		for _, c in ipairs(clients) do
			c:request(method, req, function(err, result)
				if not err and type(result) == "table" then
					-- `implementation` may answer with a single Location
					if result.uri or result.targetUri then
						result = { result }
					end
					vim.list_extend(out, result)
				end
				finish()
			end, buf)
		end
	end
end

return {
	list = {
		--- Symbols in `ctx.buf`, flattened and fuzzy-filtered by the session.
		doc_symbols = {
			lsp = function(ctx, cb)
				local buf = ctx.buf
				if not (buf and vim.api.nvim_buf_is_valid(buf)) then
					cb({}, true)
					return
				end
				local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentSymbol" })
				if #clients == 0 then
					cb({}, true)
					return
				end
				local path = vim.api.nvim_buf_get_name(buf)
				local out, finish = collector(#clients, cb)
				local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
				for _, c in ipairs(clients) do
					c:request("textDocument/documentSymbol", params, function(err, result)
						if not err and type(result) == "table" then
							flatten(result, out, path, ctx.root, 0)
						end
						finish()
					end, buf)
				end
			end,
		},

		--- References to the symbol at `ctx.cursor`, across every capable client.
		references = {
			lsp = query("textDocument/references", function(ctx)
				return {
					textDocument = vim.lsp.util.make_text_document_params(ctx.buf),
					position = position(ctx),
					context = { includeDeclaration = true },
				}
			end),
		},

		--- Implementations of the symbol at `ctx.cursor`.
		implementations = {
			lsp = query("textDocument/implementation", function(ctx)
				return {
					textDocument = vim.lsp.util.make_text_document_params(ctx.buf),
					position = position(ctx),
				}
			end),
		},
	},

	search = {
		--- Workspace symbols for `query` (`ctx.root` scopes which clients answer).
		symbols = {
			lsp = function(query, ctx, cb)
				local buf = ctx.buf
				if not (buf and vim.api.nvim_buf_is_valid(buf)) then
					cb({}, true)
					return
				end
				local capable_clients = capable(buf, "workspace/symbol")
				if #capable_clients == 0 then
					cb({}, true)
					return
				end

				local out, finish = collector(#capable_clients, cb)
				vim.lsp.buf_request(buf, "workspace/symbol", { query = query }, function(err, result)
					if not err and type(result) == "table" then
						for _, sym in ipairs(result) do
							local loc = sym.location or sym
							if loc and loc.uri and loc.range then
								local path = vim.uri_to_fname(loc.uri)
								local rel = parse.relpath(ctx.root, path)
								local name = sym.name or "?"
								if sym.containerName and sym.containerName ~= "" then
									name = name .. " (" .. sym.containerName .. ")"
								end
								local _, icon, icon_hl = kind_of(sym.kind)
								local lnum = (loc.range.start and loc.range.start.line + 1) or 1
								local where = parse.location(rel, lnum)
								out[#out + 1] = {
									rel = rel,
									abs = path,
									text = name,
									meta = where,
									label = name .. "  " .. where,
									lnum = lnum,
									col = 0,
									icon = icon,
									icon_hl = icon_hl,
									dir = false,
								}
							end
						end
					end
					finish()
				end)
			end,
		},
	},
}
