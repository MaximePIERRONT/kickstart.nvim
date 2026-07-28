-- Java format style picker (IntelliJ-like) — Eclipse default / Google / Auto.
-- Commands: :JavaFormatStyle [auto|eclipse|google]
-- Keymap: <leader>fS

local jf = require 'custom.java_format'

local LABELS = {
  auto = 'Auto — Google si détecté dans le repo, sinon Eclipse (Default)',
  eclipse = 'Eclipse — profil Default (4 espaces, line 120)',
  google = 'Google Java Format — style Google (2 espaces)',
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Java Format Style' })
end

local function apply_runtime(style)
  jf.apply_checkstyle(style)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'java' then jf.apply_buffer_indent(buf, style) end
  end
end

---Set preference, refresh indent/checkstyle, notify.
---@param style 'auto'|'eclipse'|'google'
local function set_style(style)
  local ok, err = jf.set_preference(style)
  if not ok then
    notify('Impossible de sauver: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  local effective = select(1, jf.resolve())
  apply_runtime(effective)
  notify(string.format('Style → %s (%s)', style, jf.status_line()))
end

local function picker()
  local current = jf.get_preference()
  local items = {}
  for _, style in ipairs(jf.STYLES) do
    local mark = style == current and '● ' or '  '
    table.insert(items, {
      style = style,
      label = mark .. LABELS[style],
    })
  end

  vim.ui.select(items, {
    prompt = 'Java Format Style — ' .. jf.status_line(),
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    set_style(choice.style)
  end)
end

vim.api.nvim_create_user_command('JavaFormatStyle', function(opts)
  local arg = vim.trim(opts.args or '')
  if arg == '' then
    picker()
    return
  end
  arg = arg:lower()
  if arg ~= 'auto' and arg ~= 'eclipse' and arg ~= 'google' then
    notify('Usage: :JavaFormatStyle [auto|eclipse|google]', vim.log.levels.WARN)
    return
  end
  set_style(arg)
end, {
  nargs = '?',
  complete = function() return { 'auto', 'eclipse', 'google' } end,
  desc = 'Choisir le style de formatage Java (auto / eclipse / google)',
})

vim.keymap.set('n', '<leader>fS', picker, { desc = '[F]ormat [S]tyle Java (Eclipse / Google / Auto)' })

-- Keep checkstyle + indent aligned when opening Java files.
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'java',
  group = vim.api.nvim_create_augroup('kickstart-java-format-style', { clear = true }),
  callback = function(ev)
    local style = select(1, jf.resolve(ev.buf))
    jf.apply_buffer_indent(ev.buf, style)
    jf.apply_checkstyle(style)
  end,
})
