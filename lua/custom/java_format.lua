-- Java format style: Eclipse (default) vs Google Java Format.
-- Persists per-project choice in <root>/.nvim/java-format.json (like runners).
--
-- Modes:
--   auto    — Google if detected in the repo, else Eclipse profile
--   eclipse — always Eclipse CodeFormatterProfile (config/formatter/eclipse-java.xml)
--   google  — always google-java-format (Mason)

local M = {}

local CONFIG_DIR = '.nvim'
local CONFIG_FILE = 'java-format.json'
local STYLES = { auto = true, eclipse = true, google = true }

---@param ... string
---@return string
local function path_join(...)
  if vim.fs.joinpath then return vim.fs.joinpath(...) end
  return table.concat({ ... }, '/')
end

---@return string
local function config_root()
  -- Prefer the directory that ships config/formatter/eclipse-java.xml (this repo / nvim config).
  local src = debug.getinfo(1, 'S').source
  if type(src) == 'string' and src:sub(1, 1) == '@' then
    local this_file = src:sub(2)
    -- lua/custom/java_format.lua → repo / config root
    local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(this_file)))
    if vim.uv.fs_stat(path_join(root, 'config', 'formatter', 'eclipse-java.xml')) then return root end
  end
  return vim.fn.stdpath 'config'
end

---Absolute path to the bundled Eclipse formatter XML.
---@return string
function M.eclipse_profile_path()
  return path_join(config_root(), 'config', 'formatter', 'eclipse-java.xml')
end

---Checkstyle Indentation config matching the active style.
---@param style 'eclipse'|'google'
---@return string
function M.checkstyle_config_path(style)
  local name = style == 'google' and 'java-indent-google.xml' or 'java-indent-eclipse.xml'
  return path_join(config_root(), 'config', 'checkstyle', name)
end

---Find Maven / Git project root from a buffer (or cwd).
---@param bufnr integer|nil
---@return string|nil
function M.project_root(bufnr)
  bufnr = bufnr or 0
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  local start = (bufpath ~= '' and vim.fs.dirname(bufpath)) or vim.uv.cwd()
  local found = vim.fs.find({ 'pom.xml', '.git', 'build.gradle', 'build.gradle.kts' }, {
    upward = true,
    path = start,
    limit = 1,
  })
  if #found == 0 then return vim.uv.cwd() end
  return vim.fs.dirname(found[1])
end

---@param root string|nil
---@return string
local function config_path(root)
  root = root or M.project_root()
  return path_join(root, CONFIG_DIR, CONFIG_FILE)
end

---Read preferred style for a project (`auto` if unset).
---@param root string|nil
---@return 'auto'|'eclipse'|'google'
function M.get_preference(root)
  local path = config_path(root)
  local f = io.open(path, 'r')
  if not f then return 'auto' end
  local raw = f:read '*a'
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= 'table' then return 'auto' end
  local style = data.style
  if type(style) == 'string' and STYLES[style] then return style end
  return 'auto'
end

---Persist preferred style for the current project.
---@param style 'auto'|'eclipse'|'google'
---@param root string|nil
---@return boolean ok
---@return string|nil err
function M.set_preference(style, root)
  if not STYLES[style] then return false, 'invalid style: ' .. tostring(style) end
  root = root or M.project_root()
  if not root then return false, 'no project root' end
  local dir = path_join(root, CONFIG_DIR)
  vim.fn.mkdir(dir, 'p')
  local path = config_path(root)
  local payload = vim.json.encode {
    version = 1,
    style = style,
  }
  local f, err = io.open(path, 'w')
  if not f then return false, err end
  f:write(payload)
  f:write '\n'
  f:close()
  return true
end

---Heuristics: does this repo look like it uses Google Java Format?
---@param root string|nil
---@return boolean
---@return string|nil reason
function M.detect_google(root)
  root = root or M.project_root()
  if not root then return false, nil end

  local marker_files = {
    '.google-java-format',
    'google-java-format',
    'eclipse-java-google-style.xml',
  }
  for _, name in ipairs(marker_files) do
    if vim.uv.fs_stat(path_join(root, name)) then return true, name end
  end

  local idea = path_join(root, '.idea', 'codeStyles', 'Project.xml')
  if vim.uv.fs_stat(idea) then
    local f = io.open(idea, 'r')
    if f then
      local raw = f:read '*a'
      f:close()
      if raw and (raw:find('GoogleStyle', 1, true) or raw:find('google%-java%-format') or raw:find('Google Java Format')) then
        return true, '.idea/codeStyles/Project.xml'
      end
    end
  end

  local check_paths = {
    path_join(root, 'pom.xml'),
    path_join(root, 'build.gradle'),
    path_join(root, 'build.gradle.kts'),
  }
  -- Multi-module: also scan immediate child poms lightly via root pom only;
  -- google-java-format is almost always declared at the reactor root.
  for _, pom in ipairs(vim.fn.glob(path_join(root, '*/pom.xml'), true, true)) do
    table.insert(check_paths, pom)
  end

  local needles = {
    'google-java-format',
    'googleJavaFormat',
    'com.google.googlejavaformat',
    'fmt-maven-plugin',
    'spotless',
  }

  for _, path in ipairs(check_paths) do
    local f = io.open(path, 'r')
    if f then
      local raw = f:read '*a'
      f:close()
      if raw then
        for _, needle in ipairs(needles) do
          if raw:find(needle, 1, true) then
            -- spotless alone is weak; require a google-related hint nearby or googleJavaFormat
            if needle == 'spotless' then
              if raw:find('googleJavaFormat', 1, true) or raw:find('google-java-format', 1, true) then
                return true, path
              end
            else
              return true, path
            end
          end
        end
      end
    end
  end

  local google_checks = vim.fs.find({ 'google_checks.xml', 'checkstyle-google.xml' }, {
    path = root,
    limit = 1,
    type = 'file',
  })
  if #google_checks > 0 then return true, google_checks[1] end

  return false, nil
end

---Resolve effective formatter style for a buffer/project.
---@param bufnr integer|nil
---@return 'eclipse'|'google'
---@return 'auto'|'eclipse'|'google' preference
---@return string|nil detect_reason
function M.resolve(bufnr)
  local root = M.project_root(bufnr)
  local preference = M.get_preference(root)
  if preference == 'eclipse' or preference == 'google' then return preference, preference, nil end

  local is_google, reason = M.detect_google(root)
  if is_google then return 'google', preference, reason end
  return 'eclipse', preference, nil
end

---Indent width for Neovim buffer options.
---@param style 'eclipse'|'google'
---@return integer
function M.indent_width(style)
  return style == 'google' and 2 or 4
end

---Apply tab/indent options for Java buffers.
---@param bufnr integer|nil
---@param style 'eclipse'|'google'|nil
function M.apply_buffer_indent(bufnr, style)
  bufnr = bufnr or 0
  if not style then style = select(1, M.resolve(bufnr)) end
  local width = M.indent_width(style)
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = width
  vim.bo[bufnr].shiftwidth = width
  vim.bo[bufnr].softtabstop = width
end

---Point nvim-lint checkstyle at the matching Indentation config.
---@param style 'eclipse'|'google'|nil
function M.apply_checkstyle(style)
  if not style then style = select(1, M.resolve()) end
  local ok, lint = pcall(require, 'lint')
  if not ok or not lint.linters or not lint.linters.checkstyle then return end
  lint.linters.checkstyle.config_file = M.checkstyle_config_path(style)
end

---Conform formatters list for Java (empty → jdtls / Eclipse LSP format).
---@param bufnr integer|nil
---@return string[]
function M.conform_formatters(bufnr)
  local style = select(1, M.resolve(bufnr))
  if style == 'google' then return { 'google-java-format' } end
  return {}
end

---jdtls settings fragment for the Eclipse profile (always registered; used when conform falls back to LSP).
---@return table
function M.jdtls_format_settings()
  return {
    enabled = true,
    settings = {
      url = M.eclipse_profile_path(),
      profile = 'Default',
    },
  }
end

---Human-readable status line for notifications / picker.
---@param bufnr integer|nil
---@return string
function M.status_line(bufnr)
  local effective, preference, reason = M.resolve(bufnr)
  local parts = {
    string.format('préférence=%s', preference),
    string.format('effectif=%s', effective),
  }
  if preference == 'auto' and reason then table.insert(parts, 'détecté=' .. reason) end
  return table.concat(parts, ' · ')
end

M.STYLES = { 'auto', 'eclipse', 'google' }

return M
