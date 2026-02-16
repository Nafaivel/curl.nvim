local function fail(msg, code)
	io.stderr:write("curl-nvim skill: " .. msg .. "\n")
	os.exit(code or 1)
end

local function parse_bool(value)
	return value == "1" or value == "true" or value == "yes"
end

local function lookup_variable(name)
	local value = vim.env[name]
	if value == nil or value == vim.NIL then
		return ""
	end
	return value
end

local function expand_shell_variables(text)
	local out = {}
	local i = 1
	local n = #text
	local in_single_quote = false
	local in_double_quote = false

	while i <= n do
		local c = text:sub(i, i)

		if c == "'" and not in_double_quote then
			in_single_quote = not in_single_quote
			table.insert(out, c)
			i = i + 1
		elseif c == '"' and not in_single_quote then
			in_double_quote = not in_double_quote
			table.insert(out, c)
			i = i + 1
		elseif c == "\\" and not in_single_quote then
			table.insert(out, c)
			if i < n then
				table.insert(out, text:sub(i + 1, i + 1))
				i = i + 2
			else
				i = i + 1
			end
		elseif c == "$" and not in_single_quote then
			local next_char = i < n and text:sub(i + 1, i + 1) or ""

			if next_char == "{" then
				local start_idx = i + 2
				local end_idx = text:find("}", start_idx, true)
				if end_idx ~= nil then
					local var_name = text:sub(start_idx, end_idx - 1)
					if var_name:match("^[%w_]+$") ~= nil then
						table.insert(out, lookup_variable(var_name))
						i = end_idx + 1
					else
						table.insert(out, text:sub(i, end_idx))
						i = end_idx + 1
					end
				else
					table.insert(out, c)
					i = i + 1
				end
			else
				local _, end_idx = text:find("^[%w_]+", i + 1)
				if end_idx ~= nil then
					local var_name = text:sub(i + 1, end_idx)
					table.insert(out, lookup_variable(var_name))
					i = end_idx + 1
				else
					table.insert(out, c)
					i = i + 1
				end
			end
		else
			table.insert(out, c)
			i = i + 1
		end
	end

	return table.concat(out)
end

local function normalize_output(text)
	local lines = vim.split(text or "", "\n", { plain = true, trimempty = false })
	for i, line in ipairs(lines) do
		lines[i] = line:gsub("\r$", "")
	end
	return table.concat(lines, "\n")
end

local plugin_dir = arg[1]
local mode = arg[2] or "exec"
local file_path = arg[3]
local cursor_line = tonumber(arg[4] or "1")
local root_anchor = arg[5] or ""
local show_stderr = parse_bool(arg[6] or "0")
local print_command = parse_bool(arg[7] or "0")
local curl_binary = arg[8] or ""

if plugin_dir == nil or plugin_dir == "" then
	fail("missing plugin directory argument", 2)
end
if file_path == nil or file_path == "" then
	fail("missing file path argument", 2)
end
if cursor_line == nil or cursor_line < 1 then
	fail("cursor line must be >= 1", 2)
end
if mode ~= "export" and mode ~= "exec" then
	fail("mode must be 'export' or 'exec'", 2)
end

vim.cmd("set runtimepath+=" .. vim.fn.fnameescape(plugin_dir))

local ok_parser, parser = pcall(require, "curl.parser")
if not ok_parser then
	fail("failed to load curl.parser from plugin dir: " .. plugin_dir, 3)
end

local ok_buffers, buffers = pcall(require, "curl.buffers")
if not ok_buffers then
	fail("failed to load curl.buffers from plugin dir: " .. plugin_dir, 3)
end

local ok_shell, shell = pcall(require, "curl.shell_utils")
if not ok_shell then
	fail("failed to load curl.shell_utils from plugin dir: " .. plugin_dir, 3)
end

vim.cmd("silent edit " .. vim.fn.fnameescape(file_path))
local bufnr = vim.api.nvim_get_current_buf()

if root_anchor ~= "" then
	vim.api.nvim_buf_set_var(bufnr, "curl_root_anchor", root_anchor)
end

local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
if #lines == 0 then
	fail("file has no lines: " .. file_path, 4)
end

if cursor_line > #lines then
	cursor_line = #lines
end

local setup_ok, setup_err = buffers.setup_buf_vars(lines, cursor_line, bufnr)
if not setup_ok then
	fail(setup_err or "failed to setup buffer vars", 5)
end

local curl_command = parser.parse_curl_command(cursor_line, lines)
if curl_command == "" then
	fail("no curl command found under line " .. tostring(cursor_line), 6)
end

if curl_binary ~= "" then
	curl_command = curl_command:gsub("^curl", curl_binary)
end

local expanded_command = expand_shell_variables(curl_command)

if mode == "export" then
	io.write(expanded_command)
	return
end

if print_command then
	io.stderr:write("$ " .. expanded_command .. "\n")
end

local commands = shell.get_default_shell()
local invocation
if type(commands) == "table" then
	invocation = vim.deepcopy(commands)
	table.insert(invocation, curl_command)
elseif type(commands) == "string" and commands ~= "" then
	invocation = { commands, "-c", curl_command }
else
	invocation = { "sh", "-c", curl_command }
end

local result = vim.system(invocation, { text = true }):wait()
local stdout = normalize_output(result.stdout or "")
local stderr = normalize_output(result.stderr or "")

if result.code ~= 0 then
	if stderr ~= "" then
		io.stderr:write(stderr)
	end
	if stdout ~= "" then
		io.write(stdout)
	end
	os.exit(result.code)
end

if show_stderr and stderr ~= "" then
	io.write(stderr)
end

if stdout ~= "" then
	io.write(stdout)
end
