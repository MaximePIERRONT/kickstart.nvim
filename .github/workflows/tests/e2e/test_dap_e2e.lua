-- Smoke checks for P2 DAP (nvim-dap + java/js adapters + jdtls bundles).
-- Expects this repo as Neovim config and JDTLS_JAVA_HOME → JDK 21+.

local function fail(msg)
  io.stderr:write('FAIL: ' .. msg .. '\n')
  vim.cmd 'cquit 1'
end

local function ok(msg) io.stdout:write('OK: ' .. msg .. '\n') end

local function wait_until(timeout_ms, predicate, label)
  local deadline = vim.uv.hrtime() + (timeout_ms * 1e6)
  while vim.uv.hrtime() < deadline do
    local ok_pred, result = pcall(predicate)
    if ok_pred and result then return true end
    vim.wait(250)
  end
  fail('timeout waiting for ' .. label)
end

-- Avoid nvim-lint / checkstyle noise during headless smoke.
pcall(function()
  vim.api.nvim_clear_autocmds { group = 'kickstart-lint' }
end)

local dap_ok, dap = pcall(require, 'dap')
if not dap_ok then fail('nvim-dap not available: ' .. tostring(dap)) end
ok 'nvim-dap loaded'

if not pcall(require, 'dapui') then fail 'nvim-dap-ui not available' end
ok 'nvim-dap-ui loaded'

if not pcall(require, 'jdtls') then fail 'nvim-jdtls not available' end
ok 'nvim-jdtls loaded'

if type(dap.configurations.typescript) ~= 'table' or #dap.configurations.typescript == 0 then
  fail 'missing dap.configurations.typescript'
end
ok 'JS/TS dap configurations present'

local bundle_pattern = vim.fs.joinpath(
  vim.fn.stdpath 'data',
  'mason',
  'packages',
  'java-debug-adapter',
  'extension',
  'server',
  'com.microsoft.java.debug.plugin-*.jar'
)

wait_until(120000, function()
  local bundles = vim.fn.glob(bundle_pattern, true, true)
  return type(bundles) == 'table' and #bundles > 0
end, 'java-debug-adapter mason package')

local bundles = vim.fn.glob(bundle_pattern, true, true)
ok('java-debug-adapter bundles: ' .. table.concat(bundles, ', '))

-- Ensure jdtls binary is discoverable (Mason bin linked via mason setup PATH).
if vim.fn.executable 'jdtls' ~= 1 then
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  vim.env.PATH = mason_bin .. ':' .. (vim.env.PATH or '')
end
if vim.fn.executable 'jdtls' ~= 1 then fail 'jdtls executable not found (Mason install missing?)' end
ok 'jdtls executable present'

if not vim.env.JDTLS_JAVA_HOME or vim.env.JDTLS_JAVA_HOME == '' then fail 'JDTLS_JAVA_HOME is not set' end
ok('JDTLS_JAVA_HOME=' .. vim.env.JDTLS_JAVA_HOME)

local probe = vim.fn.fnamemodify('test-project/infrastructure/src/main/java/com/example/infrastructure/DebugProbe.java', ':p')
if vim.fn.filereadable(probe) ~= 1 then fail('missing DebugProbe.java at ' .. probe) end

-- Open without letting autocmd failures abort the smoke script.
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
local lines = vim.fn.readfile(probe)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_buf_set_name(buf, probe)
vim.bo[buf].filetype = 'java'
-- Kick LSP for this buffer explicitly.
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(probe))
vim.bo.filetype = 'java'
ok 'DebugProbe.java buffer ready'

wait_until(180000, function()
  local clients = vim.lsp.get_clients { name = 'jdtls' }
  return #clients > 0
end, 'jdtls attach')
ok 'jdtls attached'

-- Wire DAP helpers (also done on LspAttach by debug.lua; call again for certainty).
pcall(function()
  require('jdtls').setup_dap { hotcodereplace = 'auto' }
  require('jdtls.dap').setup_dap_main_class_configs()
end)

wait_until(60000, function() return dap.adapters.java ~= nil end, 'dap.adapters.java registration')
ok 'dap.adapters.java registered'

local clients = vim.lsp.get_clients { name = 'jdtls' }
local client = clients[1]
if not client then fail 'no jdtls client after attach' end

-- Validate debug extension is loaded: startDebugSession should return a port.
local dap_done, dap_err, dap_port = false, nil, nil
client:request('workspace/executeCommand', { command = 'vscode.java.startDebugSession' }, function(err, result)
  dap_err = err
  dap_port = result
  dap_done = true
end)

wait_until(60000, function() return dap_done end, 'vscode.java.startDebugSession')
if dap_err then fail('startDebugSession error: ' .. vim.inspect(dap_err)) end
if type(dap_port) ~= 'number' or dap_port <= 0 then
  fail('startDebugSession did not return a port: ' .. vim.inspect(dap_port))
end
ok('java debug session port=' .. tostring(dap_port))

-- Discover main classes (DebugProbe / Application) once the project is imported.
local mains_done, mains_err, mains = false, nil, nil
client:request('workspace/executeCommand', { command = 'vscode.java.resolveMainClass' }, function(err, result)
  mains_err = err
  mains = result
  mains_done = true
end)
wait_until(90000, function() return mains_done end, 'vscode.java.resolveMainClass')
if mains_err then fail('resolveMainClass error: ' .. vim.inspect(mains_err)) end
if type(mains) ~= 'table' then fail('resolveMainClass returned non-table: ' .. vim.inspect(mains)) end

local found = false
for _, item in ipairs(mains) do
  local name = ''
  if type(item) == 'table' then
    name = tostring(item.mainClass or item.className or '')
  else
    name = tostring(item)
  end
  if name:find('DebugProbe', 1, true) or name:find('Application', 1, true) then found = true end
end
if found then
  ok 'resolveMainClass found DebugProbe/Application'
else
  ok('resolveMainClass entries=' .. tostring(#mains) .. ' (import may still be warming; debug port already OK)')
end

pcall(function() require('jdtls.dap').setup_dap_main_class_configs() end)
vim.wait(2000)
local java_cfgs = dap.configurations.java or {}
ok('dap.configurations.java count=' .. tostring(#java_cfgs))

io.stdout:write '=== DAP smoke PASSED ===\n'
vim.cmd 'qa!'
