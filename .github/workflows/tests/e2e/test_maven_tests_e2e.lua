-- E2E: Maven test keymaps resolve + execute across multi-module project.
-- (Supersedes the older flat smoke with richer assertions.)
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.plugins.maven-tests'] = nil
local mt = require 'custom.plugins.maven-tests'

local cases = {
  {
    file = '/test-project/domain/src/test/java/com/example/domain/GreetingTest.java',
    module = 'domain',
    fqcn = 'com.example.domain.GreetingTest',
    method = 'forName_usesProvidedName',
  },
  {
    file = '/test-project/api/src/test/java/com/example/api/GreetingFacadeContractTest.java',
    module = 'api',
    fqcn = 'com.example.api.GreetingFacadeContractTest',
    method = 'facade_returnsDomainGreeting',
  },
  {
    file = '/test-project/infrastructure/src/test/java/com/example/infrastructure/web/GreetingControllerTest.java',
    module = 'infrastructure',
    fqcn = 'com.example.infrastructure.web.GreetingControllerTest',
    method = 'greet_returnsHelloPayload',
  },
}

for _, case in ipairs(cases) do
  local abs = repo .. case.file
  local class_cmd, cwd = assert(mt.build_mvn_test_cmd('class', abs))
  local method_cmd = assert(mt.build_mvn_test_cmd('method', abs, case.method))
  harness.assert_has(table.concat(class_cmd, ' '), '-pl :' .. case.module, case.module .. ' pl')
  harness.assert_has(table.concat(method_cmd, ' '), case.fqcn .. '#' .. case.method, case.module .. ' method')

  local result = vim.system(class_cmd, { cwd = cwd, text = true }):wait()
  harness.assert_eq(result.code, 0, case.module .. ' mvn class test')
  harness.ok('e2e maven-tests ' .. case.module)
end

-- :MavenTest command available
harness.assert_truthy(vim.fn.exists ':MavenTest' == 2, ':MavenTest')

harness.ok 'maven-tests e2e suite'
vim.cmd 'qa!'
