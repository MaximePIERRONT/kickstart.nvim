-- Herdr multiplexer integration: new tab + install fullscreen LazyGit / LazyDocker keys.
-- Herdr docs: https://herdr.dev/docs/configuration/

local M = {}

---@return string
function M.bundled_config_path()
  -- Prefer path next to this plugin file so unit tests (-u NONE) and
  -- non-standard XDG layouts still find config/herdr/config.toml.
  local info = debug.getinfo(1, 'S')
  local src = info and info.source or ''
  if src:sub(1, 1) == '@' then
    local plugin_file = src:sub(2)
    -- .../lua/custom/plugins/herdr.lua → repo root
    local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(plugin_file))))
    local candidate = vim.fs.joinpath(root, 'config', 'herdr', 'config.toml')
    if vim.uv.fs_stat(candidate) then return candidate end
  end
  return vim.fs.joinpath(vim.fn.stdpath 'config', 'config', 'herdr', 'config.toml')
end

---@return string
function M.user_config_path()
  local override = vim.env.HERDR_CONFIG_PATH
  if override and override ~= '' then return override end
  local xdg = vim.env.XDG_CONFIG_HOME
  if xdg and xdg ~= '' then return vim.fs.joinpath(xdg, 'herdr', 'config.toml') end
  return vim.fs.joinpath(vim.fn.expand '~', '.config', 'herdr', 'config.toml')
end

---@return boolean
function M.inside_herdr()
  local function set(v)
    return type(v) == 'string' and v ~= ''
  end
  return set(vim.env.HERDR_SOCKET_PATH) or set(vim.env.HERDR_PANE_ID) or set(vim.env.HERDR_TAB_ID)
end

---@return string|nil
function M.herdr_bin()
  if vim.fn.executable 'herdr' == 1 then return vim.fn.exepath 'herdr' end
  return nil
end

---Create a new Herdr tab focused on the new root pane.
---@param opts { label?: string, cwd?: string }|nil
---@return boolean ok
---@return string|nil err
function M.new_tab(opts)
  opts = opts or {}
  local bin = M.herdr_bin()
  if not bin then return false, 'herdr executable not found (is Herdr installed?)' end
  if not M.inside_herdr() then
    return false, 'not inside a Herdr session (HERDR_SOCKET_PATH unset)'
  end

  local cmd = { bin, 'tab', 'create', '--focus' }
  if opts.label and opts.label ~= '' then
    vim.list_extend(cmd, { '--label', opts.label })
  end
  if opts.cwd and opts.cwd ~= '' then
    vim.list_extend(cmd, { '--cwd', opts.cwd })
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    local err = (result.stderr or result.stdout or ''):gsub('%s+$', '')
    return false, err ~= '' and err or ('herdr tab create failed (exit ' .. result.code .. ')')
  end
  return true
end

---Install kickstart Herdr keybindings into the user Herdr config.
---Creates ~/.config/herdr/config.toml when missing; otherwise merges the
---managed block (idempotent) without wiping other settings.
---@return boolean ok
---@return string message
function M.install_config()
  local src = M.bundled_config_path()
  if not vim.uv.fs_stat(src) then return false, 'bundled Herdr config missing: ' .. src end

  local dest = M.user_config_path()
  vim.fn.mkdir(vim.fs.dirname(dest), 'p')

  local bundled = table.concat(vim.fn.readfile(src), '\n')
  local begin_mark = '# BEGIN kickstart.nvim herdr keys'
  local end_mark = '# END kickstart.nvim herdr keys'
  local block = begin_mark .. '\n' .. bundled .. '\n' .. end_mark .. '\n'

  ---@param text string
  local function write_text(path, text)
    local lines = vim.split(text, '\n', { plain = true })
    if lines[#lines] == '' then table.remove(lines) end
    vim.fn.writefile(lines, path)
  end

  ---@param existing string
  ---@return string
  local function merge_block(existing)
    local start_at = existing:find(begin_mark, 1, true)
    if not start_at then
      if existing ~= '' and not existing:find('\n$') then existing = existing .. '\n' end
      return existing .. '\n' .. block
    end
    local end_at = existing:find(end_mark, start_at, true)
    if not end_at then return existing .. '\n' .. block end
    end_at = end_at + #end_mark
    if existing:sub(end_at + 1, end_at + 1) == '\n' then end_at = end_at + 1 end
    return existing:sub(1, start_at - 1) .. block .. existing:sub(end_at + 1)
  end

  if not vim.uv.fs_stat(dest) then
    write_text(dest, block)
    return true, 'wrote ' .. dest
  end

  local existing = table.concat(vim.fn.readfile(dest), '\n')
  if not existing:find('\n$') and existing ~= '' then existing = existing .. '\n' end
  local updated = merge_block(existing)

  if updated == existing then return true, 'already up to date: ' .. dest end

  -- Backup once before rewriting a pre-existing config.
  local bak = dest .. '.bak-kickstart'
  if not vim.uv.fs_stat(bak) then write_text(bak, existing) end
  write_text(dest, updated)
  return true, 'updated ' .. dest .. ' (backup: ' .. bak .. ')'
end

function M.open_new_tab()
  local ok, err = M.new_tab()
  if not ok then
    vim.notify('Herdr new tab: ' .. (err or 'failed'), vim.log.levels.ERROR)
    return
  end
  vim.notify('Herdr: new tab created', vim.log.levels.INFO)
end

function M.do_install_config()
  local ok, msg = M.install_config()
  if not ok then
    vim.notify('HerdrInstallConfig: ' .. msg, vim.log.levels.ERROR)
    return
  end
  vim.notify(
    'HerdrInstallConfig: '
      .. msg
      .. '\nKeys: ctrl+alt+c / prefix+c = new tab; prefix+alt+g = LazyGit; prefix+alt+d = LazyDocker (fullscreen).\nReload with: herdr server reload-config',
    vim.log.levels.INFO
  )
end

vim.api.nvim_create_user_command('HerdrNewTab', function() M.open_new_tab() end, { desc = 'Create a new Herdr tab (focused)' })
vim.api.nvim_create_user_command('HerdrInstallConfig', function() M.do_install_config() end, {
  desc = 'Install kickstart Herdr keybindings (new tab + LazyGit/LazyDocker fullscreen)',
})

vim.keymap.set('n', '<leader>Ht', function() M.open_new_tab() end, { desc = '[H]erdr new [T]ab', silent = true })
vim.keymap.set('n', '<leader>Hi', function() M.do_install_config() end, { desc = '[H]erdr [I]nstall config keys', silent = true })

return M
