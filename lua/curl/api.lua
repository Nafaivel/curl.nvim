local M = {}

local parser = require("curl.parser")
local config = require("curl.config")
local cache = require("curl.cache")
local buffers = require("curl.buffers")
local output_parser = require("curl.output_parser")
local notify = require("curl.notifications")
local shell = require("curl.shell_utils")

---@param stdout_lines table
---@param stderr_output string
---@return table
local function include_stderr_output(stdout_lines, stderr_output)
	if stderr_output == "" then
		return stdout_lines
	end

	local stderr_lines = vim.split(stderr_output, "\n", { plain = true, trimempty = false })
	stderr_lines = vim.tbl_filter(function(line)
		return line ~= ""
	end, stderr_lines)
	vim.list_extend(stderr_lines, stdout_lines)
	return stderr_lines
end

---@param lines table
---@param drop_empty boolean
---@return table
local function normalize_lines(lines, drop_empty)
	local normalized = {}
	for _, line in ipairs(lines) do
		local cleaned = line:gsub("\r$", "")
		if not (drop_empty and cleaned == "") then
			table.insert(normalized, cleaned)
		end
	end
	return normalized
end

---@param lines table
---@return table
local function flatten_multiline_lines(lines)
	local flattened = {}
	for _, line in ipairs(lines) do
		local split = vim.split(line, "\n", { plain = true, trimempty = false })
		vim.list_extend(flattened, split)
	end
	return normalize_lines(flattened, false)
end

M.create_global_collection = function()
	vim.ui.input({ prompt = "Collection name: " }, function(input)
		if input == nil then
			return
		end
		M.open_global_collection(input)
	end)
end

M.create_scoped_collection = function()
	vim.ui.input({ prompt = "Collection name: " }, function(input)
		if input == nil then
			return
		end
		M.open_scoped_collection(input)
	end)
end

M.pick_global_collection = function()
	local global_collections = cache.get_collections(true)
	vim.ui.select(global_collections, { prompt = "Open a global collection:" }, function(selection)
		if selection == nil then
			return
		end

		M.open_global_collection(selection)
	end)
end

M.pick_scoped_collection = function()
	local scoped_collections = cache.get_collections(false)
	vim.ui.select(scoped_collections, { prompt = "Open a scoped collection:" }, function(selection)
		if selection == nil then
			return
		end

		M.open_scoped_collection(selection)
	end)
end

M.open_global_collection = function(collection_name)
	local filename = cache.load_custom_command_file(collection_name, true)
	buffers.setup_curl_tab_for_file(filename)
end

M.open_scoped_collection = function(collection_name)
	local filename = cache.load_custom_command_file(collection_name)
	buffers.setup_curl_tab_for_file(filename)
end

M.get_scoped_collections = function()
	return cache.get_scoped_collections(false)
end

M.get_global_collections = function()
	return cache.get_global_collections(true)
end

M.open_custom_tab = function(custom_buf_name)
	local filename = cache.load_custom_command_file(custom_buf_name, true)
	buffers.setup_curl_tab_for_file(filename)
	vim.deprecate(
		"open_custom_tab | CurlOpen custom {name} (see issue #20 in curl.nvim)",
		"open_global_collection | CurlOpen collection scoped",
		"soon",
		"curl.nvim"
	)
end

M.open_global_tab = function()
	local filename = cache.load_global_command_file()
	buffers.setup_curl_tab_for_file(filename)
end

M.open_curl_tab = function()
	local filename = cache.load_command_file()
	buffers.setup_curl_tab_for_file(filename)
end

---comment
---@param force boolean? if set to true, save warning is ignored
M.close_curl_tab = function(force)
	buffers.close_curl_tab(force)
end

M.execute_curl = function()
	local executed_from_win = vim.api.nvim_get_current_win()
	local cursor_pos, lines = buffers.get_command_buffer_and_pos()
	local curl_command = parser.parse_curl_command(cursor_pos, lines)

	local curl_alias = config.get("curl_binary")
	if curl_alias ~= nil then
		curl_command = curl_command:gsub("^curl", curl_alias)
	end

	if curl_command == "" then
		notify.error("No curl command found under the cursor")
		return
	end

	local output = ""
	local error = ""
	buffers.setup_buf_vars(lines, cursor_pos)

	local commands = shell.get_default_shell()
	if commands ~= nil and type(commands) == "table" then
		table.insert(commands, curl_command)
	else
		commands = curl_command
	end

	local start_time = vim.uv.hrtime()

	local _ = vim.fn.jobstart(commands, {
		on_exit = function(_, exit_code, _)
			if exit_code ~= 0 then
				notify.error("Curl failed")
				local error_lines = vim.split(error, "\n", { plain = true, trimempty = false })
				buffers.set_output_buffer_content(executed_from_win, normalize_lines(error_lines, true))
				return
			end

			local show_request_duration = config.get().show_request_duration_limit
			if show_request_duration then
				local elapsed = (vim.uv.hrtime() - start_time) / 1e9
				if elapsed > show_request_duration then
					print(string.format("Request took %.3f seconds", elapsed))
				end
			end

			local parsed_output = output_parser.parse_curl_output(output)
			if config.get("show_stderr") then
				parsed_output = include_stderr_output(parsed_output, error)
			end
			buffers.set_output_buffer_content(executed_from_win, flatten_multiline_lines(parsed_output))
		end,
		on_stdout = function(_, data, _)
			output = output .. vim.fn.join(data, "\n")
		end,
		on_stderr = function(_, data, _)
			error = error .. vim.fn.join(data, "\n")
		end,
	})
end

M.set_curl_binary = function(binary_name)
	config.set("curl_binary", binary_name)
end

return M
