-- Neotest notifications plugin: rich test feedback à la IntelliJ
-- Provides:
--   1. nvim-notify for beautiful popup notifications
--   2. Polling-based test result notifications (pass/fail)
--   3. Global keymaps for test runner (not Java-specific)
--   4. Signs and virtual_text in gutter for test status
return {
  -- Rich notification UI (replaces default vim.notify)
  {
    'rcarriga/nvim-notify',
    config = function()
      local notify = require 'notify'
      notify.setup {
        stages = 'fade_in_slide_out',
        timeout = 3000,
        max_width = 80,
        render = 'wrapped-compact',
        icons = {
          ERROR = '',
          WARN = '',
          INFO = '',
          DEBUG = '',
          TRACE = '',
        },
      }
      -- Replace default vim.notify with nvim-notify
      vim.notify = notify
    end,
  },

  -- Neotest config override: signs, virtual_text, and event-driven notifications
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-neotest/nvim-nio',
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'rcasia/neotest-java',
      'rcarriga/nvim-notify',
    },
    config = function()
      local neotest = require 'neotest'

      neotest.setup {
        adapters = {
          require('neotest-java') {
            test_classname_patterns = {
              '^.*Test$',
              '^.*Tests$',
              '^.*IT$',
              '^.*Spec$',
            },
          },
        },

        -- Signs in the gutter next to test functions
        status = {
          enabled = true,
          signs = true,
          virtual_text = true,
        },

        -- Icons for the summary panel and signs
        icons = {
          passed = '',
          failed = '',
          running = '',
          skipped = '',
          unknown = '',
          running_animated = { '', '', '', '', '', '', '' },
        },

        -- Summary panel config (like IntelliJ test tool window)
        summary = {
          enabled = true,
          animated = true,
          follow = true,
          expand_errors = true,
          open = 'botright vsplit | vertical resize 50',
          mappings = {
            expand = { '<CR>', '<2-LeftMouse>' },
            expand_all = 'e',
            output = 'o',
            short = 'O',
            attach = 'a',
            jumpto = 'i',
            stop = 'u',
            run = 'r',
            debug = 'd',
            mark = 'm',
            run_marked = 'R',
            debug_marked = 'D',
            clear_marked = 'M',
            target = 't',
            clear_target = 'T',
          },
        },

        -- Output panel config
        output = {
          enabled = true,
          open_on_run = false,
        },

        output_panel = {
          enabled = true,
          open = 'botright split | resize 15',
        },
      }

      local notify_module = require('custom.neotest-notifications')
      local run_with_notification = notify_module.make_run_with_notification(neotest)

      vim.keymap.set('n', '<leader>tr', function() run_with_notification(neotest.run.run)() end, { desc = '[T]est [R]un (nearest)' })
      vim.keymap.set('n', '<leader>tf', function() run_with_notification(neotest.run.run)(vim.fn.expand '%:p') end, { desc = '[T]est Run [F]ile' })
      vim.keymap.set('n', '<leader>tl', function() run_with_notification(neotest.run.run_last)() end, { desc = '[T]est Run [L]ast' })
      vim.keymap.set('n', '<leader>td', function() run_with_notification(neotest.run.run)({ strategy = 'dap' }) end, { desc = '[T]est [D]ebug (nearest)' })

      vim.keymap.set('n', '<leader>ts', function() neotest.summary.toggle() end, { desc = '[T]est [S]ummary toggle' })
      vim.keymap.set('n', '<leader>to', function() neotest.output.open { enter = true } end, { desc = '[T]est [O]utput' })
      vim.keymap.set('n', '<leader>tp', function() neotest.output_panel.toggle() end, { desc = '[T]est [P]anel toggle' })
      vim.keymap.set('n', '<leader>tx', function() neotest.run.stop() end, { desc = '[T]est Stop (E[x]it)' })

      vim.keymap.set('n', '[t', function() neotest.jump.prev { status = 'failed' } end, { desc = 'Previous failed test' })
      vim.keymap.set('n', ']t', function() neotest.jump.next { status = 'failed' } end, { desc = 'Next failed test' })

      -- Command to download JUnit jar on machines without Neovim 0.12+
      vim.api.nvim_create_user_command('NeotestJavaDownload', function()
        local version = '1.10.1'
        local dir = vim.fn.stdpath 'data' .. '/neotest-java'
        local jar = dir .. '/junit-platform-console-standalone-' .. version .. '.jar'
        if vim.fn.filereadable(jar) == 1 then
          vim.notify('JUnit jar already exists at ' .. jar, vim.log.levels.INFO)
          return
        end
        vim.fn.mkdir(dir, 'p')
        local url = 'https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/'
          .. version
          .. '/junit-platform-console-standalone-'
          .. version
          .. '.jar'
        vim.notify('Downloading JUnit Platform Console Standalone ' .. version .. '...', vim.log.levels.INFO)
        vim.fn.system { 'curl', '-L', '-o', jar, url }
        if vim.v.shell_error == 0 then
          vim.notify('JUnit jar downloaded successfully!', vim.log.levels.INFO)
        else
          vim.notify('Failed to download JUnit jar', vim.log.levels.ERROR)
        end
      end, { desc = 'Download JUnit Platform Console Standalone jar for neotest-java' })
    end,
  },
}
