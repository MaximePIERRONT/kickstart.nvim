-- neotest.lua
-- Java test runner with Maven multi-module support
--
-- Uses neotest + neotest-java (jdtls backend) for fast test execution
-- and nvim-dap for debugging

---@module 'lazy'
---@type LazySpec
return {
  {
    'rcasia/neotest-java',
    build = function()
      vim.cmd 'NeotestJava setup'
    end,
  },
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-neotest/nvim-nio',
      'rcasia/neotest-java',
    },
    keys = {
      { '<leader>jt', function() require('neotest').run.run() end, desc = '[J]ava test: run under cursor' },
      { '<leader>jT', function() require('neotest').run.run(vim.fn.expand('%')) end, desc = '[J]ava test: run all in file' },
      { '<leader>js', function() require('neotest').run.stop() end, desc = '[J]ava test: stop' },
      { '<leader>jo', function() require('neotest').output.open { enter = true, align = 'row' } end, desc = '[J]ava test: output' },
      { '<leader>jS', function() require('neotest').summary.toggle() end, desc = '[J]ava test: summary panel' },
      { '<leader>jd', function() require('neotest').run.run { strategy = 'dap' } end, desc = '[J]ava test: debug' },
    },
    config = function()
      require('neotest').setup {
        adapters = {
          require('neotest-java'),
        },
        icons = {
          passed = '✓',
          failed = '✗',
          running = '○',
          skipped = '○',
        },
      }

      vim.schedule(function()
        local junit_dir = vim.fn.stdpath('data') .. '/neotest-java'
        local junit_jar = vim.fn.glob(junit_dir .. '/junit-platform-console-standalone-*.jar')
        if junit_jar == '' then
          vim.cmd 'NeotestJava setup'
        end
      end)
    end,
  },
}
