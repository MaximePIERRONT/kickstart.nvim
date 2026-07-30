-- Toggle between source and test files (IntelliJ Ctrl+Shift+T style).

local M = {}

local SEP = package.config:sub(1, 1)

---@param path string
---@return string
local function abs(path) return vim.fn.fnamemodify(path, ':p') end

---@param path string
---@return boolean
local function readable(path) return vim.fn.filereadable(path) == 1 end

---@param candidates string[]
---@return string[]
local function existing(candidates)
  local out = {}
  for _, p in ipairs(candidates) do
    if readable(p) then table.insert(out, vim.fs.normalize(p)) end
  end
  return out
end

---@param path string
---@return string[] candidates (may be empty)
function M.java_alternates(path)
  local full = abs(path)
  for _, kind in ipairs { 'main', 'test' } do
    local marker = 'src' .. SEP .. kind .. SEP .. 'java' .. SEP
    local at = full:find(marker, 1, true)
    if not at then goto continue end

    local module_root = full:sub(1, at - 1)
    local relative = full:sub(at + #marker)
    if not relative:match '%.java$' then return {} end

    local pkg_dir = relative:match('^(.*)' .. SEP .. '[^' .. SEP .. ']+%.java$') or ''
    local class_file = relative:match('([^' .. SEP .. ']+)%.java$')
    if not class_file then return {} end

    local base = class_file:gsub('%.java$', '')
    local pkg_prefix = pkg_dir ~= '' and pkg_dir .. SEP or ''

    if kind == 'main' then
      local test_root = module_root .. 'src' .. SEP .. 'test' .. SEP .. 'java' .. SEP .. pkg_prefix
      return existing {
        test_root .. base .. 'Test.java',
        test_root .. base .. 'Tests.java',
        test_root .. base .. 'IT.java',
        test_root .. 'IT' .. base .. '.java',
      }
    end

    local source_base = base
    if base:match 'Tests$' then
      source_base = base:gsub('Tests$', '')
    elseif base:match 'Test$' then
      source_base = base:gsub('Test$', '')
    elseif base:match '^IT' then
      source_base = base:gsub('^IT', '')
    elseif base:match 'IT$' then
      source_base = base:gsub('IT$', '')
    end

    local main_root = module_root .. 'src' .. SEP .. 'main' .. SEP .. 'java' .. SEP .. pkg_prefix
    return existing { main_root .. source_base .. '.java' }
    ::continue::
  end
  return {}
end

---@param stem string
---@return string source_stem
local function web_test_to_source_stem(stem)
  if stem:match '%.test$' then return stem:gsub('%.test$', '') end
  if stem:match '%.spec$' then return stem:gsub('%.spec$', '') end
  return stem
end

---@param dir string directory containing the file (no trailing sep)
---@param stem string filename without extension
---@param ext string leading-dot extension (e.g. ".ts")
---@return string[]
local function web_source_candidates(dir, stem, ext)
  local out = {}
  local test_suffixes = { '.test', '.spec' }
  local test_exts = { ext }
  if ext == '.vue' then
    test_exts = { '.ts', '.tsx', '.js', '.jsx' }
  elseif ext == '.ts' or ext == '.tsx' then
    table.insert(test_exts, '.js')
    table.insert(test_exts, '.jsx')
  elseif ext == '.js' or ext == '.jsx' then
    table.insert(test_exts, '.ts')
    table.insert(test_exts, '.tsx')
  end

  for _, sfx in ipairs(test_suffixes) do
    for _, te in ipairs(test_exts) do
      table.insert(out, dir .. SEP .. stem .. sfx .. te)
      table.insert(out, dir .. SEP .. '__tests__' .. SEP .. stem .. sfx .. te)
      table.insert(out, dir .. SEP .. '__tests__' .. SEP .. stem .. te)
    end
  end
  return out
end

---@param path string
---@return string[] candidates
function M.web_alternates(path)
  local full = abs(path)
  local dir = vim.fs.dirname(full)
  local fname = vim.fn.fnamemodify(full, ':t')
  local ext = vim.fn.fnamemodify(full, ':e')
  if ext == '' then return {} end
  local dotted = '.' .. ext

  local tests_dir = SEP .. '__tests__' .. SEP
  local in_tests = dir:find(tests_dir, 1, true)
  if in_tests then
    local parent = dir:sub(1, in_tests - 1)
    local stem = fname:gsub('%.' .. ext .. '$', '')
    local source_stem = web_test_to_source_stem(stem)
    return existing {
      parent .. SEP .. source_stem .. dotted,
      parent .. SEP .. source_stem .. '.ts',
      parent .. SEP .. source_stem .. '.js',
      parent .. SEP .. source_stem .. '.vue',
    }
  end

  local stem = fname:gsub('%.' .. ext .. '$', '')
  if stem:match '%.test$' or stem:match '%.spec$' then
    local source_stem = web_test_to_source_stem(stem)
    return existing {
      dir .. SEP .. source_stem .. dotted,
      dir .. SEP .. source_stem .. '.ts',
      dir .. SEP .. source_stem .. '.js',
      dir .. SEP .. source_stem .. '.vue',
    }
  end

  return existing(web_source_candidates(dir, stem, dotted))
end

---@param path string|nil
---@return string[]
function M.alternates(path)
  path = path or vim.api.nvim_buf_get_name(0)
  if path == '' then return {} end

  local ext = vim.fn.fnamemodify(path, ':e'):lower()
  if ext == 'java' then return M.java_alternates(path) end
  if ext == 'ts' or ext == 'tsx' or ext == 'js' or ext == 'jsx' or ext == 'vue' or ext == 'mjs' or ext == 'cjs' then
    return M.web_alternates(path)
  end
  return {}
end

---Open path in the current window (reuse buffer if already open).
---@param path string
local function open(path)
  local norm = vim.fs.normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == norm then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == buf then
          vim.api.nvim_set_current_win(win)
          return
        end
      end
      vim.api.nvim_set_current_buf(buf)
      return
    end
  end
  vim.cmd.edit(norm)
end

---Toggle or pick among source/test alternates.
function M.toggle()
  local current = vim.api.nvim_buf_get_name(0)
  if current == '' or vim.bo.buftype ~= '' then
    vim.notify('Aucun fichier sur le buffer courant', vim.log.levels.WARN)
    return
  end

  local candidates = M.alternates(current)
  if #candidates == 0 then
    vim.notify('Aucun fichier test/source correspondant trouvé', vim.log.levels.WARN)
    return
  end

  local norm_current = vim.fs.normalize(abs(current))
  local filtered = vim.tbl_filter(function(p) return vim.fs.normalize(p) ~= norm_current end, candidates)

  if #filtered == 0 then filtered = candidates end

  if #filtered == 1 then
    open(filtered[1])
    return
  end

  vim.ui.select(filtered, {
    prompt = 'Source / test',
    format_item = function(item) return vim.fn.fnamemodify(item, ':~:.') end,
  }, function(choice)
    if choice then open(choice) end
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('TestAlternate', function() M.toggle() end, { desc = 'Toggle between source and test file' })
  vim.api.nvim_create_user_command('GoToTest', function() M.toggle() end, { desc = 'Toggle between source and test file (alias)' })
end

return M
