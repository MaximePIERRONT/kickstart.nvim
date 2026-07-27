-- Project runners: npm (frontend) + Maven (Java / Micronaut)
-- Roadmap P1 — lancer un projet sans quitter Neovim.
--
-- Keymaps (<leader>r = [R]un) :
--   rd  npm run [d]ev
--   rb  npm run [b]uild
--   rt  npm [t]est
--   rs  npm [s]cript (picker)
--   rc  maven [c]ompile
--   rp  maven [p]ackage
--   rm  micronaut : picker configs sauvées / créer / mn:run simple
--   rM  micronaut : créer / éditer une config (sauvegarde)
--   rj  [j]ava run (spring-boot:run si détecté, sinon prompt)
--   rg  maven [g]oals (prompt libre)
--
-- Configs Micronaut sauvegardées dans <racine-projet>/.nvim/runners.json
-- Exemple :
-- {
--   "version": 1,
--   "default": "local-dev",
--   "configs": [
--     {
--       "name": "local-dev",
--       "type": "micronaut",
--       "environments": "dev,local",
--       "config_files": ["config/application-local.yml"],
--       "env_file": ".env.local",
--       "env": { "DATASOURCE_PASSWORD": "secret" },
--       "jvm_args": "",
--       "app_args": ""
--     }
--   ]
-- }

local TERM_HEIGHT = 15
local CONFIG_DIR = '.nvim'
local CONFIG_FILE = 'runners.json'

---@param ... string
---@return string
local function path_join(...)
  if vim.fs.joinpath then return vim.fs.joinpath(...) end
  return table.concat({ ... }, '/')
end

---@param s string
---@param prefix string
---@return boolean
local function starts_with(s, prefix)
  if vim.startswith then return vim.startswith(s, prefix) end
  return s:sub(1, #prefix) == prefix
end

---Find nearest ancestor directory containing one of the marker files.
---@param markers string[]
---@return string|nil root
---@return string|nil marker_path
local function find_root(markers)
  local bufpath = vim.api.nvim_buf_get_name(0)
  local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or vim.uv.cwd()
  local found = vim.fs.find(markers, { upward = true, path = start, limit = 1 })
  if #found == 0 then return nil, nil end
  return vim.fs.dirname(found[1]), found[1]
end

---@param exe string
---@return boolean
local function has_exe(exe) return vim.fn.executable(exe) == 1 end

---Merge extra env vars onto the current process environment (termopen replaces if set).
---@param extra table<string, string>|nil
---@return table<string, string>
local function merge_env(extra)
  local env = vim.fn.environ()
  for k, v in pairs(extra or {}) do
    env[tostring(k)] = tostring(v)
  end
  return env
end

---@param cmd string|string[]
---@param cwd string
---@param title string
---@param env table<string, string>|nil
local function run_in_terminal(cmd, cwd, title, env)
  local cmd_str = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd
  vim.notify(string.format('%s → %s', title, cmd_str), vim.log.levels.INFO)

  -- Headless CI: run synchronously (no terminal UI).
  if #vim.api.nvim_list_uis() == 0 then
    local opts = { cwd = cwd, env = merge_env(env), text = true }
    local result
    if type(cmd) == 'table' then
      result = vim.system(cmd, opts):wait()
    else
      result = vim.system({ vim.o.shell, '-c', cmd }, opts):wait()
    end
    if result.code ~= 0 then error(string.format('%s failed (%s):\n%s%s', title, tostring(result.code), result.stdout or '', result.stderr or '')) end
    return
  end

  vim.cmd('botright ' .. TERM_HEIGHT .. 'split')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, 'runners://' .. title:gsub('%s+', '-'):lower() .. '-' .. buf)

  local opts = { cwd = cwd, env = merge_env(env) }
  if type(cmd) == 'table' then
    vim.fn.termopen(cmd, opts)
  else
    vim.fn.termopen({ vim.o.shell, '-c', cmd }, opts)
  end
  vim.cmd 'startinsert'
end

-- ---------------------------------------------------------------------------
-- npm
-- ---------------------------------------------------------------------------

local function npm_root()
  local root, marker = find_root { 'package.json' }
  if not root then
    vim.notify('Aucun package.json trouvé (remonter depuis le buffer courant)', vim.log.levels.ERROR)
    return nil
  end
  if not has_exe 'npm' then
    vim.notify('npm introuvable dans $PATH', vim.log.levels.ERROR)
    return nil
  end
  return root, marker
end

---@param script string
local function npm_run(script)
  local root = npm_root()
  if not root then return end
  run_in_terminal({ 'npm', 'run', script }, root, 'npm run ' .. script)
end

local function npm_test()
  local root = npm_root()
  if not root then return end
  run_in_terminal({ 'npm', 'test' }, root, 'npm test')
end

---@param marker_path string
---@return table<string, string>
local function read_npm_scripts(marker_path)
  local ok, lines = pcall(vim.fn.readfile, marker_path)
  if not ok or not lines then return {} end
  local decoded = vim.json.decode(table.concat(lines, '\n'))
  if type(decoded) ~= 'table' or type(decoded.scripts) ~= 'table' then return {} end
  return decoded.scripts
end

local function npm_script_picker()
  local root, marker = npm_root()
  if not root or not marker then return end

  local scripts = read_npm_scripts(marker)
  local names = vim.tbl_keys(scripts)
  table.sort(names)
  if #names == 0 then
    vim.notify('Aucun script dans package.json', vim.log.levels.WARN)
    return
  end

  vim.ui.select(names, {
    prompt = 'npm run',
    format_item = function(name)
      local body = scripts[name]
      if type(body) == 'string' and body ~= '' then return string.format('%s  →  %s', name, body) end
      return name
    end,
  }, function(choice)
    if choice then npm_run(choice) end
  end)
end

-- ---------------------------------------------------------------------------
-- Maven (Java / Micronaut)
-- ---------------------------------------------------------------------------

local function maven_root()
  local root, marker = find_root { 'pom.xml' }
  if not root then
    vim.notify('Aucun pom.xml trouvé (remonter depuis le buffer courant)', vim.log.levels.ERROR)
    return nil
  end
  if not has_exe 'mvn' then
    local ensure = require 'custom.ensure_tool'
    local ok, path_or_err = ensure.ensure_maven()
    if not ok then
      vim.notify('mvn introuvable: ' .. tostring(path_or_err), vim.log.levels.ERROR)
      return nil
    end
  end
  return root, marker
end

---@param goals string|string[]
---@param title string|nil
---@param env table<string, string>|nil
local function maven_run(goals, title, env)
  local root = maven_root()
  if not root then return end

  local goal_list = type(goals) == 'table' and goals or vim.split(goals, '%s+', { trimempty = true })
  local cmd = { 'mvn' }
  vim.list_extend(cmd, goal_list)
  run_in_terminal(cmd, root, title or ('mvn ' .. table.concat(goal_list, ' ')), env)
end

---@param pom_path string
---@return boolean
local function pom_has(pom_path, needle)
  local ok, lines = pcall(vim.fn.readfile, pom_path)
  if not ok or not lines then return false end
  return table.concat(lines, '\n'):find(needle, 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- Saved run configs (project-local .nvim/runners.json)
-- ---------------------------------------------------------------------------

---@class RunnerConfig
---@field name string
---@field type string
---@field environments string|nil comma-separated Micronaut envs
---@field config_files string[]|string|nil extra micronaut.config.files
---@field env_file string|nil dotenv path relative to project root
---@field env table<string, string>|nil
---@field jvm_args string|nil
---@field app_args string|nil
---@field goals string[]|nil

---@class RunnersFile
---@field version integer
---@field default string|nil
---@field configs RunnerConfig[]

---@param root string
---@return string
local function runners_path(root) return path_join(root, CONFIG_DIR, CONFIG_FILE) end

---@param root string
---@return RunnersFile
local function load_runners_file(root)
  local path = runners_path(root)
  if vim.fn.filereadable(path) ~= 1 then return { version = 1, configs = {} } end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then return { version = 1, configs = {} } end
  local decoded = vim.json.decode(table.concat(lines, '\n'))
  if type(decoded) ~= 'table' then return { version = 1, configs = {} } end
  if type(decoded.configs) ~= 'table' then decoded.configs = {} end
  decoded.version = decoded.version or 1
  return decoded --[[@as RunnersFile]]
end

---@param root string
---@param data RunnersFile
local function save_runners_file(root, data)
  local dir = path_join(root, CONFIG_DIR)
  if vim.fn.isdirectory(dir) == 0 then vim.fn.mkdir(dir, 'p') end
  local path = runners_path(root)
  local encoded = vim.json.encode(data)
  -- Pretty-print lightly for hand-editing
  local ok_fmt, formatted = pcall(vim.fn.system, { 'python3', '-m', 'json.tool' }, encoded)
  local body = (ok_fmt and vim.v.shell_error == 0 and formatted ~= '' and formatted) or (encoded .. '\n')
  vim.fn.writefile(vim.split(body, '\n', { trimempty = true }), path)
  vim.notify('Configs sauvegardées → ' .. path, vim.log.levels.INFO)
end

---@param root string
---@param env_file string|nil
---@return table<string, string>
local function parse_env_file(root, env_file)
  local env = {}
  if not env_file or env_file == '' then return env end
  local path = env_file
  if not starts_with(path, '/') then path = path_join(root, env_file) end
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify('env_file introuvable : ' .. path, vim.log.levels.WARN)
    return env
  end
  for _, line in ipairs(vim.fn.readfile(path)) do
    local trimmed = vim.trim(line)
    if trimmed ~= '' and not starts_with(trimmed, '#') then
      local key, val = trimmed:match '^([^=]+)=(.*)$'
      if key then
        val = vim.trim(val)
        -- strip optional surrounding quotes
        val = val:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
        env[vim.trim(key)] = val
      end
    end
  end
  return env
end

---@param raw string|nil KEY=val;KEY2=val2 or KEY=val,KEY2=val
---@return table<string, string>
local function parse_env_inline(raw)
  local env = {}
  if not raw or vim.trim(raw) == '' then return env end
  for pair in vim.gsplit(raw, '[;,]') do
    local trimmed = vim.trim(pair)
    if trimmed ~= '' then
      local key, val = trimmed:match '^([^=]+)=(.*)$'
      if key then env[vim.trim(key)] = vim.trim(val) end
    end
  end
  return env
end

---@param root string
---@param cfg RunnerConfig
---@return table<string, string> env
---@return string[] mvn_args extra -D… / -Dmn.jvmArgs=…
local function build_micronaut_env_and_args(root, cfg)
  local env = parse_env_file(root, cfg.env_file)
  for k, v in pairs(cfg.env or {}) do
    env[tostring(k)] = tostring(v)
  end

  local environments = cfg.environments and vim.trim(cfg.environments) or ''
  if environments ~= '' then env.MICRONAUT_ENVIRONMENTS = environments end

  local files = cfg.config_files
  local file_list = {}
  if type(files) == 'string' and files ~= '' then
    file_list = vim.split(files, '%s*,%s*', { trimempty = true })
  elseif type(files) == 'table' then
    for _, f in ipairs(files) do
      if type(f) == 'string' and f ~= '' then table.insert(file_list, f) end
    end
  end
  if #file_list > 0 then
    local abs = {}
    for _, f in ipairs(file_list) do
      if starts_with(f, '/') or starts_with(f, 'classpath:') then
        table.insert(abs, f)
      else
        table.insert(abs, path_join(root, f))
      end
    end
    env.MICRONAUT_CONFIG_FILES = table.concat(abs, ',')
  end

  local mvn_args = {}
  if environments ~= '' then table.insert(mvn_args, '-Dmicronaut.environments=' .. environments) end
  if env.MICRONAUT_CONFIG_FILES then table.insert(mvn_args, '-Dmicronaut.config.files=' .. env.MICRONAUT_CONFIG_FILES) end
  if cfg.jvm_args and vim.trim(cfg.jvm_args) ~= '' then table.insert(mvn_args, '-Dmn.jvmArgs=' .. cfg.jvm_args) end
  if cfg.app_args and vim.trim(cfg.app_args) ~= '' then table.insert(mvn_args, '-Dmn.appArgs=' .. cfg.app_args) end

  return env, mvn_args
end

---@param root string
---@param cfg RunnerConfig
---@return string[] cmd
---@return table<string, string> env
local function build_micronaut_cmd(root, cfg)
  local env, mvn_args = build_micronaut_env_and_args(root, cfg)
  local goals = cfg.goals
  if type(goals) ~= 'table' or #goals == 0 then goals = { 'mn:run' } end
  local cmd = { 'mvn' }
  vim.list_extend(cmd, mvn_args)
  vim.list_extend(cmd, goals)
  return cmd, env
end

---@param root string
---@param cfg RunnerConfig
local function run_micronaut_config(root, cfg)
  local cmd, env = build_micronaut_cmd(root, cfg)
  run_in_terminal(cmd, root, 'micronaut:' .. cfg.name, env)
end

---@param root string
---@param existing RunnerConfig|nil
---@param on_done fun(cfg: RunnerConfig)|nil
local function prompt_micronaut_config(root, existing, on_done)
  existing = existing or { name = '', type = 'micronaut' }

  local function ask(prompt, default, next)
    vim.ui.input({ prompt = prompt, default = default or '' }, function(value)
      if value == nil then return end -- cancelled
      next(vim.trim(value))
    end)
  end

  ask('Nom de la config : ', existing.name ~= '' and existing.name or 'local-dev', function(name)
    if name == '' then
      vim.notify('Nom obligatoire', vim.log.levels.ERROR)
      return
    end
    ask('Micronaut environments (ex: dev,local) : ', existing.environments or 'dev', function(environments)
      local default_files = ''
      if type(existing.config_files) == 'table' then
        default_files = table.concat(existing.config_files, ',')
      elseif type(existing.config_files) == 'string' then
        default_files = existing.config_files
      end
      ask('Fichiers de config (chemins relatifs, séparés par ,) : ', default_files, function(config_files_raw)
        ask('Fichier .env (optionnel, relatif à la racine) : ', existing.env_file or '', function(env_file)
          local default_env = ''
          if type(existing.env) == 'table' then
            local parts = {}
            for k, v in pairs(existing.env) do
              table.insert(parts, k .. '=' .. v)
            end
            table.sort(parts)
            default_env = table.concat(parts, ';')
          end
          ask('Variables env inline KEY=val;KEY2=val (optionnel) : ', default_env, function(env_inline)
            ask('JVM args mn.jvmArgs (optionnel) : ', existing.jvm_args or '', function(jvm_args)
              ask('App args mn.appArgs (optionnel) : ', existing.app_args or '', function(app_args)
                local cfg = {
                  name = name,
                  type = 'micronaut',
                  environments = environments ~= '' and environments or nil,
                  config_files = config_files_raw ~= '' and vim.split(config_files_raw, '%s*,%s*', { trimempty = true }) or nil,
                  env_file = env_file ~= '' and env_file or nil,
                  env = next(parse_env_inline(env_inline)) and parse_env_inline(env_inline) or nil,
                  jvm_args = jvm_args ~= '' and jvm_args or nil,
                  app_args = app_args ~= '' and app_args or nil,
                  goals = { 'mn:run' },
                }

                local data = load_runners_file(root)
                local replaced = false
                for i, c in ipairs(data.configs) do
                  if c.name == cfg.name then
                    data.configs[i] = cfg
                    replaced = true
                    break
                  end
                end
                if not replaced then table.insert(data.configs, cfg) end
                if not data.default then data.default = cfg.name end
                save_runners_file(root, data)

                if on_done then on_done(cfg) end
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

local function micronaut_run_plain()
  local root, pom = maven_root()
  if not root or not pom then return end
  if not pom_has(pom, 'micronaut') then vim.notify('pom.xml sans indice Micronaut — lance quand même `mvn mn:run`', vim.log.levels.WARN) end
  maven_run({ 'mn:run' }, 'mvn mn:run')
end

---Picker : configs sauvegardées + actions.
local function micronaut_picker()
  local root, pom = maven_root()
  if not root or not pom then return end

  local data = load_runners_file(root)
  ---@type { label: string, action: fun() }[]
  local items = {}

  for _, cfg in ipairs(data.configs) do
    if cfg.type == 'micronaut' or cfg.type == nil then
      local mark = (data.default == cfg.name) and '★ ' or '  '
      local detail = {}
      if cfg.environments and cfg.environments ~= '' then table.insert(detail, 'env=' .. cfg.environments) end
      if cfg.config_files then
        local files = type(cfg.config_files) == 'table' and table.concat(cfg.config_files, ',') or tostring(cfg.config_files)
        if files ~= '' then table.insert(detail, 'files=' .. files) end
      end
      if cfg.env_file and cfg.env_file ~= '' then table.insert(detail, 'dotenv=' .. cfg.env_file) end
      local suffix = #detail > 0 and ('  (' .. table.concat(detail, ', ') .. ')') or ''
      table.insert(items, {
        label = mark .. cfg.name .. suffix,
        action = function() run_micronaut_config(root, cfg) end,
      })
    end
  end

  table.insert(items, {
    label = '＋ Nouvelle config Micronaut…',
    action = function()
      prompt_micronaut_config(root, nil, function(cfg) run_micronaut_config(root, cfg) end)
    end,
  })
  table.insert(items, {
    label = '✎ Éditer une config…',
    action = function()
      local editable = {}
      for _, cfg in ipairs(data.configs) do
        if cfg.type == 'micronaut' or cfg.type == nil then table.insert(editable, cfg) end
      end
      if #editable == 0 then
        vim.notify('Aucune config à éditer', vim.log.levels.WARN)
        return
      end
      vim.ui.select(editable, {
        prompt = 'Éditer config',
        format_item = function(c) return c.name end,
      }, function(choice)
        if choice then prompt_micronaut_config(root, choice, nil) end
      end)
    end,
  })
  table.insert(items, {
    label = '▶ mn:run (sans config)',
    action = micronaut_run_plain,
  })
  table.insert(items, {
    label = '📁 Ouvrir .nvim/runners.json',
    action = function()
      local path = runners_path(root)
      if vim.fn.filereadable(path) ~= 1 then save_runners_file(root, { version = 1, configs = {} }) end
      vim.cmd('edit ' .. vim.fn.fnameescape(path))
    end,
  })

  vim.ui.select(items, {
    prompt = 'Micronaut run',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then choice.action() end
  end)
end

local function micronaut_new_or_edit()
  local root = maven_root()
  if not root then return end
  local data = load_runners_file(root)
  local editable = {}
  for _, cfg in ipairs(data.configs) do
    if cfg.type == 'micronaut' or cfg.type == nil then table.insert(editable, cfg) end
  end

  local choices = { { label = '＋ Nouvelle config', cfg = nil } }
  for _, cfg in ipairs(editable) do
    table.insert(choices, { label = '✎ ' .. cfg.name, cfg = cfg })
  end

  vim.ui.select(choices, {
    prompt = 'Créer / éditer config Micronaut',
    format_item = function(c) return c.label end,
  }, function(choice)
    if not choice then return end
    prompt_micronaut_config(root, choice.cfg, nil)
  end)
end

---Java : spring-boot:run si plugin détecté, sinon invite à saisir des goals.
local function java_run()
  local root, pom = maven_root()
  if not root or not pom then return end

  if pom_has(pom, 'spring-boot') then
    maven_run({ 'spring-boot:run' }, 'mvn spring-boot:run')
    return
  end
  if pom_has(pom, 'micronaut') then
    micronaut_picker()
    return
  end

  vim.ui.input({
    prompt = 'mvn goals (ex: compile exec:java) : ',
    default = 'compile',
  }, function(input)
    if input and vim.trim(input) ~= '' then maven_run(vim.trim(input)) end
  end)
end

local function maven_goals_prompt()
  if not maven_root() then return end
  vim.ui.input({
    prompt = 'mvn goals : ',
    default = 'compile',
  }, function(input)
    if input and vim.trim(input) ~= '' then maven_run(vim.trim(input)) end
  end)
end

-- ---------------------------------------------------------------------------
-- Keymaps + user commands
-- ---------------------------------------------------------------------------

vim.keymap.set('n', '<leader>rd', function() npm_run 'dev' end, { desc = '[R]un npm [d]ev' })
vim.keymap.set('n', '<leader>rb', function() npm_run 'build' end, { desc = '[R]un npm [b]uild' })
vim.keymap.set('n', '<leader>rt', npm_test, { desc = '[R]un npm [t]est' })
vim.keymap.set('n', '<leader>rs', npm_script_picker, { desc = '[R]un npm [s]cript (picker)' })

vim.keymap.set('n', '<leader>rc', function() maven_run { 'compile' } end, { desc = '[R]un maven [c]ompile' })
vim.keymap.set('n', '<leader>rp', function() maven_run { 'package' } end, { desc = '[R]un maven [p]ackage' })
vim.keymap.set('n', '<leader>rm', micronaut_picker, { desc = '[R]un [m]icronaut (configs / mn:run)' })
vim.keymap.set('n', '<leader>rM', micronaut_new_or_edit, { desc = '[R]un [M]icronaut config (créer / éditer)' })
vim.keymap.set('n', '<leader>rj', java_run, { desc = '[R]un [j]ava (spring-boot / micronaut / prompt)' })
vim.keymap.set('n', '<leader>rg', maven_goals_prompt, { desc = '[R]un maven [g]oals (prompt)' })

vim.api.nvim_create_user_command('Npm', function(opts)
  local args = vim.trim(opts.args)
  local root = npm_root()
  if not root then return end
  if args == '' then
    npm_script_picker()
  elseif args == 'test' then
    npm_test()
  elseif args:match '^run%s+' then
    run_in_terminal('npm ' .. args, root, 'npm ' .. args)
  else
    npm_run(args)
  end
end, { nargs = '*', desc = 'Run npm script from nearest package.json' })

vim.api.nvim_create_user_command('Maven', function(opts)
  local args = vim.trim(opts.args)
  if args == '' then
    maven_goals_prompt()
  else
    maven_run(args)
  end
end, { nargs = '*', desc = 'Run Maven goals from nearest pom.xml' })

vim.api.nvim_create_user_command('Micronaut', function(opts)
  local root = maven_root()
  if not root then return end
  local name = vim.trim(opts.args)
  if name == '' then
    micronaut_picker()
    return
  end
  local data = load_runners_file(root)
  for _, cfg in ipairs(data.configs) do
    if cfg.name == name then
      run_micronaut_config(root, cfg)
      return
    end
  end
  vim.notify('Config Micronaut inconnue : ' .. name .. ' (voir .nvim/runners.json)', vim.log.levels.ERROR)
end, {
  nargs = '?',
  desc = 'Run saved Micronaut config (or open picker)',
  complete = function(arglead)
    local root = select(1, find_root { 'pom.xml' })
    if not root then return {} end
    local names = {}
    for _, cfg in ipairs(load_runners_file(root).configs) do
      if (cfg.type == 'micronaut' or cfg.type == nil) and starts_with(cfg.name, arglead) then table.insert(names, cfg.name) end
    end
    table.sort(names)
    return names
  end,
})

vim.api.nvim_create_user_command('RunConfig', function() micronaut_new_or_edit() end, { desc = 'Create / edit Micronaut run config' })

-- Exported for unit / integration / e2e tests.
return {
  find_root = find_root,
  has_exe = has_exe,
  merge_env = merge_env,
  npm_root = npm_root,
  maven_root = maven_root,
  read_npm_scripts = read_npm_scripts,
  pom_has = pom_has,
  runners_path = runners_path,
  load_runners_file = load_runners_file,
  save_runners_file = save_runners_file,
  parse_env_file = parse_env_file,
  parse_env_inline = parse_env_inline,
  build_micronaut_env_and_args = build_micronaut_env_and_args,
  build_micronaut_cmd = build_micronaut_cmd,
  run_in_terminal = run_in_terminal,
  maven_run = maven_run,
  npm_run = npm_run,
  npm_test = npm_test,
}
