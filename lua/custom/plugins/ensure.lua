-- User-facing helpers for auto-installed CLI tools (Ubuntu / Arch friendly).
local ensure = require 'custom.ensure_tool'

vim.api.nvim_create_user_command('KickstartEnsureTools', function()
  vim.notify('Ensuring managed tools (Node, JDK, rg, fd, Maven, LazyGit, LazyDocker, LazySQL)…', vim.log.levels.INFO)
  local results = ensure.ensure_all()
  local lines = {}
  for name, pair in pairs(results) do
    local ok, detail = pair[1], pair[2]
    table.insert(lines, string.format('%s: %s (%s)', name, ok and 'ok' or 'FAIL', tostring(detail)))
  end
  table.sort(lines)
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end, { desc = 'Download missing tools into stdpath data (Node, JDK, rg, fd, Maven, LazyGit, LazyDocker, LazySQL)' })

-- Warm remaining tools after UI is ready (Maven / LazyGit / LazySQL / …). Node+JDK+rg+fd
-- already run sync before Mason in init.lua.
vim.api.nvim_create_autocmd('VimEnter', {
  group = vim.api.nvim_create_augroup('kickstart-ensure-tools', { clear = true }),
  once = true,
  callback = function() ensure.ensure_common_async() end,
})
