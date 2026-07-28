-- LazyGit + LazyDocker + Rainfrog in a floating terminal.
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

---Prefer DATABASE_URL from the environment (common for Postgres/MySQL/SQLite apps).
---@return string|nil
local function database_url()
  local url = vim.env.DATABASE_URL
  if url and url ~= '' then return url end
  return nil
end

---@param cmd string|string[]
---@param cwd string|nil
---@param title string
local function open_float_term(cmd, cwd, title)
  local argv = type(cmd) == 'table' and cmd or { cmd }
  local exe = argv[1]

  -- Headless / CI: just verify the binary runs with --help / version.
  if #vim.api.nvim_list_uis() == 0 then
    local result = vim.system({ exe, '--version' }, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then
      -- lazydocker may use different flags
      result = vim.system({ exe, '-v' }, { cwd = cwd, text = true }):wait()
    end
    if result.code ~= 0 then
      result = vim.system({ exe, '-V' }, { cwd = cwd, text = true }):wait()
    end
    if result.code ~= 0 then error(title .. ' failed to run: ' .. (result.stderr or result.stdout or '')) end
    vim.notify(title .. ' OK (headless)', vim.log.levels.INFO)
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

  local job = vim.fn.termopen(argv, {
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

---@param tool 'lazygit'|'lazydocker'|'rainfrog'
---@param title string
---@param cwd string|nil
---@param extra_args string[]|nil
local function open_tool(tool, title, cwd, extra_args)
  local ok, path_or_err = ensure['ensure_' .. tool]()
  if not ok then
    vim.notify(string.format('%s: %s', title, path_or_err), vim.log.levels.ERROR)
    return
  end
  local argv = { path_or_err }
  if extra_args then
    for _, a in ipairs(extra_args) do
      table.insert(argv, a)
    end
  end
  open_float_term(argv, cwd, title)
end

function M.open_lazygit()
  open_tool('lazygit', 'LazyGit', git_root())
end

function M.open_lazydocker()
  open_tool('lazydocker', 'LazyDocker', vim.uv.cwd())
end

function M.open_rainfrog()
  local extra = nil
  local url = database_url()
  if url then extra = { '-u', url } end
  open_tool('rainfrog', 'Rainfrog', vim.uv.cwd(), extra)
end

vim.api.nvim_create_user_command('LazyGit', function() M.open_lazygit() end, { desc = 'Open LazyGit (auto-install if missing)' })
vim.api.nvim_create_user_command('LazyDocker', function() M.open_lazydocker() end, { desc = 'Open LazyDocker (auto-install if missing)' })
vim.api.nvim_create_user_command('Rainfrog', function() M.open_rainfrog() end, { desc = 'Open Rainfrog DB TUI (auto-install if missing)' })

vim.keymap.set('n', '<leader>gg', function() M.open_lazygit() end, { desc = 'Open Lazy[G]it', silent = true })
vim.keymap.set('n', '<leader>ld', function() M.open_lazydocker() end, { desc = 'Open [L]azy[D]ocker', silent = true })
vim.keymap.set('n', '<leader>db', function() M.open_rainfrog() end, { desc = 'Open Rainfrog [D]ata[B]ase TUI', silent = true })

return M
