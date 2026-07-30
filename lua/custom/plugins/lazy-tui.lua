-- LazyGit + LazyDocker + LazySQL in floating or full-screen tab terminals (roadmap P2).
-- Binaries auto-install via custom.ensure_tool when missing (GitHub releases).

local ensure = require 'custom.ensure_tool'

local M = {}

---@return string|nil
local function git_root()
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
local function run_headless(cmd, cwd, title)
  -- Headless / CI: just verify the binary runs with --help / version.
  local result = vim.system({ cmd, '--version' }, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    -- lazydocker may use -v; lazysql uses -version
    result = vim.system({ cmd, '-v' }, { cwd = cwd, text = true }):wait()
  end
  if result.code ~= 0 then result = vim.system({ cmd, '-version' }, { cwd = cwd, text = true }):wait() end
  if result.code ~= 0 then error(title .. ' failed to run: ' .. (result.stderr or result.stdout or '')) end
  vim.notify(title .. ' OK (headless)', vim.log.levels.INFO)
end

---@param cmd string
---@param cwd string|nil
---@param title string
local function open_float_term(cmd, cwd, title)
  local width = math.max(40, math.floor(vim.o.columns * 0.9))
  local height = math.max(10, math.floor(vim.o.lines * 0.85))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })

  vim.bo[buf].bufhidden = 'wipe'
  vim.wo[win].winhl = 'Normal:Normal'

  local job = vim.fn.termopen({ cmd }, {
    cwd = cwd or vim.uv.cwd(),
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end,
  })
  if job <= 0 then
    vim.notify('Failed to start ' .. title, vim.log.levels.ERROR)
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    return
  end

  vim.cmd 'startinsert'
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end, { buffer = buf, silent = true, desc = 'Close ' .. title })
end

---@param cmd string
---@param cwd string|nil
---@param title string
local function open_tab_term(cmd, cwd, title)
  vim.cmd 'tabnew'
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.bo[buf].bufhidden = 'wipe'

  local job = vim.fn.termopen({ cmd }, {
    cwd = cwd or vim.uv.cwd(),
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      end)
    end,
  })
  if job <= 0 then
    vim.notify('Failed to start ' .. title, vim.log.levels.ERROR)
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    return
  end

  vim.cmd 'startinsert'
end

---@param tool 'lazygit'|'lazydocker'|'lazysql'
---@param title string
---@param cwd string|nil
---@param fullscreen? boolean
local function open_tool(tool, title, cwd, fullscreen)
  local ok, path_or_err = ensure['ensure_' .. tool]()
  if not ok then
    vim.notify(string.format('%s: %s', title, path_or_err), vim.log.levels.ERROR)
    return
  end
  if #vim.api.nvim_list_uis() == 0 then
    run_headless(path_or_err, cwd, title)
  elseif fullscreen then
    open_tab_term(path_or_err, cwd, title)
  else
    open_float_term(path_or_err, cwd, title)
  end
end

function M.open_lazygit()
  open_tool('lazygit', 'LazyGit', git_root())
end

function M.open_lazydocker()
  open_tool('lazydocker', 'LazyDocker', vim.uv.cwd())
end

function M.open_lazygit_fullscreen()
  open_tool('lazygit', 'LazyGit', git_root(), true)
end

function M.open_lazydocker_fullscreen()
  open_tool('lazydocker', 'LazyDocker', vim.uv.cwd(), true)
end

function M.open_lazysql()
  open_tool('lazysql', 'LazySQL', vim.uv.cwd())
end

vim.api.nvim_create_user_command('LazyGit', function() M.open_lazygit() end, { desc = 'Open LazyGit (auto-install if missing)' })
vim.api.nvim_create_user_command('LazyDocker', function() M.open_lazydocker() end, { desc = 'Open LazyDocker (auto-install if missing)' })
vim.api.nvim_create_user_command('LazyGitFullscreen', function() M.open_lazygit_fullscreen() end, { desc = 'Open LazyGit in a full-screen tab' })
vim.api.nvim_create_user_command('LazyDockerFullscreen', function() M.open_lazydocker_fullscreen() end, { desc = 'Open LazyDocker in a full-screen tab' })
vim.api.nvim_create_user_command('LazySQL', function() M.open_lazysql() end, { desc = 'Open LazySQL (auto-install if missing)' })

vim.keymap.set('n', '<leader>gg', function() M.open_lazygit() end, { desc = 'Open Lazy[G]it', silent = true })
vim.keymap.set('n', '<leader>ld', function() M.open_lazydocker() end, { desc = 'Open [L]azy[D]ocker', silent = true })
vim.keymap.set('n', '<leader>gG', function() M.open_lazygit_fullscreen() end, { desc = 'Open Lazy[G]it full-screen', silent = true })
vim.keymap.set('n', '<leader>lF', function() M.open_lazydocker_fullscreen() end, { desc = 'Open [L]azyDocker [F]ull-screen', silent = true })
vim.keymap.set('n', '<leader>ls', function() M.open_lazysql() end, { desc = 'Open [L]azy[S]QL', silent = true })

return M
