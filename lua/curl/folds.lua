local M = {}

local config = require("curl.config")

---@param line string
---@param header_pattern string
---@return integer|nil
local function get_header_level(line, header_pattern)
	if line:match(header_pattern) == nil then
		return nil
	end

	local hashes = line:match("^%s*(#+)")
	if hashes == nil then
		return 1
	end

	return #hashes
end

---@param lnum integer
---@return string
M.foldexpr = function(lnum)
	local folds = config.get("folds") or {}
	if folds.mode ~= "markdown_headers" then
		return "="
	end

	local line = vim.fn.getline(lnum)
	local header_level = get_header_level(line, folds.header_pattern or "^%s*#+%s+")
	if header_level ~= nil then
		return ">" .. tostring(header_level)
	end

	return "="
end

M.setup_window = function()
	local folds = config.get("folds") or {}
	if not folds.enabled then
		return
	end

	vim.wo.foldmethod = "expr"
	vim.wo.foldexpr = "v:lua.require'curl.folds'.foldexpr(v:lnum)"
	vim.wo.foldenable = true

	if folds.start_open then
		vim.wo.foldlevel = 99
	end
end

return M
