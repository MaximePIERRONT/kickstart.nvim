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
--   rm  micronaut [m]n:run
--   rj  [j]ava run (spring-boot:run si détecté, sinon prompt)
--   rg  maven [g]oals (prompt libre)

local TERM_HEIGHT = 15

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

---@param cmd string|string[]
---@param cwd string
---@param title string
local function run_in_terminal(cmd, cwd, title)
  local cmd_str = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd
  vim.notify(string.format('%s → %s', title, cmd_str), vim.log.levels.INFO)

  vim.cmd('botright ' .. TERM_HEIGHT .. 'split')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, 'runners://' .. title:gsub('%s+', '-'):lower() .. '-' .. buf)

  local opts = { cwd = cwd }
  if type(cmd) == 'table' then
    vim.fn.termopen(cmd, opts)
  else
    -- shell form keeps npm scripts with spaces / args simple
    vim.fn.termopen({ vim.o.shell, '-c', cmd }, opts)
  end
  vim.cmd 'startinsert'
end

---@param exe string
---@return boolean
local function has_exe(exe) return vim.fn.executable(exe) == 1 end

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
  -- `npm test` (lifecycle) plutôt que `npm run test` — plus idiomatique
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
    vim.notify('mvn introuvable dans $PATH', vim.log.levels.ERROR)
    return nil
  end
  return root, marker
end

---@param goals string|string[]
---@param title string|nil
local function maven_run(goals, title)
  local root = maven_root()
  if not root then return end

  local goal_list
  if type(goals) == 'table' then
    goal_list = goals
  else
    goal_list = vim.split(goals, '%s+', { trimempty = true })
  end

  local cmd = { 'mvn' }
  vim.list_extend(cmd, goal_list)
  run_in_terminal(cmd, root, title or ('mvn ' .. table.concat(goal_list, ' ')))
end

---@param pom_path string
---@return boolean
local function pom_has(pom_path, needle)
  local ok, lines = pcall(vim.fn.readfile, pom_path)
  if not ok or not lines then return false end
  return table.concat(lines, '\n'):find(needle, 1, true) ~= nil
end

---Micronaut : goal officiel du micronaut-maven-plugin.
local function micronaut_run()
  local root, pom = maven_root()
  if not root or not pom then return end
  if not pom_has(pom, 'micronaut') then vim.notify('pom.xml sans indice Micronaut — lance quand même `mvn mn:run`', vim.log.levels.WARN) end
  maven_run({ 'mn:run' }, 'mvn mn:run')
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
    maven_run({ 'mn:run' }, 'mvn mn:run')
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
vim.keymap.set('n', '<leader>rm', micronaut_run, { desc = '[R]un [m]icronaut (mvn mn:run)' })
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
    -- :Npm dev → npm run dev
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
