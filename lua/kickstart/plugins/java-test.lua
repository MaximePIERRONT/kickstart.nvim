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
  local dir = vim.fn.fnamemodify(bufpath, ':p:h')
  while dir ~= '' and dir ~= '/' do
    local src_test = dir .. '/src/test/java'
    if vim.fn.isdirectory(src_test) == 1 then
      local prefix = src_test .. '/'
      if bufpath:sub(1, #prefix) == prefix then
        return bufpath:sub(#prefix + 1):gsub('%.java$', ''):gsub('/', '.')
      end
      break
    end
    dir = vim.fn.fnamemodify(dir, ':h')
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
          [
            (marker_annotation name: (identifier) @annotation_name)
            (annotation name: (identifier) @annotation_name)
          ]
          name: (identifier) @method_name
        ) @method
      ]])

  for _, captures, _ in query:iter_matches(root, bufnr) do
    local annotation_name = vim.treesitter.query.get_node_text(captures[1], bufnr)
    if annotation_name ~= 'Test' then
    else
      local method_name_node = captures[2]
      local row = (method_name_node:start()) + 1
      local name = vim.treesitter.query.get_node_text(method_name_node, bufnr)
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

  -- Self-closing testcase tags: <testcase name="..." classname="..." time="..."/>
  for testcase_xml in xml_str:gmatch '<testcase [^/]*/?>' do
    local name = testcase_xml:match 'name="([^"]*)"'
    local classname = testcase_xml:match 'classname="([^"]*)"'
    local time = testcase_xml:match 'time="([^"]*)"'
    local skipped_xml = testcase_xml:match '<skipped[^/]*/?>'

    if name then
      local status = skipped_xml and 'skipped' or 'passed'
      results[name] = {
        classname = classname,
        time = time,
        status = status,
        message = '',
        stacktrace = '',
      }
    end
  end

  -- Non-self-closing testcase tags: <testcase ...>...</testcase>
  -- These may contain <failure>, <error>, or <skipped>
  for full_testcase in xml_str:gmatch '<testcase [^>]->.-</testcase>' do
    local name = full_testcase:match 'name="([^"]*)"'
    local classname = full_testcase:match 'classname="([^"]*)"'
    local time = full_testcase:match 'time="([^"]*)"'

    if name then
      local status = 'passed'
      local message = ''
      local stacktrace = ''

      local failure_start, failure_end, failure_body = full_testcase:find '<failure [^>]->'
      if failure_start then
        status = 'failed'
        -- Extract message from failure tag attributes
        local fail_msg = full_testcase:match 'message="([^"]*)"'
        message = fail_msg or ''
        -- Extract lines from failure body (between > and </failure>)
        local body_start = full_testcase:find('>', failure_start)
        local body_end = full_testcase:find('</failure>')
        if body_start and body_end then
          local body = full_testcase:sub(body_start + 1, body_end - 1)
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
      else
        local error_start = full_testcase:find '<error '
        if error_start then
          status = 'failed'
          message = 'Error'
        else
          local skipped_pos = full_testcase:find '<skipped'
          if skipped_pos then
            status = 'skipped'
          end
        end
      end

      results[name] = {
        classname = classname,
        time = time,
        status = status,
        message = message,
        stacktrace = stacktrace,
      }
    end
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
