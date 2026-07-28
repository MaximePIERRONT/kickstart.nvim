-- Java formatter selection. Eclipse/jdtls is the default; Google Java Format
-- remains available for projects that explicitly use that convention.
--
-- Important: conform treats an empty formatter list as "disable formatting".
-- Eclipse mode therefore keeps an explicit lsp_format preference so jdtls runs.
local M = {}

local DEFAULT = 'eclipse'
local FORMATTERS = {
  eclipse = { lsp_format = 'prefer' },
  google = { 'google-java-format' },
}

local LABELS = {
  eclipse = 'Eclipse profile (repository default)',
  google = 'Google Java Format',
}

---@return 'eclipse'|'google'
function M.current()
  return vim.g.kickstart_java_formatter == 'google' and 'google' or DEFAULT
end

---@param bufnr integer
---@param size integer
local function set_indent(bufnr, size)
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = size
  vim.bo[bufnr].shiftwidth = size
  vim.bo[bufnr].softtabstop = size
end

---@param name string
---@param silent? boolean
---@return boolean
function M.set(name, silent)
  if not FORMATTERS[name] then
    vim.notify('Unknown Java formatter: ' .. name .. '. Use eclipse or google.', vim.log.levels.ERROR)
    return false
  end

  vim.g.kickstart_java_formatter = name
  require('conform').formatters_by_ft.java = vim.deepcopy(FORMATTERS[name])

  local indent_size = name == 'google' and 2 or 4
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].filetype == 'java' then set_indent(bufnr, indent_size) end
  end

  if not silent then vim.notify('Java formatter: ' .. LABELS[name], vim.log.levels.INFO) end
  return true
end

---Format with the selected Java formatter, or use the normal Conform behavior
---for every other file type.
function M.format()
  local opts = { async = true, lsp_format = 'fallback' }
  if vim.bo.filetype == 'java' and M.current() == 'eclipse' then opts.lsp_format = 'prefer' end
  require('conform').format(opts)
end

function M.picker()
  local choices = { 'eclipse', 'google' }
  vim.ui.select(choices, {
    prompt = 'Java formatter',
    format_item = function(name)
      local suffix = name == M.current() and ' (current)' or ''
      return LABELS[name] .. suffix
    end,
  }, function(choice)
    if choice then M.set(choice) end
  end)
end

vim.api.nvim_create_user_command('JavaFormat', function(opts)
  local name = vim.trim(opts.args)
  if name == '' then
    M.picker()
  else
    M.set(name)
  end
end, {
  nargs = '?',
  complete = function() return { 'eclipse', 'google' } end,
  desc = 'Select Java formatter (eclipse|google)',
})

vim.keymap.set('n', '<leader>jf', M.picker, { desc = '[J]ava [f]ormatter' })

M.set(M.current(), true)

return M
