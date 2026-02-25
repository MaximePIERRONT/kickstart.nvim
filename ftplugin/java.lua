-- ftplugin/java.lua
-- This file is automatically loaded when a Java file is opened.
-- It configures jdtls (Eclipse JDT Language Server) for Java development.

local jdtls = require 'jdtls'

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

-- Detect the OS for the jdtls config directory
local os_config = 'config_linux'
if vim.fn.has 'mac' == 1 then
  os_config = 'config_mac'
elseif vim.fn.has 'win32' == 1 then
  os_config = 'config_win'
end

-- Find the launcher jar
local launcher_jar = vim.fn.glob(jdtls_path .. '/plugins/org.eclipse.equinox.launcher_*.jar')

-- Determine the project name for workspace isolation
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
local workspace_dir = vim.fn.stdpath 'data' .. '/jdtls-workspace/' .. project_name

-- Find the root directory of the project
local root_dir = require('jdtls.setup').find_root { 'pom.xml', 'build.gradle', 'gradlew', '.git', 'mvnw' }

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

  local adapter_root = vim.g.neotest_java_adapter_root
  if adapter_root ~= root_dir then
    require('neotest').setup {
      adapters = {
        new_neotest_java_adapter(),
      },
    }
    vim.g.neotest_java_adapter_root = root_dir
  end
end

if vim.fn.exists ':JavaTestCheck' == 0 then
  vim.api.nvim_create_user_command('JavaTestCheck', function() java_test_check { notify = true } end, {
    desc = 'Verifier les prerequis de tests Java (jdtls/neotest/build tool)',
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

      ensure_neotest_context()

      local ok, neotest = pcall(require, 'neotest')
      if not ok then
        vim.notify('Impossible de charger neotest', vim.log.levels.ERROR, { title = 'Neotest Java' })
        return
      end

      local run_ok, err = pcall(neotest.run.run, target)
      if not run_ok then
        vim.notify('Echec lancement test: ' .. tostring(err), vim.log.levels.ERROR, { title = 'Neotest Java' })
        return
      end

      vim.notify('Execution des tests Java lancee', vim.log.levels.INFO, { title = 'Neotest Java' })
    end

    -- Java-specific keymaps under <leader>j
    vim.keymap.set('n', '<leader>ji', jdtls.organize_imports, vim.tbl_extend('force', opts, { desc = '[J]ava Organize [I]mports' }))
    vim.keymap.set('n', '<leader>jc', jdtls.extract_constant, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [C]onstant' }))
    vim.keymap.set('v', '<leader>jm', function() jdtls.extract_method(true) end, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [M]ethod' }))
    vim.keymap.set('v', '<leader>jv', jdtls.extract_variable, vim.tbl_extend('force', opts, { desc = '[J]ava Extract [V]ariable' }))

    -- Test keymaps using neotest
    local neotest = require 'neotest'
    vim.keymap.set('n', '<leader>jt', function() run_java_test() end, vim.tbl_extend('force', opts, { desc = '[J]ava Run [T]est (cursor)' }))
    vim.keymap.set('n', '<leader>jf', function() run_java_test(vim.fn.expand '%:p') end, vim.tbl_extend('force', opts, { desc = '[J]ava Run Tests [F]ile' }))
    vim.keymap.set('n', '<leader>js', function() neotest.summary.toggle() end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [S]ummary' }))
    vim.keymap.set('n', '<leader>jo', function() neotest.output.open { enter = true } end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [O]utput' }))
    vim.keymap.set('n', '<leader>jC', function() java_test_check { notify = true } end, vim.tbl_extend('force', opts, { desc = '[J]ava Test [C]heck' }))

    -- Debug test under cursor
    vim.keymap.set('n', '<leader>jd', function() run_java_test { strategy = 'dap' } end, vim.tbl_extend('force', opts, { desc = '[J]ava [D]ebug Test' }))
  end,
}

-- Start or attach jdtls
jdtls.start_or_attach(config)
