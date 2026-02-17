-- Lazydocker integration via native floating terminal
-- Requires: lazydocker (https://github.com/jesseduffield/lazydocker)

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

local function open()
  if vim.fn.executable 'lazydocker' ~= 1 then
    vim.notify('lazydocker is not installed. Install it: https://github.com/jesseduffield/lazydocker', vim.log.levels.ERROR)
    return
  end

  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.9)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' lazydocker ',
    title_pos = 'center',
  })

  state.buf = buf
  state.win = win

  vim.fn.termopen('lazydocker', {
    on_exit = function()
      vim.schedule(close)
    end,
  })

  vim.cmd 'startinsert'

  -- Close with q or <Esc> when not in lazydocker's own input
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-q>', '<C-\\><C-n><cmd>lua vim.api.nvim_win_close(0, true)<cr>', {
    noremap = true,
    silent = true,
    desc = 'Close lazydocker',
  })
end

local function toggle()
  if is_valid() then
    close()
  else
    open()
  end
end

return {
  {
    'lazydocker.nvim',
    virtual = true,
    keys = {
      { '<leader>td', toggle, desc = '[T]oggle [D]ocker' },
    },
  },
}
