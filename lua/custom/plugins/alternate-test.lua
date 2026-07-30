-- Toggle source ↔ test (IntelliJ Ctrl+Shift+T).
--
-- Keymap : <leader>t
-- Supports :
--   Java      src/main/java ↔ src/test/java (Foo ↔ FooTest / FooTests / TestFoo / FooIT / …)
--   TS/JS     foo.ts ↔ foo.test.ts / foo.spec.ts / __tests__/…

local M = {}

local JAVA_TEST_SUFFIXES = { 'IntegrationTest', 'Tests', 'Test', 'IT' }

---@param path string
---@return string
local function norm(path) return vim.fs.normalize(path):gsub('\\', '/') end

---@param list string[]
---@return string[]
local function uniq(list)
  local seen, out = {}, {}
  for _, item in ipairs(list) do
    if item and item ~= '' and not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

---@param path string
---@return boolean
function M.is_java(path) return norm(path):match '%.java$' ~= nil end

---@param path string
---@return boolean
function M.is_web(path)
  local p = norm(path)
  return p:match '%.[cm]?[jt]sx?$' ~= nil or p:match '%.[cm]?js$' ~= nil
end

---True when the path looks like a web test file.
---@param path string
---@return boolean
function M.is_web_test(path)
  local p = norm(path)
  local name = vim.fn.fnamemodify(p, ':t')
  if name:find('.test.', 1, true) or name:find('.spec.', 1, true) then return true end
  for segment in p:gmatch '[^/]+' do
    if segment == '__tests__' then return true end
  end
  return false
end

---Strip a known Java test suffix/prefix → possible production class stems.
---@param class_base string basename without .java
---@return string[]
function M.java_source_stems(class_base)
  local stems = {}
  local function add(stem)
    if stem and stem ~= '' and stem ~= class_base then stems[#stems + 1] = stem end
  end
  for _, suf in ipairs(JAVA_TEST_SUFFIXES) do
    if #class_base > #suf and class_base:sub(-#suf) == suf then add(class_base:sub(1, -#suf - 1)) end
  end
  if #class_base > 4 and class_base:sub(1, 4) == 'Test' then add(class_base:sub(5)) end
  if #stems == 0 then stems[1] = class_base end
  return uniq(stems)
end

---Candidate absolute paths for the Java alternate (may or may not exist).
---@param path string
---@return string[]
function M.java_candidates(path)
  path = norm(vim.fn.fnamemodify(path, ':p'))
  local main_marker = 'src/main/java/'
  local test_marker = 'src/test/java/'
  local at_main = path:find(main_marker, 1, true)
  local at_test = path:find(test_marker, 1, true)
  local out = {}

  if at_main then
    local prefix = path:sub(1, at_main - 1)
    local rest = path:sub(at_main + #main_marker)
    local dir = vim.fs.dirname(rest)
    local base = vim.fn.fnamemodify(rest, ':t:r')
    local names = {
      base .. 'Test',
      base .. 'Tests',
      'Test' .. base,
      base .. 'IT',
      base .. 'IntegrationTest',
    }
    for _, name in ipairs(names) do
      local rel = (dir == '.' or dir == '') and (name .. '.java') or (dir .. '/' .. name .. '.java')
      out[#out + 1] = norm(prefix .. test_marker .. rel)
    end
  elseif at_test then
    local prefix = path:sub(1, at_test - 1)
    local rest = path:sub(at_test + #test_marker)
    local dir = vim.fs.dirname(rest)
    local base = vim.fn.fnamemodify(rest, ':t:r')
    for _, stem in ipairs(M.java_source_stems(base)) do
      local rel = (dir == '.' or dir == '') and (stem .. '.java') or (dir .. '/' .. stem .. '.java')
      out[#out + 1] = norm(prefix .. main_marker .. rel)
    end
  end

  return uniq(out)
end

---Candidate absolute paths for the TS/JS alternate (may or may not exist).
---@param path string
---@return string[]
function M.web_candidates(path)
  path = norm(vim.fn.fnamemodify(path, ':p'))
  local dir = vim.fs.dirname(path)
  local name = vim.fn.fnamemodify(path, ':t')
  local base, ext = name:match '^(.*)%.([^.]+)$'
  if not base or not ext then return {} end

  local out = {}
  if M.is_web_test(path) then
    local source_name = name:gsub('%.test%.', '.'):gsub('%.spec%.', '.')
    local parent_of_tests = dir:match '^(.*)/__tests__$'
    if parent_of_tests then
      out[#out + 1] = norm(parent_of_tests .. '/' .. source_name)
      -- __tests__/foo.ts (no .test infix) → ../foo.ts already covered; also try raw name
      if source_name == name then out[#out + 1] = norm(parent_of_tests .. '/' .. name) end
    end
    if source_name ~= name then out[#out + 1] = norm(dir .. '/' .. source_name) end
  else
    out[#out + 1] = norm(dir .. '/' .. base .. '.test.' .. ext)
    out[#out + 1] = norm(dir .. '/' .. base .. '.spec.' .. ext)
    out[#out + 1] = norm(dir .. '/__tests__/' .. name)
    out[#out + 1] = norm(dir .. '/__tests__/' .. base .. '.test.' .. ext)
    out[#out + 1] = norm(dir .. '/__tests__/' .. base .. '.spec.' .. ext)
  end

  return uniq(out)
end

---@param path string
---@return string[]
function M.candidates(path)
  path = path or ''
  if path == '' then return {} end
  if M.is_java(path) then return M.java_candidates(path) end
  if M.is_web(path) then return M.web_candidates(path) end
  return {}
end

---@param paths string[]
---@return string[]
function M.existing(paths)
  local out = {}
  for _, p in ipairs(paths) do
    if vim.fn.filereadable(p) == 1 then out[#out + 1] = p end
  end
  return out
end

---@param path string
local function open_file(path) vim.cmd.edit(vim.fn.fnameescape(path)) end

---Jump to the related test or source file.
---@param path string|nil defaults to current buffer
function M.toggle(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if not path or path == '' then
    vim.notify('Aucun fichier courant', vim.log.levels.WARN)
    return
  end

  local cands = M.candidates(path)
  if #cands == 0 then
    vim.notify('Pas de mapping test↔code pour ce fichier', vim.log.levels.WARN)
    return
  end

  local found = M.existing(cands)
  if #found == 1 then
    open_file(found[1])
    return
  end
  if #found > 1 then
    vim.ui.select(found, { prompt = 'Fichier lié' }, function(choice)
      if choice then open_file(choice) end
    end)
    return
  end

  -- Nothing on disk yet — offer to create one of the candidates (IntelliJ-like).
  vim.ui.select(cands, { prompt = 'Aucun fichier lié — créer ?' }, function(choice)
    if not choice then return end
    vim.fn.mkdir(vim.fn.fnamemodify(choice, ':h'), 'p')
    open_file(choice)
  end)
end

vim.keymap.set('n', '<leader>t', function() M.toggle() end, { desc = 'Toggle source ↔ [T]est' })

vim.api.nvim_create_user_command('AlternateTest', function() M.toggle() end, { desc = 'Toggle between source and test file' })

return M
