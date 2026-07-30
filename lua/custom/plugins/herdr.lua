-- Herdr: new tab from Neovim (<leader>Ht / :HerdrTab).

local herdr = require 'custom.herdr'

local function create_tab()
  local ok, err = herdr.create_tab(vim.uv.cwd(), 'nvim')
  if not ok then vim.notify('Herdr tab: ' .. (err or 'échec'), vim.log.levels.ERROR) end
end

return {
  {
    'herdr.nvim',
    virtual = true,
    cmd = { 'HerdrTab' },
    keys = {
      { '<leader>Ht', create_tab, desc = 'Herdr new [T]ab' },
    },
    init = function()
      vim.api.nvim_create_user_command('HerdrTab', create_tab, { desc = 'Create a new Herdr tab (focused)' })
    end,
  },
}
