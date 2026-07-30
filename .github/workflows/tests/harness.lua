-- Shared helpers for kickstart feature tests.
local M = {}

function M.repo_root()
  return vim.fn.fnamemodify(vim.fn.getcwd(), ':p'):gsub('/$', '')
end

function M.ok(msg) io.stdout:write('OK: ' .. msg .. '\n') end

function M.fail(msg)
  io.stderr:write('FAIL: ' .. msg .. '\n')
  vim.cmd 'cquit 1'
end

function M.assert_eq(actual, expected, label)
  if actual ~= expected then
    M.fail(string.format('%s: expected %s, got %s', label or 'assert_eq', vim.inspect(expected), vim.inspect(actual)))
  end
end

function M.assert_truthy(value, label)
  if not value then M.fail((label or 'assert_truthy') .. ' failed') end
end

function M.assert_has(haystack, needle, label)
  if type(haystack) ~= 'string' or not haystack:find(needle, 1, true) then
    M.fail(string.format('%s: %s not found in %s', label or 'assert_has', vim.inspect(needle), vim.inspect(haystack)))
  end
end

function M.map_exists(lhs, mode)
  mode = mode or 'n'
  local maps = vim.fn.maparg(lhs, mode, false, true)
  return type(maps) == 'table' and maps.lhs ~= nil and maps.lhs ~= ''
end

function M.command_exists(name)
  return vim.fn.exists(':' .. name) == 2
end

return M
