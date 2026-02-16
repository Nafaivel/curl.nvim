local M = {}

OUTPUT_BUF_ID = -1
COMMAND_BUF_ID = -1
TAB_ID = "curl.nvim.tab"
RESULT_BUF_NAME = "Curl output"

local buf_is_open = function(buffer_name)
	local bufnr = vim.fn.bufnr(buffer_name, false)

	return bufnr ~= -1 and vim.fn.bufloaded(bufnr) == 1
end

local close_curl_buffer = function(buffer, force)
	if buffer == -1 or vim.fn.bufexists(buffer) ~= 1 then
		return
	end

	vim.api.nvim_buf_delete(buffer, { force = force })
end

local function find_curl_tab_windid()
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local success, tab_id = pcall(function() ---@type any,integer
			return vim.api.nvim_tabpage_get_var(tab, "id")
		end)

		if success and tab_id == TAB_ID then
			vim.api.nvim_set_current_tabpage(tab)
			local win_id = vim.api.nvim_tabpage_get_win(tab)
			vim.api.nvim_set_current_win(win_id)
			return win_id
		end
	end
end

local function open_or_goto_curl_tab()
	local config = require("curl.config")
	local open_with = config.get("open_with")

	if open_with == "split" then
		vim.cmd("botright split | wincmd j")
	elseif open_with == "vsplit" then
		vim.cmd("botright vsplit | wincmd l")
	elseif open_with == "buffer" then
		return
	else
		local tab_win_id = find_curl_tab_windid()
		if tab_win_id ~= nil then
			return tab_win_id
		end

		vim.cmd("tabnew")
		vim.api.nvim_tabpage_set_var(0, "id", TAB_ID)
	end
end

local open_command_buffer = function(command_file)
	vim.cmd.edit(command_file)
	local new_bufnr = vim.fn.bufnr(command_file, false)
	local new_win = vim.api.nvim_get_current_win()

	return new_bufnr, new_win
end

---@param line string
---@return string
local function trim(line)
	return line:match("^%s*(.-)%s*$")
end

---@param name string
---@return string
local function lookup_env(name)
	local value = vim.env[name]
	if value == nil or value == vim.NIL then
		return ""
	end

	return value
end

---@param value string
---@return string
local function expand_env_variables(value)
	local expanded = value
	for _ = 1, 10 do
		local next_value = expanded:gsub("%${([%w_]+)}", lookup_env)
		next_value = next_value:gsub("%$([%w_]+)", lookup_env)
		if next_value == expanded then
			break
		end
		expanded = next_value
	end

	return expanded
end

---@param path string
---@return string
local function expand_path_variables(path)
	local expanded = expand_env_variables(path)

	local home = lookup_env("HOME")
	if expanded == "~" then
		return home
	end

	if expanded:sub(1, 2) == "~/" then
		return home .. expanded:sub(2)
	end

	return expanded
end

---@param bufnr integer
---@return string
local function resolve_base_dir(bufnr)
	local ok, root_anchor = pcall(vim.api.nvim_buf_get_var, bufnr, "curl_root_anchor")
	if ok and type(root_anchor) == "string" and root_anchor ~= "" then
		return root_anchor
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if buf_name ~= "" then
		return vim.fn.fnamemodify(buf_name, ":p:h")
	end

	return vim.fn.getcwd()
end

---@param raw_path string
---@param bufnr integer
---@return string
local function resolve_source_path(raw_path, bufnr)
	local expanded = expand_path_variables(trim(raw_path))
	if expanded == "" then
		return ""
	end

	if expanded:sub(1, 1) ~= "/" then
		expanded = resolve_base_dir(bufnr) .. "/" .. expanded
	end

	return vim.fn.fnamemodify(expanded, ":p")
end

---@param filepath string
---@return boolean, string|nil
local function load_env_file(filepath)
	local file = io.open(filepath, "r")
	if file == nil then
		return false, "Failed to source env file: " .. filepath
	end

	for line in file:lines() do
		local stripped = trim(line)
		if stripped ~= "" and stripped:sub(1, 1) ~= "#" then
			stripped = stripped:gsub("^export%s+", "")
			local key, value = stripped:match("^([%a_][%w_]*)=(.*)$")
			if key and value then
				local unwrapped = trim(value)
				local first_char = unwrapped:sub(1, 1)
				local last_char = unwrapped:sub(-1)
				if (#unwrapped >= 2 and first_char == "'" and last_char == "'")
					or (#unwrapped >= 2 and first_char == '"' and last_char == '"')
				then
					unwrapped = unwrapped:sub(2, -2)
				end
				vim.env[key] = unwrapped
			end
		end
	end

	file:close()
	return true, nil
end

local result_open_in_current_tab = function(res_buf_name)
	local buffer = vim.fn.bufnr(res_buf_name, false)

	if not buf_is_open(res_buf_name) then
		return
	end

	local open_windows = vim.api.nvim_tabpage_list_wins(0)
	local windows_containing_buffer = vim.fn.win_findbuf(buffer)

	local set = {}
	for _, win_id in pairs(open_windows) do
		set[win_id] = true ---@type boolean
	end

	for _, win_id in pairs(windows_containing_buffer) do
		if set[win_id] then
			return true
		end
	end

	return false
end

local open_result_buffer = function(called_from_win_id)
	local open_resbuf_name = RESULT_BUF_NAME .. "_" .. called_from_win_id ---@type string

	vim.api.nvim_set_current_win(called_from_win_id)
	if result_open_in_current_tab(open_resbuf_name) then
		return
	end

	local config = require("curl.config")
	local output_split_direction = config.get("output_split_direction")
	local split_cmd = output_split_direction == "horizontal" and "belowright sb" or "vert belowright sb"

	if buf_is_open(open_resbuf_name) then
		local bufnr = vim.fn.bufnr(open_resbuf_name, false)
		vim.cmd(split_cmd .. bufnr .. " | wincmd p")
		OUTPUT_BUF_ID = bufnr
		return
	end

	local new_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(new_bufnr, open_resbuf_name)
	vim.api.nvim_set_option_value("filetype", "json", { buf = new_bufnr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = new_bufnr })
	vim.cmd(split_cmd .. new_bufnr .. " | wincmd p")
	OUTPUT_BUF_ID = new_bufnr
end

---sets envs from parsed lines output
---in style like `---var=val` or `---source=.env`
---@param lines [string]
---@param upper_bound integer | nil
---@param bufnr integer|nil
---@return boolean, string|nil
M.setup_buf_vars = function(lines, upper_bound, bufnr)
	upper_bound = upper_bound or #lines
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	for idx = 1, upper_bound do
		local line = lines[idx]
		if not line then
			break
		end

		local source_path = line:match("^%s*%-%-%-%s*source%s*=%s*(.+)$")
		if source_path then
			local resolved_path = resolve_source_path(source_path, bufnr)
			local ok, err = load_env_file(resolved_path)
			if not ok then
				return false, err
			end
			goto continue
		end

		local k, v = line:match("^%s*%-%-%-%s*([^=]+)=(.*)")
		if k and v then
			k = trim(k)
			v = trim(v)
		end
		if k and v and k ~= "source" then
			vim.env[k] = expand_env_variables(v)
		end

		::continue::
	end

	return true, nil
end

M.setup_curl_tab_for_file = function(filename)
	open_or_goto_curl_tab()

	local new_buf_id, current_win = open_command_buffer(filename)
	vim.api.nvim_buf_set_var(new_buf_id, "curl_root_anchor", vim.fn.getcwd())
	COMMAND_BUF_ID = new_buf_id
end

M.close_curl_tab = function(force)
	close_curl_buffer(COMMAND_BUF_ID, force)
	close_curl_buffer(OUTPUT_BUF_ID, force)
	COMMAND_BUF_ID, OUTPUT_BUF_ID = -1, -1, -1
end

M.get_command_buffer_and_pos = function()
	local left_buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(left_buf, 0, -1, false)

	local cursor_pos = vim.api.nvim_win_get_cursor(0)[1]

	return cursor_pos, lines, left_buf
end

---@param executed_from_win integer
---@param content table
---@param filetype string|nil
M.set_output_buffer_content = function(executed_from_win, content, filetype)
	open_result_buffer(executed_from_win)
	vim.api.nvim_set_option_value("filetype", filetype or "json", { buf = OUTPUT_BUF_ID })
	vim.api.nvim_buf_set_lines(OUTPUT_BUF_ID, 0, -1, false, content)
end

return M
