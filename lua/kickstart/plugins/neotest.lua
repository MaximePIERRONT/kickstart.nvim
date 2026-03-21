return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'rcasia/neotest-java',
  },
  config = function()
    require('neotest').setup {
      adapters = {
        require('neotest-java'),
      },
    }
  end,
  keys = {
    { '<leader>tr', function() require('neotest').run.run() end, desc = 'Run nearest test' },
    { '<leader>tf', function() require('neotest').run.run(vim.fn.expand '%') end, desc = 'Run file tests' },
    { '<leader>tl', function() require('neotest').run.run_last() end, desc = 'Run last test' },
    { '<leader>ts', function() require('neotest').summary.toggle() end, desc = 'Toggle test summary' },
    { '<leader>to', function() require('neotest').output.open { enter = true } end, desc = 'Show test output' },
    { '<leader>tp', function() require('neotest').output_panel.toggle() end, desc = 'Toggle output panel' },
    { '<leader>tx', function() require('neotest').run.stop() end, desc = 'Stop tests' },
  },
}
