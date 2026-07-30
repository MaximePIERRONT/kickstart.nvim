-- LazyGit in a floating terminal or fullscreen (Herdr tab + zoom, or Neovim tab).

local tui = require 'custom.tui'

local function open_float()
  tui.open('lazygit', 'LazyGit', tui.git_root(), 'float')
end

local function open_fullscreen()
  tui.open('lazygit', 'LazyGit', tui.git_root(), 'fullscreen')
end

return {
  {
    'lazygit.nvim',
    virtual = true,
    cmd = { 'LazyGit', 'LazyGitFullscreen' },
    keys = {
      { '<leader>gg', open_float, desc = 'Lazy[G]it (float)' },
      { '<leader>gG', open_fullscreen, desc = 'Lazy[G]it fullscreen' },
    },
    init = function()
      vim.api.nvim_create_user_command('LazyGit', open_float, { desc = 'Open LazyGit (floating terminal)' })
      vim.api.nvim_create_user_command('LazyGitFullscreen', open_fullscreen, { desc = 'Open LazyGit fullscreen (Herdr or Neovim tab)' })
    end,
  },
}
