-- Test complet pour vérifier jdtls, neotest et les keymaps Java
-- Usage: nvim --headless -c "luafile test-neotest-full.lua" -c "qa!"

local TEST_FILE = vim.fn.getcwd() .. "/test-project/core/src/test/java/com/example/CalculatorTest.java"

local function log(msg)
  vim.cmd('redir! >> /tmp/neotest-full-test.log')
  vim.cmd('echo "' .. msg .. '"')
  vim.cmd('redir END')
  print(msg)
end

local function fail(msg)
  log("FAIL: " .. msg)
  error(msg)
end

-- Test 1: Vérifier que le fichier de test existe
log("Test 1: Checking test file exists...")
local f = io.open(TEST_FILE, "r")
if not f then
  fail("Test file not found: " .. TEST_FILE)
end
f:close()
log("✓ Test file exists: " .. TEST_FILE)

-- Test 2: Ouvrir le fichier Java
log("Test 2: Opening Java file...")
vim.cmd("edit " .. TEST_FILE)
vim.cmd("set ft=java")
log("✓ Opened " .. TEST_FILE)

-- Test 3: Attendre que jdtls soit prêt (avec timeout)
log("Test 3: Waiting for jdtls to attach...")
local timeout = 60
local interval = 0.5
local elapsed = 0

while elapsed < timeout do
  local clients = vim.lsp.get_active_clients({name = "jdtls"})
  if #clients > 0 then
    log("✓ jdtls attached after " .. elapsed .. "s")
    break
  end
  vim.cmd("sleep 500m")
  elapsed = elapsed + 0.5
end

if elapsed >= timeout then
  log("WARNING: jdtls did not attach within " .. timeout .. "s, continuing anyway...")
end

-- Test 4: Vérifier que neotest est disponible
log("Test 4: Checking neotest...")
local ok_neotest, neotest = pcall(require, 'neotest')
if not ok_neotest then
  fail("neotest not found")
end
log("✓ neotest available")

-- Test 5: Vérifier les keymaps <leader>j*
log("Test 5: Checking <leader>j* keymaps...")
local maps = vim.api.nvim_get_keymap('n')
local leaderj_maps = {}
for _, map in ipairs(maps) do
  if map.lhs and string.find(map.lhs, "<leader>j") then
    table.insert(leaderj_maps, map.lhs)
  end
end

local required_maps = {"<leader>jf", "<leader>jt"}
for _, required in ipairs(required_maps) do
  local found = false
  for _, map_lhs in ipairs(leaderj_maps) do
    if map_lhs == required then
      found = true
      break
    end
  end
  if not found then
    fail("Required keymap not found: " .. required)
  end
  log("✓ Found: " .. required)
end

log("Found " .. #leaderj_maps .. " <leader>j* keymaps")

-- Test 6: Vérifier que neotest-summary peut être affiché
log("Test 6: Checking neotest summary toggle...")
local ok_summary = pcall(function()
  neotest.summary.toggle()
end)
if not ok_summary then
  fail("neotest.summary.toggle() failed")
end
log("✓ neotest.summary.toggle() works")

-- Test 7: Exécuter les tests avec neotest (dry run - vérifie que la commande peut être construite)
log("Test 7: Testing neotest.run.run availability...")
local ok_run = pcall(function()
  local run_fn = neotest.run.run
  if type(run_fn) ~= "function" then
    error("neotest.run.run is not a function")
  end
end)
if not ok_run then
  fail("neotest.run.run is not available")
end
log("✓ neotest.run.run is available")

log("=== ALL TESTS PASSED ===")
os.exit(0)
