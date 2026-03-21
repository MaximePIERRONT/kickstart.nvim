-- Test simple pour vérifier que neotest et neotest-java sont disponibles
-- Usage: nvim --headless -c "luafile test-neotest-simple.lua" -c "qa!"

local function log(msg)
  vim.cmd('redir! >> /tmp/neotest-test.log')
  vim.cmd('echo "' .. msg .. '"')
  vim.cmd('redir END')
end

local function fail(msg)
  log("FAIL: " .. msg)
  error(msg)
end

-- Test 1: Vérifier que neotest est chargé
log("Test 1: Checking neotest...")
local ok_neotest, neotest = pcall(require, 'neotest')
if not ok_neotest then
  fail("neotest not found: " .. tostring(neotest))
end
log("✓ neotest loaded")

-- Test 2: Vérifier que neotest-java est chargé
log("Test 2: Checking neotest-java...")
local ok_java, neotest_java = pcall(require, 'neotest-java')
if not ok_java then
  fail("neotest-java not found: " .. tostring(neotest_java))
end
log("✓ neotest-java loaded")

-- Test 3: Vérifier que l'adapter peut être instancié
log("Test 3: Instantiating neotest-java adapter...")
local ok_adapter, adapter = pcall(neotest_java)
if not ok_adapter then
  fail("Failed to instantiate neotest-java adapter: " .. tostring(adapter))
end
if adapter == nil then
  fail("neotest-java adapter is nil")
end
log("✓ neotest-java adapter instantiated")

-- Test 4: Vérifier que l'adapter a les méthodes attendues
log("Test 4: Checking adapter methods...")
if type(adapter) ~= "table" then
  fail("Adapter is not a table, got: " .. type(adapter))
end

local required_methods = {"discover", "is_test_file", "build_spec", "run"}
for _, method in ipairs(required_methods) do
  if type(adapter[method]) ~= "function" then
    fail("Adapter missing method: " .. method)
  end
end
log("✓ adapter has all required methods")

log("=== ALL TESTS PASSED ===")
os.exit(0)
