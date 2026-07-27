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

function M.wait_until(timeout_ms, predicate, label)
  local deadline = vim.uv.hrtime() + (timeout_ms * 1e6)
  while vim.uv.hrtime() < deadline do
    local ok_pred, result = pcall(predicate)
    if ok_pred and result then return true end
    vim.wait(200)
  end
  M.fail('timeout waiting for ' .. (label or 'condition'))
end

function M.map_exists(lhs, mode)
  mode = mode or 'n'
  local maps = vim.fn.maparg(lhs, mode, false, true)
  return type(maps) == 'table' and maps.lhs ~= nil and maps.lhs ~= ''
end

function M.command_exists(name)
  return vim.fn.exists(':' .. name) == 2
end

function M.require_ok(mod)
  local ok, result = pcall(require, mod)
  if not ok then M.fail('require ' .. mod .. ' failed: ' .. tostring(result)) end
  return result
end

---Disable noisy autocmds that break headless edits.
function M.silence_lint()
  pcall(function() vim.api.nvim_clear_autocmds { group = 'kickstart-lint' } end)
end

return M
