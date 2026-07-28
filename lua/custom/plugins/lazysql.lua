-- LazySQL integration via native floating terminal.
-- TUI database browser (MySQL, PostgreSQL, SQLite, SQL Server, Oracle).
-- Binary auto-install via custom.ensure_tool when missing.

local ensure = require 'custom.ensure_tool'
ensure.prepend_path()

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
  local ok, path_or_err = ensure.ensure_lazysql()
  if not ok then
    vim.notify('LazySQL: ' .. tostring(path_or_err), vim.log.levels.ERROR)
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
    title = ' lazysql ',
    title_pos = 'center',
  })

  state.buf = buf
  state.win = win

  vim.fn.termopen(path_or_err, {
    on_exit = function()
      vim.schedule(close)
    end,
  })

  vim.cmd 'startinsert'

  vim.api.nvim_buf_set_keymap(buf, 't', '<C-q>', '<C-\\><C-n><cmd>lua vim.api.nvim_win_close(0, true)<cr>', {
    noremap = true,
    silent = true,
    desc = 'Close lazysql',
  })
end

local function toggle()
  if is_valid() then
    close()
  else
    open()
  end
end

vim.api.nvim_create_user_command('LazySQL', toggle, { desc = 'Open LazySQL database browser (auto-install if missing)' })

return {
  {
    'lazysql.nvim',
    virtual = true,
    keys = {
      { '<leader>ls', toggle, desc = 'Open [L]azy[S]QL' },
    },
  },
}
