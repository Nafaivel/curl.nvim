local new_set = MiniTest.new_set

local api = require("curl.api")
local buffers = require("curl.buffers")

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ "-u", "scripts/minimal_init.lua" })
      -- Load tested plugin
      child.lua([[M = require('curl').setup({})]])
    end,
    after_case = function()
      api.close_curl_tab(true)
    end,
  },
})

T["api"] = new_set()
T["api"]["can curl something"] = function()
  local curl_command = "curl https://jsonplaceholder.typicode.com/todos/1"

  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, { curl_command })

  child.type_keys("gg")
  child.lua([[
    require("curl").execute_curl()
  ]])

  os.execute("sleep 1")
  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)

  local expected_output = [[{
  "userId": 1,
  "id": 1,
  "title": "delectus aut autem",
  "completed": false
}]]

  MiniTest.expect.equality(table.concat(output, "\n"), expected_output)
end

T["api"]["can open custom buffer"] = function()
  local custom_name = "sauron"
  api.open_scoped_collection(custom_name)

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find(custom_name), nil)

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find(custom_name), nil, "Buffer should be closed")
end

T["api"]["can open custom global buffer"] = function()
  local custom_name = "frodo"
  api.open_global_collection(custom_name)

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find(custom_name), nil, "Global custom buffer should be open")

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find(custom_name), nil, "Buffer should be closed")
end

T["api"]["can open global buffer"] = function()
  api.open_global_tab()

  local bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.no_equality(bufname:find("global"), nil)

  api.close_curl_tab()
  local new_bufname = vim.api.nvim_buf_get_name(0)
  MiniTest.expect.equality(new_bufname:find("global"), nil)
end

T["api"]["can export curl under cursor"] = function()
  child.lua([[
    require("curl").open_curl_tab()
    require("curl").set_curl_binary("/my/cool/curl")
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "curl http://127.0.0.1:9200/healthz" })

  child.lua([[
    require("curl").export_curl()
  ]])

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(table.concat(output, "\n"), "/my/cool/curl http://127.0.0.1:9200/healthz -sSL")
  local filetype = child.lua_get([[vim.bo.filetype]])
  MiniTest.expect.equality(filetype, "sh")
end

T["api"]["has CurlExport command"] = function()
  child.lua([[
    require("curl").open_curl_tab()
    require("curl").set_curl_binary("othercurl")
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "curl http://127.0.0.1:9200/healthz" })
  child.cmd("CurlExport")

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(table.concat(output, "\n"), "othercurl http://127.0.0.1:9200/healthz -sSL")
end

T["api"]["export resolves scoped variables in command text"] = function()
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---crematorium=http://127.0.0.1:9200",
    "---day=2026-02-14",
    "curl $crematorium/admin/sync/day -H \"Content-Type: application/json\" -u admin:admin -d",
    '{"day":"$day"}',
  })
  child.cmd("normal! 4G")
  child.lua([[
    require("curl").export_curl()
  ]])

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(
    table.concat(output, "\n"),
    "curl http://127.0.0.1:9200/admin/sync/day -H \"Content-Type: application/json\" -u admin:admin -d '{\"day\":\"2026-02-14\"}' -sSL"
  )
end

T["api"]["export resolves nested variables inside directives"] = function()
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---host=127.0.0.1",
    "---LIMITLESS_ACCOUNT_API_PORT=9200",
    "---accounts_url=http://$host:$LIMITLESS_ACCOUNT_API_PORT",
    "curl $accounts_url/api/v1/buyback/daily",
  })
  child.cmd("normal! 4G")
  child.lua([[
    require("curl").export_curl()
  ]])

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(table.concat(output, "\n"), "curl http://127.0.0.1:9200/api/v1/buyback/daily -sSL")
end

T["api"]["export resolves relative source file from open-time root"] = function()
  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, "p")
  local env_file = temp_dir .. "/.curl.env"
  local file = io.open(env_file, "w")
  file:write("CREMATORIUM=http://127.0.0.1:9200\n")
  file:close()

  child.cmd("cd " .. temp_dir)
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.cmd("cd /")
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---source=.curl.env",
    "curl $CREMATORIUM/healthz",
  })
  child.cmd("normal! 2G")
  child.lua([[
    require("curl").export_curl()
  ]])

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(table.concat(output, "\n"), "curl http://127.0.0.1:9200/healthz -sSL")
end

T["api"]["export aborts when source file is missing"] = function()
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---source=/tmp/curl.nvim-missing-source-file",
    "curl $CREMATORIUM/healthz",
  })
  child.cmd("normal! 2G")

  local windows_before = #child.api.nvim_tabpage_list_wins(0)
  child.lua([[
    require("curl").export_curl()
  ]])
  local windows_after = #child.api.nvim_tabpage_list_wins(0)
  MiniTest.expect.equality(windows_after, windows_before)
end

T["api"]["execute aborts when source file is missing"] = function()
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "---source=/tmp/curl.nvim-missing-source-file",
    "curl http://127.0.0.1:9200/healthz",
  })
  child.cmd("normal! 2G")

  local called = false
  local mock_pre = child.fn.jobstart
  child.fn.jobstart = function(_, _)
    called = true
    return 1
  end

  child.lua([[
    require("curl").execute_curl()
  ]])
  MiniTest.expect.equality(called, false)

  child.fn.jobstart = mock_pre
end

T["api"]["export supports directive with spaces after dashes"] = function()
  child.lua([[
    require("curl").open_curl_tab()
  ]])
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "--- crematorium = http://127.0.0.1:9200",
    "curl $crematorium/healthz",
  })
  child.cmd("normal! 2G")
  child.lua([[
    require("curl").export_curl()
  ]])

  child.cmd("wincmd l")
  local output = child.api.nvim_buf_get_lines(0, 0, -1, false)
  MiniTest.expect.equality(table.concat(output, "\n"), "curl http://127.0.0.1:9200/healthz -sSL")
end
return T
