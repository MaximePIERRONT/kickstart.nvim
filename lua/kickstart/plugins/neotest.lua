-- neotest.lua
-- Java test runner with Maven multi-module support
--
-- Uses neotest + neotest-java (jdtls backend) for fast test execution
-- and nvim-dap for debugging

---@module 'lazy'
---@type LazySpec
return {
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-neotest/nvim-nio',
      'nvim-neotest/neotest-java',
    },
    keys = {
      { '<leader>tt', function() require('neotest').run.run() end, desc = 'Run test under cursor' },
      { '<leader>tT', function() require('neotest').run.run(vim.fn.expand('%')) end, desc = 'Run all tests in file' },
      { '<leader>ts', function() require('neotest').run.stop() end, desc = 'Stop running tests' },
      { '<leader>to', function() require('neotest').output.open({ enter = true, align = 'row' }) end, desc = 'Show test output' },
      { '<leader>tS', function() require('neotest').summary.toggle() end, desc = 'Toggle test summary panel' },
      { '<leader>td', function() require('neotest').run.run({ strategy = 'dap' }) end, desc = 'Debug test under cursor' },
    },
    config = function()
      require('neotest').setup {
        -- Java adapter: uses jdtls for test discovery and execution
        adapters = {
          require('neotest-java'),
        },
        -- Icons in the sign column
        icons = {
          passed = '✓',
          failed = '✗',
          running = '○',
          skipped = '○',
        },
      }
    end,
  },
}
