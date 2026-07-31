-- LazyGit + LazyDocker + LazySQL in a floating or fullscreen terminal (roadmap P2).
-- Binaries auto-install via custom.ensure_tool when missing (GitHub releases).
-- Inside Herdr, fullscreen opens a new tab + zoomed pane via custom.herdr.

local ensure = require 'custom.ensure_tool'
local herdr = require 'custom.herdr'

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
---@param layout 'float'|'fullscreen'
local function open_term(cmd, cwd, title, layout)
  layout = layout or 'float'

  -- Headless / CI: just verify the binary runs with --help / version.
  if #vim.api.nvim_list_uis() == 0 then
    local result = vim.system({ cmd, '--version' }, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then
      -- lazydocker may use -v; lazysql uses -version
      result = vim.system({ cmd, '-v' }, { cwd = cwd, text = true }):wait()
    end
    if result.code ~= 0 then
      result = vim.system({ cmd, '-version' }, { cwd = cwd, text = true }):wait()
    end
    if result.code ~= 0 then error(title .. ' failed to run: ' .. (result.stderr or result.stdout or '')) end
    vim.notify(title .. ' OK (headless)', vim.log.levels.INFO)
    return
  end

  if layout == 'fullscreen' then
    local prev_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd 'tabnew'
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].buflisted = false

    local job = vim.fn.termopen({ cmd }, {
      cwd = cwd or vim.uv.cwd(),
      on_exit = function()
        if vim.api.nvim_tabpage_is_valid(prev_tab) then vim.api.nvim_set_current_tabpage(prev_tab) end
        pcall(vim.cmd, 'tabclose')
      end,
    })
    if job <= 0 then
      vim.notify('Failed to start ' .. title, vim.log.levels.ERROR)
      pcall(vim.cmd, 'tabclose')
      return
    end

    vim.cmd 'startinsert'
    vim.keymap.set('n', 'q', function() pcall(vim.cmd, 'tabclose') end, { buffer = buf, silent = true, desc = 'Close ' .. title })
    return
  end

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

---@param tool 'lazygit'|'lazydocker'|'lazysql'
---@param title string
---@param cwd string|nil
---@param layout 'float'|'fullscreen'
local function open_tool(tool, title, cwd, layout)
  local ok, path_or_err = ensure['ensure_' .. tool]()
  if not ok then
    vim.notify(string.format('%s: %s', title, path_or_err), vim.log.levels.ERROR)
    return
  end

  if layout == 'fullscreen' and herdr.available() then
    local opened, err = herdr.open_fullscreen(path_or_err, title, cwd)
    if opened then return end
    if err then vim.notify(string.format('%s (Herdr): %s — fallback Neovim tab', title, err), vim.log.levels.WARN) end
  end

  open_term(path_or_err, cwd, title, layout)
end

function M.open_lazygit()
  open_tool('lazygit', 'LazyGit', git_root(), 'float')
end

function M.open_lazydocker()
  open_tool('lazydocker', 'LazyDocker', vim.uv.cwd(), 'float')
end

function M.open_lazysql()
  open_tool('lazysql', 'LazySQL', vim.uv.cwd(), 'float')
end

function M.open_lazygit_fullscreen()
  open_tool('lazygit', 'LazyGit', git_root(), 'fullscreen')
end

function M.open_lazydocker_fullscreen()
  open_tool('lazydocker', 'LazyDocker', vim.uv.cwd(), 'fullscreen')
end

vim.api.nvim_create_user_command('LazyGit', function() M.open_lazygit() end, { desc = 'Open LazyGit (auto-install if missing)' })
vim.api.nvim_create_user_command('LazyDocker', function() M.open_lazydocker() end, { desc = 'Open LazyDocker (auto-install if missing)' })
vim.api.nvim_create_user_command('LazySQL', function() M.open_lazysql() end, { desc = 'Open LazySQL (auto-install if missing)' })
vim.api.nvim_create_user_command('LazyGitFullscreen', function() M.open_lazygit_fullscreen() end, { desc = 'Open LazyGit fullscreen (Herdr tab or Neovim tab)' })
vim.api.nvim_create_user_command('LazyDockerFullscreen', function() M.open_lazydocker_fullscreen() end, { desc = 'Open LazyDocker fullscreen (Herdr tab or Neovim tab)' })

vim.keymap.set('n', '<leader>gg', function() M.open_lazygit() end, { desc = 'Open Lazy[G]it', silent = true })
vim.keymap.set('n', '<leader>gG', function() M.open_lazygit_fullscreen() end, { desc = 'Lazy[G]it fullscreen', silent = true })
vim.keymap.set('n', '<leader>ld', function() M.open_lazydocker() end, { desc = 'Open [L]azy[D]ocker', silent = true })
vim.keymap.set('n', '<leader>lD', function() M.open_lazydocker_fullscreen() end, { desc = '[L]azy[D]ocker fullscreen', silent = true })
vim.keymap.set('n', '<leader>ls', function() M.open_lazysql() end, { desc = 'Open [L]azy[S]QL', silent = true })

return M
