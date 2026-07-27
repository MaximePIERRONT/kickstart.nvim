-- Maven test runners (roadmap P2) — minimal, no neotest.
--
-- Keymaps (<leader>j = [J]ava test) :
--   jt  test current [t]ype / class   → mvn test -Dtest=com.example.FooTest
--   jm  test [m]ethod under cursor    → mvn test -Dtest=com.example.FooTest#bar
--   ja  test [a]ll in module          → mvn test
--
-- Requires `mvn` on $PATH. Uses the nearest pom.xml (multi-module friendly).

local M = {}

local TERM_HEIGHT = 15

---@param markers string[]
---@param start_path string|nil
---@return string|nil
function M.find_root(markers, start_path)
  local start = start_path
  if not start then
    local bufpath = vim.api.nvim_buf_get_name(0)
    start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or vim.uv.cwd()
  end
  local found = vim.fs.find(markers, { upward = true, path = start, limit = 1 })
  if #found == 0 then return nil end
  return vim.fs.dirname(found[1])
end

---@param start_path string|nil
---@return string|nil
function M.maven_root(start_path)
  local root = M.find_root({ 'pom.xml' }, start_path)
  if not root then return nil end
  if vim.fn.executable 'mvn' ~= 1 then return nil end
  return root
end

---Walk up from a module pom directory to the top-most aggregator pom (reactor).
---@param module_root string
---@return string reactor_root
function M.reactor_root(module_root)
  local current = module_root
  local top = module_root
  while true do
    local parent = vim.fs.dirname(current)
    if not parent or parent == current then break end
    local parent_pom = vim.fs.joinpath(parent, 'pom.xml')
    if vim.fn.filereadable(parent_pom) ~= 1 then break end
    top = parent
    current = parent
  end
  return top
end

---@param pom_dir string
---@return string|nil
function M.artifact_id(pom_dir)
  local pom = vim.fs.joinpath(pom_dir, 'pom.xml')
  if vim.fn.filereadable(pom) ~= 1 then return nil end
  local ok, lines = pcall(vim.fn.readfile, pom)
  if not ok or not lines then return nil end
  local text = table.concat(lines, '\n')
  -- Prefer the project artifactId (first after optional parent block).
  local after_parent = text:gsub('<parent>.-</parent>', '', 1)
  return after_parent:match '<artifactId>%s*([^<]-)%s*</artifactId>'
end

---@param cmd string[]
---@param cwd string
---@param title string
local function run_in_terminal(cmd, cwd, title)
  vim.notify(string.format('%s → %s', title, table.concat(cmd, ' ')), vim.log.levels.INFO)
  -- Headless CI / -es scripts: run synchronously instead of opening a terminal UI.
  if vim.fn.has 'nvim' == 1 and #vim.api.nvim_list_uis() == 0 then
    local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then error(string.format('%s failed (%s):\n%s%s', title, tostring(result.code), result.stdout or '', result.stderr or '')) end
    return
  end

  vim.cmd('botright ' .. TERM_HEIGHT .. 'split')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, 'maven-tests://' .. title:gsub('%s+', '-'):lower() .. '-' .. buf)
  vim.fn.termopen(cmd, { cwd = cwd })
  vim.cmd 'startinsert'
end

---FQCN from src/test/java/... (or src/main/java/...), else file basename.
---@param bufpath string
---@return string
function M.class_name(bufpath)
  local abs = vim.fn.fnamemodify(bufpath, ':p')
  local sep = package.config:sub(1, 1)
  for _, kind in ipairs { 'test', 'main' } do
    local marker = 'src' .. sep .. kind .. sep .. 'java' .. sep
    local at = abs:find(marker, 1, true)
    if at then
      local relative = abs:sub(at + #marker)
      if relative:match '%.java$' then return relative:gsub('%.java$', ''):gsub(sep, '.') end
    end
  end
  return vim.fn.fnamemodify(bufpath, ':t:r')
end

---@param text string
---@return boolean
local function is_test_annotation(text) return text == 'Test' or text == 'ParameterizedTest' or text == 'RepeatedTest' end

---Collect @Test / @ParameterizedTest / @RepeatedTest methods via treesitter.
---@param bufnr integer
---@return { name: string, start_row: integer, end_row: integer }[]
function M.list_test_methods(bufnr)
  local methods = {}
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'java')
  if not ok or not parser then return methods end

  local trees = parser:parse()
  if not trees or not trees[1] then return methods end

  local query_ok, query = pcall(
    vim.treesitter.query.parse,
    'java',
    [[
      (method_declaration
        (modifiers
          [
            (marker_annotation name: (identifier) @ann)
            (annotation name: (identifier) @ann)
          ])
        name: (identifier) @method_name) @method
    ]]
  )
  if not query_ok then return methods end

  local root = trees[1]:root()
  for _, match in query:iter_matches(root, bufnr, 0, -1) do
    local ann_text, method_name, method_node
    for id, nodes in pairs(match) do
      local cap = query.captures[id]
      local node = type(nodes) == 'table' and nodes[1] or nodes
      if node then
        if cap == 'ann' then
          ann_text = vim.treesitter.get_node_text(node, bufnr)
        elseif cap == 'method_name' then
          method_name = vim.treesitter.get_node_text(node, bufnr)
        elseif cap == 'method' then
          method_node = node
        end
      end
    end
    if ann_text and is_test_annotation(ann_text) and method_name and method_node then
      local start_row, _, end_row = method_node:range()
      table.insert(methods, { name = method_name, start_row = start_row, end_row = end_row })
    end
  end
  return methods
end

---Method under cursor: containing / nearest @Test method, else <cword>.
---@param bufnr integer
---@return string|nil
function M.method_under_cursor(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local methods = M.list_test_methods(bufnr)

  for _, m in ipairs(methods) do
    if row >= m.start_row and row <= m.end_row then return m.name end
  end

  local best
  for _, m in ipairs(methods) do
    if m.start_row <= row and (not best or m.start_row > best.start_row) then best = m end
  end
  if best then return best.name end

  local word = vim.fn.expand '<cword>'
  if word ~= '' then return word end
  return nil
end

---@param mode 'all'|'class'|'method'
---@param bufpath string|nil
---@param method string|nil
---@return string[]|nil args
---@return string|nil cwd
---@return string|nil err
function M.build_mvn_test_cmd(mode, bufpath, method)
  bufpath = bufpath or vim.api.nvim_buf_get_name(0)
  local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or nil
  local module_root = M.maven_root(start)
  if not module_root then return nil, nil, 'maven root / mvn missing' end

  local reactor = M.reactor_root(module_root)
  local artifact = M.artifact_id(module_root)
  if not artifact then return nil, nil, 'unable to read artifactId from module pom' end

  -- Multi-module friendly: always run from reactor with -pl/-am so sibling deps resolve.
  local cmd = {
    'mvn',
    '-pl',
    ':' .. artifact,
    '-am',
    'test',
  }

  if mode == 'all' then return cmd, reactor, nil end

  if bufpath == '' or not bufpath:match '%.java$' then return nil, nil, 'not a java file' end
  local fqcn = M.class_name(bufpath)
  if mode == 'class' then
    vim.list_extend(cmd, { '-Dtest=' .. fqcn, '-Dsurefire.failIfNoSpecifiedTests=false' })
    return cmd, reactor, nil
  end
  if mode == 'method' then
    method = method or M.method_under_cursor(vim.api.nvim_get_current_buf())
    if not method then return nil, nil, 'no test method' end
    vim.list_extend(cmd, { '-Dtest=' .. fqcn .. '#' .. method, '-Dsurefire.failIfNoSpecifiedTests=false' })
    return cmd, reactor, nil
  end
  return nil, nil, 'unknown mode'
end

local function run_class()
  local cmd, root, err = M.build_mvn_test_cmd 'class'
  if not cmd then
    vim.notify(err or 'unable to build mvn test class command', vim.log.levels.WARN)
    return
  end
  run_in_terminal(cmd, root, 'mvn test class')
end

local function run_method()
  local cmd, root, err = M.build_mvn_test_cmd 'method'
  if not cmd then
    vim.notify(err or 'unable to build mvn test method command', vim.log.levels.WARN)
    return
  end
  run_in_terminal(cmd, root, 'mvn test method')
end

local function run_all()
  local cmd, root, err = M.build_mvn_test_cmd 'all'
  if not cmd then
    vim.notify(err or 'unable to build mvn test all command', vim.log.levels.ERROR)
    return
  end
  run_in_terminal(cmd, root, 'mvn test all')
end

vim.keymap.set('n', '<leader>jt', run_class, { desc = '[J]ava [t]est class' })
vim.keymap.set('n', '<leader>jm', run_method, { desc = '[J]ava test [m]ethod' })
vim.keymap.set('n', '<leader>ja', run_all, { desc = '[J]ava test [a]ll' })

vim.api.nvim_create_user_command('MavenTest', function(opts)
  local arg = opts.args
  if arg == '' or arg == 'all' then
    run_all()
  elseif arg == 'class' then
    run_class()
  elseif arg == 'method' then
    run_method()
  else
    local cmd, root, err = M.build_mvn_test_cmd 'class'
    -- Reuse module/reactor resolution, then override -Dtest pattern.
    local bufpath = vim.api.nvim_buf_get_name(0)
    local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or nil
    local module_root = M.maven_root(start)
    if not module_root then
      vim.notify('Aucun pom.xml / mvn introuvable', vim.log.levels.ERROR)
      return
    end
    local reactor = M.reactor_root(module_root)
    local artifact = M.artifact_id(module_root)
    if not artifact then
      vim.notify(err or 'artifactId introuvable', vim.log.levels.ERROR)
      return
    end
    run_in_terminal({
      'mvn',
      '-pl',
      ':' .. artifact,
      '-am',
      'test',
      '-Dtest=' .. arg,
      '-Dsurefire.failIfNoSpecifiedTests=false',
    }, reactor, 'mvn test ' .. arg)
  end
end, {
  nargs = '?',
  complete = function() return { 'all', 'class', 'method' } end,
  desc = 'Run Maven tests (all|class|method|<pattern>)',
})

return M
