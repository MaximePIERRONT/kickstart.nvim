-- java-test.lua
-- Java Maven test runner with inline results display
--
-- Runs mvn test and parses surefire-reports to show ✓/✗ in gutter
-- and assertion messages + stacktrace as virtual text

---@module 'lazy'
---@type LazySpec
return {
  'kickstart/java-test',
  keys = {
    { '<leader>jt', function() require('java-test').run_file() end, desc = '[J]ava test: run file' },
    { '<leader>jT', function() require('java-test').run_all() end, desc = '[J]ava test: run all' },
    { '<leader>jc', function() require('java-test').clear() end, desc = '[J]ava test: clear results' },
    { '<leader>jo', function() require('java-test').show_output() end, desc = '[J]ava test: show output' },
  },
  config = function()
    local M = {}

    local ns_id = vim.api.nvim_create_namespace 'java-test'
    local sign_group = 'java-test-signs'

    local signs = {
      passed = { text = '✓', texthl = 'DiagnosticOk' },
      failed = { text = '✗', texthl = 'DiagnosticError' },
    }

    vim.fn.sign_define('JavaTestPassed', signs.passed)
    vim.fn.sign_define('JavaTestFailed', signs.failed)

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

    local function find_module_root(pom_dir)
      local parent_pom = pom_dir .. '/pom.xml'
      local content = vim.fn.readfile(parent_pom)
      local is_parent = false
      for _, line in ipairs(content) do
        if line:match '<packaging%pom</packaging>' or line:match '<modules>' then
          is_parent = true
          break
        end
      end
      if is_parent then
        return pom_dir
      end
      local dir = vim.fn.fnamemodify(pom_dir, ':h')
      while dir ~= '' and dir ~= '/' do
        local pom = dir .. '/pom.xml'
        if vim.fn.filereadable(pom) == 1 then
          local content = vim.fn.readfile(pom)
          for _, line in ipairs(content) do
            if line:match '<packaging%pom</packaging>' or line:match '<modules>' then
              return dir
            end
          end
        end
        dir = vim.fn.fnamemodify(dir, ':h')
      end
      return pom_dir
    end

    local function get_module_path(pom_dir, project_root)
      if pom_dir == project_root then
        return nil
      end
      local rel = pom_dir:gsub(project_root .. '/', '')
      return rel
    end

    local function get_class_name(bufpath)
      local rel = nil
      local dir = vim.fn.fnamemodify(bufpath, ':p:h')
      while dir ~= '' and dir ~= '/' do
        local src_test = dir .. '/src/test/java'
        if vim.fn.isdirectory(src_test) == 1 then
          rel = bufpath:gsub(src_test .. '/', ''):gsub('%.java$', '')
          break
        end
        dir = vim.fn.fnamemodify(dir, ':h')
      end
      if not rel then
        local fpath = vim.fn.fnamemodify(bufpath, ':t:r')
        return fpath
      end
      return rel:gsub('/', '.')
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
          (annotation
            name: (identifier) @annotation_name
            (#eq? @annotation_name "Test"))
          name: (identifier) @method_name
          body: (block) @body
        ) @method
      ]])

      for _, captures, metadata in query:iter_matches(root, bufnr) do
        local method_name_node = captures[2]
        local row = (method_name_node:start()) + 1
        local name = vim.treesitter.query.get_node_text(method_name_node, bufnr)
        table.insert(methods, { name = name, row = row })
      end
      return methods
    end

    local function parse_surefire_report(report_path)
      if vim.fn.filereadable(report_path) ~= 1 then return {} end
      local content = vim.fn.readfile(report_path)
      local xml_str = table.concat(content, '\n')

      local results = {}
      for testcase_xml in xml_str:gmatch '<testcase [^>]->' do
        local name = testcase_xml:match 'name="([^"]*)"'
        local classname = testcase_xml:match 'classname="([^"]*)"'
        local time = testcase_xml:match 'time="([^"]*)"'
        local failure_xml = testcase_xml:match '<failure [^>]->(.-)</failure>'
        local error_xml = testcase_xml:match '<error [^>]->(.-)</error>'
        local skipped_xml = testcase_xml:match '<skipped[^/]*/?>'

        if name then
          local status = 'passed'
          local message = ''
          local stacktrace = ''

          if failure_xml then
            status = 'failed'
            local fail_msg = failure_xml:match 'message="([^"]*)"'
            local fail_type = failure_xml:match 'type="([^"]*)"'
            message = fail_msg or ''
            local lines = {}
            for line in failure_xml:gmatch '[^\n]+' do
              line = line:gsub('^%s+', ''):gsub('%s+$', '')
              if line ~= '' and not line:match '^<failure' and not line:match '^</failure' then
                table.insert(lines, line)
              end
            end
            stacktrace = table.concat(lines, '\n')
          elseif error_xml then
            status = 'failed'
            message = 'Error'
          elseif skipped_xml then
            status = 'skipped'
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
      vim.fn.sign_unplace(sign_group, { id = '*', buffer = bufnr })
    end

    local function clear_extmarks(bufnr)
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
        end_row = -1,
        end_col = -1,
        valid = -1,
      })
    end

    function M.clear()
      local bufnr = vim.api.nvim_get_current_buf()
      clear_signs(bufnr)
      clear_extmarks(bufnr)
    end

    local current_output = {}

    function M.run_file()
      local bufnr = vim.api.nvim_get_current_buf()
      local bufpath = vim.api.nvim_buf_get_name(bufnr)
      if not bufpath:match '%.java$' then
        vim.notify('Not a Java file', vim.log.levels.WARN)
        return
      end

      M.clear()

      local pom_path, pom_dir = find_pom(bufpath)
      if not pom_path then
        vim.notify('No pom.xml found', vim.log.levels.ERROR)
        return
      end

      local project_root = find_module_root(pom_dir)
      local module_path = get_module_path(pom_dir, project_root)
      local class_name = get_class_name(bufpath)
      local test_methods = get_test_methods(bufnr)

      local cmd = { 'mvn', 'test', '-f', pom_path }
      if module_path and module_path ~= '' then
        vim.list_extend(cmd, { '-pl', module_path })
      end
      vim.list_extend(cmd, { '-Dtest=' .. class_name })

      vim.notify('Running: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)

      vim.system(cmd, { text = true }, function(obj)
        if obj.code then
          vim.schedule(function()
            vim.notify('Maven test failed: ' .. obj.stderr, vim.log.levels.ERROR)
          end)
          return
        end

        local output = obj.stdout .. '\n' .. obj.stderr
        current_output = output

        vim.schedule(function()
          local report_dir
          if module_path then
            report_dir = module_path .. '/target/surefire-reports'
          else
            report_dir = 'target/surefire-reports'
          end
          local report_path = pom_dir .. '/' .. report_dir .. '/TEST-' .. class_name .. '.xml'
          local results = parse_surefire_report(report_path)

          for _, method in ipairs(test_methods) do
            local result = results[method.name]
            local sign_name = 'JavaTestPassed'
            local virt_lines = {}

            if result then
              if result.status == 'failed' then
                sign_name = 'JavaTestFailed'
                local msg = result.message
                if msg ~= '' then
                  table.insert(virt_lines, { { msg, 'DiagnosticError' } })
                end
                if result.stacktrace ~= '' then
                  local lines = {}
                  for line in result.stacktrace:gmatch '[^\n]+' do
                    line = line:gsub('^%s+', ''):gsub('%s+$', '')
                    if line ~= '' then
                      table.insert(lines, line)
                      if #lines >= 5 then break end
                    end
                  end
                  for _, l in ipairs(lines) do
                    table.insert(virt_lines, { { l, 'Comment' } })
                  end
                end
              elseif result.status == 'skipped' then
                sign_name = 'JavaTestPassed'
                table.insert(virt_lines, { { 'Skipped', 'Comment' } })
              end
            end

            local line = method.row - 1
            vim.fn.sign_place(0, sign_group, sign_name, bufnr, {
              lnum = method.row,
              buffer = bufnr,
            })

            if #virt_lines > 0 then
              vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
                virt_lines = virt_lines,
                virt_lines_above = false,
              })
            end
          end
        end)
      end)
    end

    function M.run_all()
      local bufnr = vim.api.nvim_get_current_buf()
      local bufpath = vim.api.nvim_buf_get_name(bufnr)

      M.clear()

      local pom_path, pom_dir = find_pom(bufpath)
      if not pom_path then
        vim.notify('No pom.xml found', vim.log.levels.ERROR)
        return
      end

      local cmd = { 'mvn', 'test', '-f', pom_path }
      vim.notify('Running: ' .. table.concat(cmd, ' '), vim.log.levels.INFO)

      vim.system(cmd, { text = true }, function(obj)
        if obj.code then
          vim.schedule(function()
            vim.notify('Maven test failed: ' .. obj.stderr, vim.log.levels.ERROR)
          end)
          return
        end

        local output = obj.stdout .. '\n' .. obj.stderr
        current_output = output

        vim.schedule(function()
          vim.notify('All tests complete', vim.log.levels.INFO)
        end)
      end)
    end

    function M.show_output()
      if #current_output == 0 then
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

      local win = vim.api.nvim_open_win(buf, true, opts)
      vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf, nowait = true })
      vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', { buffer = buf, nowait = true, silent = true })
    end

    require('lazy.core.plugin').load()
  end,
}
