local M = {
  'ThePrimeagen/refactoring.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
  },
  keys = {
    {
      '<leader>rv',
      function() require('refactoring').refactor('Extract Variable') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract [v]ariable',
    },
    {
      '<C-A-v>',
      function() require('refactoring').refactor('Extract Variable') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract variable (IntelliJ)',
    },
    {
      '<leader>rc',
      function()
        vim.lsp.buf.code_action {
          context = { only = { 'refactor.extract.constant' } },
          filter = function(a) return a.title:lower():find('constant') ~= nil end,
          apply = true,
        }
      end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract [c]onstant',
    },
    {
      '<C-A-c>',
      function()
        vim.lsp.buf.code_action {
          context = { only = { 'refactor.extract.constant' } },
          filter = function(a) return a.title:lower():find('constant') ~= nil end,
          apply = true,
        }
      end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract constant (IntelliJ)',
    },
    {
      '<leader>rm',
      function() require('refactoring').refactor('Extract Function') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract [m]ethod',
    },
    {
      '<C-A-m>',
      function() require('refactoring').refactor('Extract Function') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: extract method (IntelliJ)',
    },
    {
      '<leader>ri',
      function() require('refactoring').refactor('Inline Variable') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: [i]nline variable',
    },
    {
      '<C-A-i>',
      function() require('refactoring').refactor('Inline Variable') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: inline variable (IntelliJ)',
    },
    {
      '<leader>rI',
      function() require('refactoring').refactor('Inline Function') end,
      mode = { 'n', 'x' },
      desc = '[R]efactor: inline [I]unction',
    },
  },
  config = function()
    require('refactoring').setup {}
  end,
}

return M
