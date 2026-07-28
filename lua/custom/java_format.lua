--- Java formatting: Eclipse profile (jdtls) by default, Google Java Format on demand.
---
--- Commands (IntelliJ-like):
---   :JavaFormat            — default formatter for this buffer
---   :JavaFormat eclipse    — force Eclipse / jdtls
---   :JavaFormat google     — force google-java-format
---   :JavaFormat picker     — choose formatter interactively
---
--- Keymaps (Java buffers):
---   <leader>f   — default format (via conform wrapper in init.lua)
---   <leader>fE  — Eclipse
---   <leader>fG  — Google
---   <leader>fJ  — picker
local M = {}

local BUNDLED_PROFILE_DIR = vim.fs.joinpath(vim.fn.stdpath 'config', 'config', 'eclipse-formatter')
local BUNDLED_PROFILE_PATH = vim.fs.joinpath(BUNDLED_PROFILE_DIR, 'Default.xml')
local BUNDLED_PROFILE_NAME = 'Default'

local PROJECT_ROOT_MARKERS = { '.git', 'mvnw', 'pom.xml', 'build.gradle', 'settings.gradle', 'gradlew' }

local PROJECT_ECLIPSE_CANDIDATES = {
  'eclipse-formatter.xml',
  '.eclipse-formatter.xml',
  'config/eclipse-formatter/Default.xml',
  'config/eclipse-formatter/java.xml',
}

local GOOGLE_FORMAT_MARKERS = {
  '.google-java-format',
  '.google-java-format.json',
}

---@param path string
---@return boolean
local function file_exists(path)
  return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

---@param bufnr? integer
---@return string|nil
local function project_root(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return nil end
  return vim.fs.root(name, PROJECT_ROOT_MARKERS)
end

---@param xml_path string
---@return string|nil
local function profile_name_from_xml(xml_path)
  local lines = vim.fn.readfile(xml_path)
  for _, line in ipairs(lines) do
    local name = line:match('<profile[^>]-name="([^"]+)"')
    if name then return name end
  end
  return nil
end

---@param dir string
---@return string|nil, string|nil
local function first_xml_in_dir(dir)
  if not file_exists(dir) then return nil, nil end
  for file_name, type in vim.fs.dir(dir) do
    if (type == 'file' or type == 'link') and file_name:match '%.xml$' then
      local path = vim.fs.joinpath(dir, file_name)
      return path, profile_name_from_xml(path) or BUNDLED_PROFILE_NAME
    end
  end
  return nil, nil
end

---Bundled kickstart Eclipse formatter profile.
---@return { path: string, name: string }|nil
function M.bundled_eclipse_profile()
  if not file_exists(BUNDLED_PROFILE_PATH) then return nil end
  return {
    path = BUNDLED_PROFILE_PATH,
    name = profile_name_from_xml(BUNDLED_PROFILE_PATH) or BUNDLED_PROFILE_NAME,
  }
end

---Project-local Eclipse formatter profile, if any.
---@param bufnr? integer
---@return { path: string, name: string }|nil
function M.project_eclipse_profile(bufnr)
  local root = project_root(bufnr)
  if not root then return nil end

  for _, relative in ipairs(PROJECT_ECLIPSE_CANDIDATES) do
    local path = vim.fs.joinpath(root, relative)
    if file_exists(path) then
      return {
        path = path,
        name = profile_name_from_xml(path) or BUNDLED_PROFILE_NAME,
      }
    end
  end

  local dir_path, dir_name = first_xml_in_dir(vim.fs.joinpath(root, 'config', 'eclipse-formatter'))
  if dir_path then
    return { path = dir_path, name = dir_name or BUNDLED_PROFILE_NAME }
  end

  return nil
end

---Best Eclipse profile for a buffer: project overrides bundled config.
---@param bufnr? integer
---@return { path: string, name: string }|nil
function M.resolve_eclipse_profile(bufnr)
  return M.project_eclipse_profile(bufnr) or M.bundled_eclipse_profile()
end

---@param bufnr? integer
---@return boolean
function M.has_eclipse_profile(bufnr)
  return M.resolve_eclipse_profile(bufnr) ~= nil
end

---Detect Google Java Format configuration in the project tree.
---@param bufnr? integer
---@return boolean
function M.has_google_format_config(bufnr)
  local root = project_root(bufnr)
  if not root then return false end

  for _, marker in ipairs(GOOGLE_FORMAT_MARKERS) do
    if file_exists(vim.fs.joinpath(root, marker)) then return true end
  end

  local pom = vim.fs.joinpath(root, 'pom.xml')
  if file_exists(pom) then
    local content = table.concat(vim.fn.readfile(pom), '\n')
    if content:find 'google%-java%-format' or content:find 'spotless' then return true end
  end

  local build_gradle = vim.fs.joinpath(root, 'build.gradle')
  if file_exists(build_gradle) then
    local content = table.concat(vim.fn.readfile(build_gradle), '\n')
    if content:find 'googleJavaFormat' or content:find 'google%-java%-format' or content:find 'spotless' then return true end
  end

  return false
end

---Default formatter id: `eclipse` when a profile exists (even if Google config is present), else `google`.
---@param bufnr? integer
---@return 'eclipse'|'google'
function M.default_formatter(bufnr)
  if M.has_eclipse_profile(bufnr) then return 'eclipse' end
  return 'google'
end

---Effective formatter for a buffer (buffer override > default).
---@param bufnr? integer
---@return 'eclipse'|'google'
function M.effective_formatter(bufnr)
  bufnr = bufnr or 0
  local override = vim.b[bufnr].kickstart_java_formatter
  if override == 'eclipse' or override == 'google' then return override end
  return M.default_formatter(bufnr)
end

---jdtls `settings.java.format` table for the resolved Eclipse profile.
---@param bufnr? integer
---@return table|nil
function M.jdtls_format_settings(bufnr)
  local profile = M.resolve_eclipse_profile(bufnr)
  if not profile then return nil end
  return {
    java = {
      format = {
        enabled = true,
        settings = {
          url = vim.uri_from_fname(profile.path),
          profile = profile.name,
        },
      },
    },
  }
end

---conform.nvim `formatters_by_ft.java` entry.
---@return table
function M.conform_java_formatters()
  if M.bundled_eclipse_profile() then
    return { lsp_format = 'prefer' }
  end
  return { 'google-java-format' }
end

---@param formatter 'eclipse'|'google'
---@param bufnr? integer
---@return table
local function conform_opts_for(formatter, bufnr)
  bufnr = bufnr or 0
  if formatter == 'google' then
    return {
      bufnr = bufnr,
      async = true,
      formatters = { 'google-java-format' },
      lsp_format = 'never',
    }
  end

  return {
    bufnr = bufnr,
    async = true,
    lsp_format = 'prefer',
    filter = function(client) return client.name == 'jdtls' end,
  }
end

---@class JavaFormatOpts
---@field formatter? 'eclipse'|'google'|'default'
---@field async? boolean
---@field bufnr? integer
---@field set_buffer_default? boolean

---Format the current (or given) Java buffer.
---@param opts? JavaFormatOpts
function M.format(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'java' then
    vim.notify('JavaFormat: not a Java buffer', vim.log.levels.WARN)
    return
  end

  local formatter = opts.formatter or 'default'
  if formatter == 'default' then formatter = M.effective_formatter(bufnr) end

  if opts.set_buffer_default then vim.b[bufnr].kickstart_java_formatter = formatter end

  local conform_opts = conform_opts_for(formatter, bufnr)
  conform_opts.async = opts.async ~= false
  require('conform').format(conform_opts)
end

function M.show_picker()
  local bufnr = vim.api.nvim_get_current_buf()
  local default_fmt = M.default_formatter(bufnr)
  local google_hint = M.has_google_format_config(bufnr) and ' (project config detected)' or ''
  local eclipse_hint = M.has_eclipse_profile(bufnr) and ' (default)' or ''

  local choices = {
  {
    label = 'Eclipse formatter (jdtls)' .. eclipse_hint,
    value = 'eclipse',
  },
  {
    label = 'Google Java Format' .. google_hint,
    value = 'google',
  },
  {
    label = 'Use project default (' .. default_fmt .. ')',
    value = 'default',
  },
  {
    label = 'Set buffer default → Eclipse',
    value = 'set_eclipse',
  },
  {
    label = 'Set buffer default → Google',
    value = 'set_google',
  },
  {
    label = 'Clear buffer override',
    value = 'clear',
  },
  }

  vim.ui.select(choices, {
    prompt = 'Java formatter',
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    if choice.value == 'set_eclipse' then
      vim.b[bufnr].kickstart_java_formatter = 'eclipse'
      vim.notify('Java formatter for this buffer: Eclipse', vim.log.levels.INFO)
      return
    end
    if choice.value == 'set_google' then
      vim.b[bufnr].kickstart_java_formatter = 'google'
      vim.notify('Java formatter for this buffer: Google', vim.log.levels.INFO)
      return
    end
    if choice.value == 'clear' then
      vim.b[bufnr].kickstart_java_formatter = nil
      vim.notify('Java buffer formatter override cleared', vim.log.levels.INFO)
      return
    end
    M.format { formatter = choice.value, bufnr = bufnr }
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('JavaFormat', function(args)
    local arg = vim.trim(args.args)
    if arg == '' or arg == 'default' then
      M.format { formatter = 'default' }
    elseif arg == 'eclipse' then
      M.format { formatter = 'eclipse' }
    elseif arg == 'google' then
      M.format { formatter = 'google' }
    elseif arg == 'picker' or arg == 'select' then
      M.show_picker()
    else
      vim.notify('Usage: :JavaFormat [eclipse|google|picker|default]', vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'eclipse', 'google', 'picker', 'default' }
    end,
    desc = 'Format Java with Eclipse (default) or Google Java Format',
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'java',
    group = vim.api.nvim_create_augroup('kickstart-java-format-keymaps', { clear = true }),
    callback = function(event)
      local bufnr = event.buf
      vim.keymap.set('n', '<leader>fE', function() M.format { formatter = 'eclipse', bufnr = bufnr } end, {
        buffer = bufnr,
        desc = '[F]ormat Java with [E]clipse',
      })
      vim.keymap.set('n', '<leader>fG', function() M.format { formatter = 'google', bufnr = bufnr } end, {
        buffer = bufnr,
        desc = '[F]ormat Java with [G]oogle',
      })
      vim.keymap.set('n', '<leader>fJ', function() M.show_picker() end, {
        buffer = bufnr,
        desc = '[F]ormat Java — pick formatter',
      })
    end,
  })
end

return M
