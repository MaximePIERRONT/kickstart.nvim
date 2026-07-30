-- Shared helpers to open CLI TUIs in a float, Neovim tab, or Herdr zoomed pane.

local herdr = require 'custom.herdr'

local M = {}

---@param exe string
---@return string|nil
function M.resolve_exe(exe)
  if vim.fn.executable(exe) == 1 then return exe end
  return nil
end

---@return string|nil
function M.git_root()
  local bufpath = vim.api.nvim_buf_get_name(0)
  local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or vim.uv.cwd()
  local found = vim.fs.find({ '.git' }, { upward = true, path = start, limit = 1 })
  if #found == 0 then return vim.uv.cwd() end
  local git = found[1]
  if vim.fn.isdirectory(git) == 1 then return vim.fs.dirname(git) end
  return vim.fs.dirname(git)
end

---@param cmd string
---@param cwd string|nil
---@param title string
---@param opts { width?: number, height?: number, border?: string }
---@return integer|nil buf
---@return integer|nil win
function M.open_float(cmd, cwd, title, opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.9)
  local height = opts.height or math.floor(vim.o.lines * 0.9)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = opts.border or 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })

  vim.bo[buf].bufhidden = 'wipe'

  local job = vim.fn.termopen(cmd, {
    cwd = cwd or vim.uv.cwd(),
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })
  if job <= 0 then
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    return nil, nil
  end

  vim.cmd 'startinsert'
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, silent = true, desc = 'Close ' .. title })

  return buf, win
end

---@param cmd string
---@param cwd string|nil
---@param title string
function M.open_tab(cmd, cwd, title)
  local prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd 'tabnew'
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buflisted = false

  local job = vim.fn.termopen(cmd, {
    cwd = cwd or vim.uv.cwd(),
    on_exit = function()
      if vim.api.nvim_tabpage_is_valid(prev_tab) then vim.api.nvim_set_current_tabpage(prev_tab) end
      pcall(vim.cmd, 'tabclose')
    end,
  })
  if job <= 0 then
    pcall(vim.cmd, 'tabclose')
    return false
  end

  vim.cmd 'startinsert'
  vim.keymap.set('n', 'q', function() pcall(vim.cmd, 'tabclose') end, { buffer = buf, silent = true, desc = 'Close ' .. title })
  return true
end

---@param exe string
---@param title string
---@param cwd string|nil
---@param layout 'float'|'fullscreen'
function M.open(exe, title, cwd, layout)
  local cmd = M.resolve_exe(exe)
  if not cmd then
    vim.notify(exe .. ' is not installed', vim.log.levels.ERROR)
    return false
  end

  if layout == 'fullscreen' and herdr.available() then
    local ok, err = herdr.open_fullscreen(cmd, title, cwd)
    if ok then return true end
    if err then vim.notify(title .. ' (Herdr): ' .. err .. ' — fallback Neovim tab', vim.log.levels.WARN) end
    return M.open_tab(cmd, cwd, title)
  end

  if layout == 'fullscreen' then return M.open_tab(cmd, cwd, title) end

  local buf, win = M.open_float(cmd, cwd, title)
  return buf ~= nil and win ~= nil
end

return M
