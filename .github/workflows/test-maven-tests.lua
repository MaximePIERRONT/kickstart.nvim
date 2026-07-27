-- Smoke + integration checks for P2 Maven tests on the multi-module demo.
-- Usage (from repo root):
--   nvim --headless -u NONE -c "luafile .github/workflows/test-maven-tests.lua"

local repo = vim.fn.fnamemodify(vim.fn.getcwd(), ':p')
vim.opt.runtimepath:prepend(repo)

local function fail(msg)
  io.stderr:write('FAIL: ' .. msg .. '\n')
  vim.cmd 'cquit 1'
end

local function ok(msg) io.stdout:write('OK: ' .. msg .. '\n') end

package.loaded['custom.plugins.maven-tests'] = nil
local mt = require 'custom.plugins.maven-tests'
if type(mt.class_name) ~= 'function' then fail 'maven-tests module did not export class_name' end
ok 'maven-tests module loaded'

local cases = {
  {
    file = 'test-project/domain/src/test/java/com/example/domain/GreetingTest.java',
    fqcn = 'com.example.domain.GreetingTest',
    module = 'domain',
    method = 'forName_usesProvidedName',
  },
  {
    file = 'test-project/api/src/test/java/com/example/api/GreetingFacadeContractTest.java',
    fqcn = 'com.example.api.GreetingFacadeContractTest',
    module = 'api',
    method = 'facade_returnsDomainGreeting',
  },
  {
    file = 'test-project/infrastructure/src/test/java/com/example/infrastructure/web/GreetingControllerTest.java',
    fqcn = 'com.example.infrastructure.web.GreetingControllerTest',
    module = 'infrastructure',
    method = 'greet_returnsHelloPayload',
  },
}

local reactor_expected = vim.fs.joinpath(repo, 'test-project')

for _, case in ipairs(cases) do
  local abs = repo .. case.file
  local fqcn = mt.class_name(abs)
  if fqcn ~= case.fqcn then fail(string.format('class_name(%s) = %s, expected %s', case.file, fqcn, case.fqcn)) end

  local module_root = mt.maven_root(vim.fs.dirname(abs))
  if not module_root or not module_root:match(case.module .. '$') then
    fail(string.format('maven_root for %s = %s (expected …/%s)', case.file, tostring(module_root), case.module))
  end

  local reactor = mt.reactor_root(module_root)
  if reactor ~= reactor_expected and reactor ~= reactor_expected:gsub('/$', '') then
    -- Allow trailing slash differences
    if vim.fs.normalize(reactor) ~= vim.fs.normalize(reactor_expected) then
      fail('reactor_root = ' .. tostring(reactor) .. ' expected ' .. reactor_expected)
    end
  end

  local artifact = mt.artifact_id(module_root)
  if artifact ~= case.module then fail('artifactId = ' .. tostring(artifact)) end

  local class_cmd, class_cwd, err = mt.build_mvn_test_cmd('class', abs)
  if not class_cmd then fail('build class cmd: ' .. tostring(err)) end
  local joined = table.concat(class_cmd, ' ')
  if not joined:find('-pl :' .. case.module, 1, true) then fail('missing -pl in ' .. joined) end
  if not joined:find('-am', 1, true) then fail('missing -am in ' .. joined) end
  if not joined:find('-Dtest=' .. case.fqcn, 1, true) then fail('missing -Dtest in ' .. joined) end
  if vim.fs.normalize(class_cwd) ~= vim.fs.normalize(reactor_expected) then
    fail('class cwd = ' .. tostring(class_cwd) .. ' expected reactor')
  end

  vim.cmd('edit ' .. vim.fn.fnameescape(abs))
  vim.cmd 'filetype detect'
  vim.fn.search(case.method, 'w')

  local method_cmd, method_cwd, merr = mt.build_mvn_test_cmd('method', abs, case.method)
  if not method_cmd then fail('build method cmd: ' .. tostring(merr)) end
  local mjoined = table.concat(method_cmd, ' ')
  if not mjoined:find('-Dtest=' .. case.fqcn .. '#' .. case.method, 1, true) then
    fail('unexpected method cmd: ' .. mjoined)
  end
  if vim.fs.normalize(method_cwd) ~= vim.fs.normalize(reactor_expected) then fail 'method cwd mismatch' end

  ok(case.module .. ' FQCN + multi-module cmd resolution')

  local result = vim.system(class_cmd, { cwd = class_cwd, text = true }):wait()
  if result.code ~= 0 then
    fail(string.format('mvn test class failed in %s:\n%s%s', case.module, result.stdout or '', result.stderr or ''))
  end
  ok(case.module .. ' mvn -pl :' .. case.module .. ' -am test -Dtest=' .. case.fqcn)
end

if vim.fn.exists ':MavenTest' ~= 2 then fail 'MavenTest command missing' end
ok 'MavenTest command present'

io.stdout:write '=== Maven tests smoke PASSED ===\n'
vim.cmd 'qa!'
