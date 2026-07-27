-- Maven test runners (roadmap P2) — minimal, no neotest.
--
-- Keymaps (<leader>j = [J]ava test) :
--   jt  test current [t]ype / class   → mvn test -Dtest=com.example.FooTest
--   jm  test [m]ethod under cursor    → mvn test -Dtest=com.example.FooTest#bar
--   ja  test [a]ll in module          → mvn test
--
-- Requires `mvn` on $PATH. Uses the nearest pom.xml (multi-module friendly).

local TERM_HEIGHT = 15

---@param markers string[]
---@return string|nil
local function find_root(markers)
  local bufpath = vim.api.nvim_buf_get_name(0)
  local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or vim.uv.cwd()
  local found = vim.fs.find(markers, { upward = true, path = start, limit = 1 })
  if #found == 0 then return nil end
  return vim.fs.dirname(found[1])
end

---@return string|nil
local function maven_root()
  local root = find_root { 'pom.xml' }
  if not root then
    vim.notify('Aucun pom.xml trouvé (remonter depuis le buffer courant)', vim.log.levels.ERROR)
    return nil
  end
  if vim.fn.executable 'mvn' ~= 1 then
    vim.notify('mvn introuvable dans $PATH', vim.log.levels.ERROR)
    return nil
  end
  return root
end

---@param cmd string[]
---@param cwd string
---@param title string
local function run_in_terminal(cmd, cwd, title)
  vim.notify(string.format('%s → %s', title, table.concat(cmd, ' ')), vim.log.levels.INFO)
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
local function class_name(bufpath)
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
local function list_test_methods(bufnr)
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
local function method_under_cursor(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local methods = list_test_methods(bufnr)

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

local function run_class()
  local root = maven_root()
  if not root then return end
  local bufpath = vim.api.nvim_buf_get_name(0)
  if bufpath == '' or not bufpath:match '%.java$' then
    vim.notify('Ouvre un fichier .java pour lancer la classe de test', vim.log.levels.WARN)
    return
  end
  local fqcn = class_name(bufpath)
  run_in_terminal({ 'mvn', 'test', '-Dtest=' .. fqcn }, root, 'mvn test class')
end

local function run_method()
  local root = maven_root()
  if not root then return end
  local bufnr = vim.api.nvim_get_current_buf()
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  if bufpath == '' or not bufpath:match '%.java$' then
    vim.notify('Ouvre un fichier .java pour lancer la méthode de test', vim.log.levels.WARN)
    return
  end
  local method = method_under_cursor(bufnr)
  if not method then
    vim.notify('Aucune méthode de test sous le curseur', vim.log.levels.WARN)
    return
  end
  local fqcn = class_name(bufpath)
  run_in_terminal({ 'mvn', 'test', '-Dtest=' .. fqcn .. '#' .. method }, root, 'mvn test method')
end

local function run_all()
  local root = maven_root()
  if not root then return end
  run_in_terminal({ 'mvn', 'test' }, root, 'mvn test all')
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
    local root = maven_root()
    if not root then return end
    run_in_terminal({ 'mvn', 'test', '-Dtest=' .. arg }, root, 'mvn test ' .. arg)
  end
end, {
  nargs = '?',
  complete = function() return { 'all', 'class', 'method' } end,
  desc = 'Run Maven tests (all|class|method|<pattern>)',
})
