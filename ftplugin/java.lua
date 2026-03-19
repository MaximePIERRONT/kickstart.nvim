-- ftplugin/java.lua
-- This file is automatically loaded when a Java file is opened.
-- It configures jdtls (Eclipse JDT Language Server) for Java development.

local jdtls = require 'jdtls'
local notify_module = require 'custom.neotest-notifications'

-- Mason install paths
local mason_path = vim.fn.stdpath 'data' .. '/mason/packages'
local jdtls_path = mason_path .. '/jdtls'
local java_debug_path = mason_path .. '/java-debug-adapter'
local java_test_path = mason_path .. '/java-test'

local function first_non_empty_glob(pattern)
  local matches = vim.split(vim.fn.glob(pattern, true), '\n')
  for _, match in ipairs(matches) do
    if match ~= '' then
      return match
    end
  end
  return nil
end

local function detect_build_tool(project_root)
  if project_root and vim.fn.filereadable(project_root .. '/mvnw') == 1 then
    return './mvnw'
  end
  if project_root and vim.fn.filereadable(project_root .. '/gradlew') == 1 then
    return './gradlew'
  end
  if vim.fn.executable 'mvn' == 1 then
    return 'mvn'
  end
  local sdkman_mvn = vim.fn.expand '~/.sdkman/candidates/maven/current/bin/mvn'
  if vim.fn.executable(sdkman_mvn) == 1 then
    return sdkman_mvn
  end
  if vim.fn.executable 'gradle' == 1 then
    return 'gradle'
  end
  return nil
end

local function new_neotest_java_adapter()
  return require('neotest-java') {
    test_classname_patterns = {
      '^.*Test$',
      '^.*Tests$',
      '^.*IT$',
      '^.*Spec$',
    },
  }
end

local function nearest_pom_dir(start_path)
  local dir = start_path
  if vim.fn.filereadable(start_path) == 1 then
    dir = vim.fs.dirname(start_path)
  end

  while dir and dir ~= '' do
    if vim.fn.filereadable(dir .. '/pom.xml') == 1 then
      return dir
    end

    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end

  return nil
end

local function pom_has_modules(pom_path)
  if vim.fn.filereadable(pom_path) ~= 1 then
    return false
  end

  for _, line in ipairs(vim.fn.readfile(pom_path)) do
    if line:match '<modules>' then
      return true
    end
  end

  return false
end

local function find_workspace_root(start_path)
  local module_root = nearest_pom_dir(start_path)
  if not module_root then
    return nil
  end

  local workspace_root = module_root
  local dir = module_root
  while dir and dir ~= '' do
    local pom = dir .. '/pom.xml'
    if pom_has_modules(pom) then
      workspace_root = dir
    end

    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end

  return workspace_root
end

-- Detect the OS for the jdtls config directory
local os_config = 'config_linux'
if vim.fn.has 'mac' == 1 then
  os_config = 'config_mac'
elseif vim.fn.has 'win32' == 1 then
  os_config = 'config_win'
end

-- Find the launcher jar
local launcher_jar = vim.fn.glob(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar')

-- Find the root directory of the project
local current_file = vim.api.nvim_buf_get_name(0)
local start_path = current_file ~= '' and current_file or vim.fn.getcwd()
local root_dir = find_workspace_root(start_path) or require('jdtls.setup').find_root { 'pom.xml', 'build.gradle', 'gradlew', '.git', 'mvnw' }

-- Determine the project name for workspace isolation
local project_name = root_dir and vim.fn.fnamemodify(root_dir, ':t') or 'default'
local workspace_dir = vim.fn.stdpath 'data' .. '/jdtls-workspace/' .. project_name

local function java_test_check(opts)
  opts = opts or {}
  local notify = opts.notify ~= false

  local errors = {}
  local warnings = {}

  if launcher_jar == '' then
    table.insert(errors, 'jdtls launcher JAR introuvable (Mason: jdtls)')
  end

  if root_dir == nil then
    table.insert(errors, 'racine de projet Java non detectee (pom.xml/build.gradle/gradlew/.git/mvnw)')
  end

  local has_java_test = first_non_empty_glob(java_test_path .. '/extension/server/*.jar') ~= nil
  if not has_java_test then
    table.insert(errors, 'bundle java-test introuvable (Mason: java-test)')
  end

  local has_java_debug = first_non_empty_glob(java_debug_path .. '/extension/server/com.microsoft.java.debug.plugin-*.jar') ~= nil
  if not has_java_debug then
    table.insert(warnings, 'bundle java-debug-adapter introuvable (debug de tests indisponible)')
  end

  if vim.fn.executable 'java' ~= 1 then
    table.insert(errors, 'commande java introuvable dans le PATH')
  end

  local build_tool = detect_build_tool(root_dir)
  if not build_tool then
    table.insert(errors, 'aucun build tool detecte (mvn/mvnw/gradle/gradlew)')
  end

  local has_neotest = pcall(require, 'neotest')
  if not has_neotest then
    table.insert(errors, 'plugin neotest non charge')
  end

  local is_ok = #errors == 0
  if notify then
    if is_ok then
      local message = 'Java tests prets'
      if #warnings > 0 then
        message = message .. '\nWarnings:\n- ' .. table.concat(warnings, '\n- ')
      end
      vim.notify(message, vim.log.levels.INFO, { title = 'JavaTestCheck' })
    else
      local message = 'Java tests non prets:\n- ' .. table.concat(errors, '\n- ')
      if #warnings > 0 then
        message = message .. '\nWarnings:\n- ' .. table.concat(warnings, '\n- ')
      end
      vim.notify(message, vim.log.levels.ERROR, { title = 'JavaTestCheck' })
    end
  end

  return is_ok
end

local function ensure_neotest_context()
  if root_dir and vim.fn.getcwd() ~= root_dir then
    vim.cmd.lcd(root_dir)
  end
end

local function close_floating_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function show_popup(title, lines)
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', { plain = true })
  end
  lines = lines or {}

  local cleaned = {}
  for _, line in ipairs(lines) do
    if line ~= '' then
      table.insert(cleaned, line)
    end
  end
  if #cleaned == 0 then
    cleaned = { '(no output)' }
  end

  local max_width = 40
  for _, line in ipairs(cleaned) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  local width = math.min(max_width + 2, math.floor(vim.o.columns * 0.9))
  local height = math.min(#cleaned, math.floor(vim.o.lines * 0.7))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cleaned)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })

  vim.keymap.set('n', 'q', function() close_floating_window(win) end, { buffer = buf, silent = true })
  vim.keymap.set('n', '<Esc>', function() close_floating_window(win) end, { buffer = buf, silent = true })
end

local function tail_lines(text, max_lines)
  if not text or text == '' then
    return { '(no output)' }
  end

  local lines = vim.split(text, '\n', { plain = true })
  local start_idx = math.max(1, #lines - max_lines + 1)
  local tail = {}
  for i = start_idx, #lines do
    table.insert(tail, lines[i])
  end
  return tail
end

local function find_nearest_pom(start_path)
  return nearest_pom_dir(start_path)
end

local function current_module_dir()
  local current_file = vim.api.nvim_buf_get_name(0)
  local start_path = current_file ~= '' and current_file or vim.fn.getcwd()
  return find_nearest_pom(start_path)
end

local function detect_maven_executable(module_dir)
  if module_dir and vim.fn.filereadable(module_dir .. '/mvnw') == 1 then
    return './mvnw'
  end
  if vim.fn.executable 'mvn' == 1 then
    return 'mvn'
  end
  local sdkman_mvn = vim.fn.expand '~/.sdkman/candidates/maven/current/bin/mvn'
  if vim.fn.executable(sdkman_mvn) == 1 then
    return sdkman_mvn
  end
  return nil
end

local function open_in_preferred_browser(file_path)
  local uri = vim.uri_from_fname(file_path)

  if vim.ui and vim.ui.open then
    local ok = pcall(vim.ui.open, uri)
    if ok then
      return true
    end
  end

  if vim.fn.executable 'xdg-open' == 1 then
    vim.system({ 'xdg-open', uri }, { detach = true }, function() end)
    return true
  end

  return false
end

local function counter_stats(xml, counter_type)
  local missed, covered = xml:match('<counter%s+type="' .. counter_type .. '"%s+missed="(%d+)"%s+covered="(%d+)"%s*/>')
  if not missed or not covered then
    covered, missed = xml:match('<counter%s+type="' .. counter_type .. '"%s+covered="(%d+)"%s+missed="(%d+)"%s*/>')
  end
  if not missed or not covered then
    return nil
  end

  local missed_n = tonumber(missed) or 0
  local covered_n = tonumber(covered) or 0
  local total = missed_n + covered_n
  local pct = total > 0 and (covered_n / total) * 100 or 0

  return {
    missed = missed_n,
    covered = covered_n,
    pct = pct,
  }
end

local function coverage_summary_lines(module_dir)
  local report_xml = module_dir .. '/target/site/jacoco/jacoco.xml'
  local report_html = module_dir .. '/target/site/jacoco/index.html'

  if vim.fn.filereadable(report_xml) ~= 1 then
    return nil, report_html, { 'Coverage report not found: ' .. report_xml }
  end

  local xml_content = table.concat(vim.fn.readfile(report_xml), '\n')
  local line = counter_stats(xml_content, 'LINE')
  local instr = counter_stats(xml_content, 'INSTRUCTION')
  local branch = counter_stats(xml_content, 'BRANCH')

  local lines = {
    'Module: ' .. module_dir,
    '',
    string.format('Line coverage:        %6.2f%% (%d/%d)', line and line.pct or 0, line and line.covered or 0, (line and (line.covered + line.missed)) or 0),
    string.format('Instruction coverage: %6.2f%% (%d/%d)', instr and instr.pct or 0, instr and instr.covered or 0, (instr and (instr.covered + instr.missed)) or 0),
    string.format('Branch coverage:      %6.2f%% (%d/%d)', branch and branch.pct or 0, branch and branch.covered or 0, (branch and (branch.covered + branch.missed)) or 0),
    '',
    'HTML report:',
    report_html,
    '',
    'Press q or <Esc> to close this window.',
  }

  return lines, report_html, nil
end

local function run_module_maven(args, opts)
  opts = opts or {}

  if not java_test_check { notify = false } then
    vim.notify('Java prerequisites are incomplete. Run :JavaTestCheck', vim.log.levels.ERROR, { title = opts.title or 'JavaModule' })
    return
  end

  local module_dir = current_module_dir()
  if not module_dir then
    vim.notify('No Maven module found from current buffer (missing pom.xml)', vim.log.levels.ERROR, { title = opts.title or 'JavaModule' })
    return
  end

  local mvn = detect_maven_executable(module_dir)
  if not mvn then
    vim.notify('Maven executable not found (mvn/mvnw)', vim.log.levels.ERROR, { title = opts.title or 'JavaModule' })
    return
  end

  local cmd = { mvn }
  vim.list_extend(cmd, args)

  vim.notify('Running in module: ' .. module_dir, vim.log.levels.INFO, { title = opts.title or 'JavaModule' })

  vim.system(cmd, { cwd = module_dir, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local output = (result.stderr and result.stderr ~= '') and result.stderr or result.stdout
        show_popup((opts.title or 'JavaModule') .. ' failed', tail_lines(output, 40))
        return
      end

      if opts.on_success then
        opts.on_success(module_dir, result)
      else
        vim.notify('Command completed successfully', vim.log.levels.INFO, { title = opts.title or 'JavaModule' })
      end
    end)
  end)
end

local function run_module_tests()
  run_module_maven({ 'test' }, {
    title = 'JavaModuleTest',
    on_success = function(module_dir)
      vim.notify('Module tests passed: ' .. module_dir, vim.log.levels.INFO, { title = 'JavaModuleTest' })
    end,
  })
end

local function run_module_coverage()
  run_module_maven({
    'org.jacoco:jacoco-maven-plugin:prepare-agent',
    'test',
    'org.jacoco:jacoco-maven-plugin:report',
  }, {
    title = 'JavaModuleCoverage',
    on_success = function(module_dir)
      local lines, report_html, err_lines = coverage_summary_lines(module_dir)
      if err_lines then
        show_popup('JavaModuleCoverage', err_lines)
        return
      end

      show_popup('Java Module Coverage', lines)

      local opened = open_in_preferred_browser(report_html)
      if not opened then
        vim.notify('Could not open browser automatically for report: ' .. report_html, vim.log.levels.WARN, { title = 'JavaModuleCoverage' })
      end
    end,
  })
end

if vim.fn.exists ':JavaTestCheck' == 0 then
  vim.api.nvim_create_user_command('JavaTestCheck', function() java_test_check { notify = true } end, {
    desc = 'Verifier les prerequis de tests Java (jdtls/neotest/build tool)',
  })
end

if vim.fn.exists ':JavaModuleTest' == 0 then
  vim.api.nvim_create_user_command('JavaModuleTest', run_module_tests, {
    desc = 'Run all tests for current Maven module',
  })
end

if vim.fn.exists ':JavaModuleCoverage' == 0 then
  vim.api.nvim_create_user_command('JavaModuleCoverage', run_module_coverage, {
    desc = 'Run coverage for current Maven module and open HTML report',
  })
end

-- Collect debug and test bundles
local bundles = {}

-- java-debug-adapter
local debug_jar = vim.fn.glob(java_debug_path .. '/extension/server/com.microsoft.java.debug.plugin-*.jar', true)
if debug_jar ~= '' then
  table.insert(bundles, debug_jar)
end

-- java-test
local test_jars = vim.split(vim.fn.glob(java_test_path .. '/extension/server/*.jar', true), '\n')
for _, jar in ipairs(test_jars) do
  if jar ~= '' then
    table.insert(bundles, jar)
  end
end

-- jdtls configuration
local config = {
  cmd = {
    'java',
    '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Dosgi.bundles.defaultStartLevel=4',
    '-Declipse.product=org.eclipse.jdt.ls.core.product',
    '-Dlog.protocol=true',
    '-Dlog.level=ALL',
    '-Xmx1g',
    '--add-modules=ALL-SYSTEM',
    '--add-opens', 'java.base/java.util=ALL-UNNAMED',
    '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
    '-jar', launcher_jar,
    '-configuration', jdtls_path .. '/' .. os_config,
    '-data', workspace_dir,
  },

  root_dir = root_dir,

  settings = {
    java = {
      signatureHelp = { enabled = true },
      contentProvider = { preferred = 'fernflower' },
      completion = {
        favoriteStaticMembers = {
          'org.junit.jupiter.api.Assertions.*',
          'org.mockito.Mockito.*',
          'org.mockito.ArgumentMatchers.*',
          'java.util.Objects.requireNonNull',
          'java.util.Objects.requireNonNullElse',
        },
      },
      sources = {
        organizeImports = {
          starThreshold = 9999,
          staticStarThreshold = 9999,
        },
      },
    },
  },

  init_options = {
    bundles = bundles,
  },

  -- Called when jdtls attaches to a buffer
  on_attach = function(_, bufnr)
    -- Enable debug and test support after LSP is ready
    jdtls.setup_dap { hotcodereplace = 'auto' }
    require('jdtls.dap').setup_dap_main_class_configs()

    local opts = { buffer = bufnr }

    local function run_java_test(target)
      if not java_test_check { notify = false } then
        vim.notify('Prerequis Java incomplets. Lance :JavaTestCheck', vim.log.levels.ERROR, { title = 'Neotest Java' })
        return
      end

      local current_file = vim.api.nvim_buf_get_name(0)
      local module_dir = nearest_pom_dir(current_file)
      if module_dir and vim.fn.getcwd() ~= module_dir then
        vim.cmd.lcd(module_dir)
      end

      local ok, neotest = pcall(require, 'neotest')
      if not ok then
        vim.notify('Impossible de charger neotest', vim.log.levels.ERROR, { title = 'Neotest Java' })
        return
      end

      local adapter_root = vim.g.neotest_java_adapter_root
      if adapter_root ~= module_dir then
        neotest.setup {
          adapters = {
            new_neotest_java_adapter(),
          },
        }
        vim.g.neotest_java_adapter_root = module_dir
      end

      local run_with_notification = notify_module.make_run_with_notification(neotest)
      local wrapped_run = run_with_notification(neotest.run.run)

      local run_ok, err = pcall(wrapped_run, target)
      if not run_ok then
        vim.notify('Echec lancement test: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Neotest Java' })
        return
      end
    end

    -- Java-specific keymaps under <leader>j
    vim.keymap.set('n', '<leader>ji', jdtls.organize_imports, vim.tbl_extend('force', opts, { desc = '[J]ava Organize [I]mports' }))
    vim.keymap.set('n', '<leader>jc', jdtls.extract_constant, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [C]onstant' }))
    vim.keymap.set('v', '<leader>jm', function() jdtls.extract_method(true) end, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [M]ethod' }))
    vim.keymap.set('v', '<leader>jv', jdtls.extract_variable, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [V]ariable' }))

    -- Test keymaps using neotest
    local neotest = require 'neotest'
    local run_with_notification = notify_module.make_run_with_notification(neotest)
    local wrapped_run = run_with_notification(neotest.run.run)
    vim.keymap.set('n', '<leader>jt', function() run_java_test() end, vim.tbl_extend('force', opts, { desc = '[J]ava Run [T]est (cursor)' }))
    vim.keymap.set('n', '<leader>jf', function() run_java_test(vim.fn.expand '%:p') end, vim.tbl_extend('force', opts, { desc = '[J]ava Run Tests [F]ile' }))
    vim.keymap.set('n', '<leader>js', function() neotest.summary.toggle() end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [S]ummary' }))
    vim.keymap.set('n', '<leader>jo', function() neotest.output.open { enter = true } end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [O]utput' }))
    vim.keymap.set('n', '<leader>jC', function() java_test_check { notify = true } end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [C]heck' }))
    vim.keymap.set('n', '<leader>jT', run_module_tests, vim.tbl_extend('force', opts, { desc = '[J]ava Run Module [T]ests' }))
    vim.keymap.set('n', '<leader>jR', run_module_coverage, vim.tbl_extend('force', opts, { desc = '[J]ava Module Cove[R]age' }))

    -- Debug test under cursor
    vim.keymap.set('n', '<leader>jd', function() run_java_test { strategy = 'dap' } end, vim.tbl_extend('force', opts, { desc = '[J]ava [D]ebug Test' }))
  end,
}

-- Start or attach jdtls
jdtls.start_or_attach(config)
