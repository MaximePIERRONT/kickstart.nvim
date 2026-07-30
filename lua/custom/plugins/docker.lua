-- Lazydocker in a floating terminal or fullscreen (Herdr tab + zoom, or Neovim tab).
-- Requires: lazydocker (https://github.com/jesseduffield/lazydocker)

local tui = require 'custom.tui'

local state = {
  buf = nil,
  win = nil,
}

local function is_valid()
  return state.buf
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.win
    and vim.api.nvim_win_is_valid(state.win)
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
  state.win = nil
end

local function open_float()
  if is_valid() then
    close()
    return
  end

  local buf, win = tui.open_float('lazydocker', vim.uv.cwd(), 'lazydocker')
  if not buf or not win then
    vim.notify('lazydocker is not installed. Install it: https://github.com/jesseduffield/lazydocker', vim.log.levels.ERROR)
    return
  end

  state.buf = buf
  state.win = win

  vim.api.nvim_buf_set_keymap(buf, 't', '<C-q>', '<C-\\><C-n><cmd>lua vim.api.nvim_win_close(0,true)<cr>', {
    noremap = true,
    silent = true,
    desc = 'Close lazydocker',
  })
end

local function open_fullscreen()
  tui.open('lazydocker', 'lazydocker', vim.uv.cwd(), 'fullscreen')
end

return {
  {
    'lazydocker.nvim',
    virtual = true,
    cmd = { 'LazyDocker', 'LazyDockerFullscreen' },
    keys = {
      { '<leader>td', open_float, desc = '[T]oggle [D]ocker (float)' },
      { '<leader>tD', open_fullscreen, desc = 'Lazydocker fullscreen' },
    },
    init = function()
      vim.api.nvim_create_user_command('LazyDocker', open_float, { desc = 'Open lazydocker (floating terminal)' })
      vim.api.nvim_create_user_command('LazyDockerFullscreen', open_fullscreen, { desc = 'Open lazydocker fullscreen (Herdr or Neovim tab)' })
    end,
  },
}
