return {
  'kdheepak/lazygit.nvim',
  cmd = 'LazyGit',
  keys = {
    { '<leader>gg', '<cmd>LazyGit<cr>', desc = 'Open LazyGit' },
    { '<leader>gf', '<cmd>LazyGitFilter<cr>', desc = 'LazyGit Filter' },
  },
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
}
