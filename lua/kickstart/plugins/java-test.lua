-- java-test.lua
-- Java Maven test runner with inline results display
--
-- Runs mvn test and parses surefire-reports to show ✓/✗ in gutter
-- and assertion messages + stacktrace as virtual text

local M = {}

local ns_id = vim.api.nvim_create_namespace 'java-test'
local sign_group = 'java-test-signs'

vim.fn.sign_define('JavaTestPassed', { text = '✓', texthl = 'DiagnosticOk' })
vim.fn.sign_define('JavaTestFailed', { text = '✗', texthl = 'DiagnosticError' })

vim.keymap.set('n', '<leader>jt', function() M.run_file() end, { desc = '[J]ava test: run file' })
vim.keymap.set('n', '<leader>jT', function() M.run_all() end, { desc = '[J]ava test: run all' })
vim.keymap.set('n', '<leader>jc', function() M.clear() end, { desc = '[J]ava test: clear results' })
vim.keymap.set('n', '<leader>jo', function() M.show_output() end, { desc = '[J]ava test: show output' })

local function find_pom(bufpath)
  local dir = vim.fn.fnamemodify(bufpath, ':p:h')
  while dir ~= '' and dir ~= '/' do
    local pom = dir .. '/pom.xml'
    if vim.fn.filereadable(pom) == 1 then
      return pom, dir
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return nil, nil
end

local function get_class_name(bufpath)
  local abs_path = vim.fn.fnamemodify(bufpath, ':p')
  local sep = package.config:sub(1, 1)
  local src_test_pattern = 'src' .. sep .. 'test' .. sep .. 'java' .. sep
  local found_at = abs_path:find(src_test_pattern, 1, true)
  if found_at then
    local after_src = found_at + #src_test_pattern - 1
    local relative = abs_path:sub(after_src)
    if relative:match('%.java$') then
      return relative:gsub('%.java$', ''):gsub(sep, '.'):gsub('^%.+', ''):gsub('%.+$', '')
    end
  end
  return vim.fn.fnamemodify(bufpath, ':t:r')
end

local function get_test_methods(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'java')
  if not ok or not parser then return {} end
  local tree = parser:parse()
  if not tree or #tree == 0 then return {} end
  local root = tree[1]:root()

  local methods = {}
  local query = vim.treesitter.query.parse('java', [[
        (method_declaration
          (modifiers
            (marker_annotation
              name: (identifier) @ann_name))
          name: (identifier) @method_name) @method
      ]])

  for _, captures, _ in query:iter_matches(root, bufnr) do
    local ann_node = captures[1][1]
    local meth_node = captures[2][1]
    local annotation_name = vim.treesitter.get_node_text(ann_node, bufnr)
    if annotation_name == 'Test' then
      local row = (meth_node:start()) + 1
      local name = vim.treesitter.get_node_text(meth_node, bufnr)
      table.insert(methods, { name = name, row = row })
    end
  end
  return methods
end

local function parse_surefire_report(report_path)
  if vim.fn.filereadable(report_path) ~= 1 then return {} end
  local content = vim.fn.readfile(report_path)
  local xml_str = table.concat(content, '\n')

  local results = {}

  local pos = 1
  while true do
    local start = xml_str:find('<testcase ', pos, true)
    if not start then break end

    local open_end = xml_str:find('>', start, true)
    if not open_end then break end

    local name = xml_str:match('name="([^"]*)"', start)
    local classname = xml_str:match('classname="([^"]*)"', start)
    local time = xml_str:match('time="([^"]*)"', start)

    local is_self_closing = xml_str:sub(open_end - 1, open_end - 1) == '/'
    local tc_xml
    if is_self_closing then
      tc_xml = xml_str:sub(start, open_end)
    else
      local close_start = xml_str:find('</testcase>', open_end, true)
      if not close_start then break end
      tc_xml = xml_str:sub(start, close_start + #'</testcase>' - 1)
    end

    if name then
      local status = 'passed'
      local message = ''
      local stacktrace = ''

      if tc_xml:match '<failure ' then
        status = 'failed'
        local fail_msg = tc_xml:match 'message="([^"]*)"'
        message = fail_msg or ''
        local fail_start = tc_xml:find('<failure ', 1, true)
        local fail_end = tc_xml:find('</failure>', 1, true)
        if fail_start and fail_end then
          local body_start = tc_xml:find('>', fail_start, true)
          local body = tc_xml:sub(body_start + 1, fail_end - 1)
          body = body:gsub('%s+', ' '):gsub('^%s', ''):gsub('%s$', '')
          local lines = {}
          for line in body:gmatch '[^\n]+' do
            line = line:gsub('^%s+', ''):gsub('%s+$', '')
            if line ~= '' then
              table.insert(lines, line)
              if #lines >= 5 then break end
            end
          end
          stacktrace = table.concat(lines, '\n')
        end
      elseif tc_xml:match '<error ' then
        status = 'failed'
        local err_msg = tc_xml:match 'message="([^"]*)"'
        message = err_msg or 'Error'
      elseif tc_xml:match '<skipped[^>]*>' then
        status = 'skipped'
        local skip_msg = tc_xml:match 'message="([^"]*)"'
        if skip_msg then message = skip_msg end
      end

      results[name] = {
        classname = classname,
        time = time,
        status = status,
        message = message,
        stacktrace = stacktrace,
      }
    end

    pos = open_end + 1
  end

  return results
end

local function clear_signs(bufnr)
  vim.fn.sign_unplace(sign_group, { buffer = bufnr })
end

local function clear_extmarks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

function M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
  clear_signs(bufnr)
  clear_extmarks(bufnr)
end

local current_output = ''

function M.run_file()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  if not bufpath:match '%.java$' then
    vim.notify('Not a Java file', vim.log.levels.WARN)
    return
  end

  M.clear()

  local _, pom_dir = find_pom(bufpath)
  if not pom_dir then
    vim.notify('No pom.xml found', vim.log.levels.ERROR)
    return
  end

  local class_name = get_class_name(bufpath)
  local test_methods = get_test_methods(bufnr)

  local cmd = { 'mvn', 'test', '-Dtest=' .. class_name }

  vim.notify('Running: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)

  vim.system(cmd, { text = true, cwd = pom_dir }, function(obj)
    if obj.signal and obj.signal ~= 0 then
      vim.schedule(function()
        vim.notify('Maven process killed', vim.log.levels.ERROR)
      end)
      return
    end

    current_output = obj.stdout .. '\n' .. obj.stderr

    vim.schedule(function()
      local report_path = pom_dir .. '/target/surefire-reports/TEST-' .. class_name .. '.xml'
      local results = parse_surefire_report(report_path)

      for _, method in ipairs(test_methods) do
        local result = results[method.name]
        local sign_name = 'JavaTestPassed'
        local virt_lines = {}

        if result then
          if result.status == 'failed' then
            sign_name = 'JavaTestFailed'
            if result.message ~= '' then
              table.insert(virt_lines, { { result.message, 'DiagnosticError' } })
            end
            if result.stacktrace ~= '' then
              for _, l in ipairs(vim.split(result.stacktrace, '\n')) do
                l = l:gsub('^%s+', ''):gsub('%s+$', '')
                if l ~= '' then
                  table.insert(virt_lines, { { l, 'Comment' } })
                end
                if #virt_lines >= 6 then break end
              end
            end
          elseif result.status == 'skipped' then
            table.insert(virt_lines, { { 'Skipped', 'Comment' } })
          end
        end

        vim.fn.sign_place(0, sign_group, sign_name, bufnr, {
          lnum = method.row,
          buffer = bufnr,
        })

        if #virt_lines > 0 then
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, method.row - 1, 0, {
            virt_lines = virt_lines,
            virt_lines_above = false,
          })
        end
      end

      local passed = 0
      local failed = 0
      for _, method in ipairs(test_methods) do
        local result = results[method.name]
        if result then
          if result.status == 'failed' then
            failed = failed + 1
          else
            passed = passed + 1
          end
        else
          passed = passed + 1
        end
      end

      if failed > 0 then
        vim.notify(string.format('Tests: %d passed, %d failed', passed, failed), vim.log.levels.ERROR)
      else
        vim.notify(string.format('Tests: %d passed', passed), vim.log.levels.INFO)
      end
    end)
  end)
end

function M.run_all()
  local bufpath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

  M.clear()

  local _, pom_dir = find_pom(bufpath)
  if not pom_dir then
    vim.notify('No pom.xml found', vim.log.levels.ERROR)
    return
  end

  local cmd = { 'mvn', 'test' }
  vim.notify('Running: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)

  vim.system(cmd, { text = true, cwd = pom_dir }, function(obj)
    if obj.signal and obj.signal ~= 0 then
      vim.schedule(function()
        vim.notify('Maven process killed', vim.log.levels.ERROR)
      end)
      return
    end

    current_output = obj.stdout .. '\n' .. obj.stderr

    vim.schedule(function()
      vim.notify('All tests finished', vim.log.levels.INFO)
    end)
  end)
end

function M.show_output()
  if current_output == '' then
    vim.notify('No test output yet', vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(current_output, '\n'))

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Maven Output ',
  }

  vim.api.nvim_open_win(buf, true, opts)
end

return M
