-- Unit tests: custom.plugins.maven-tests helpers
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.plugins.maven-tests'] = nil
local mt = require 'custom.plugins.maven-tests'

local domain_test = repo .. '/test-project/domain/src/test/java/com/example/domain/GreetingTest.java'
harness.assert_eq(mt.class_name(domain_test), 'com.example.domain.GreetingTest', 'domain FQCN')

local infra_main = repo .. '/test-project/infrastructure/src/main/java/com/example/infrastructure/DebugProbe.java'
harness.assert_eq(mt.class_name(infra_main), 'com.example.infrastructure.DebugProbe', 'infra main FQCN')

local module = mt.maven_root(vim.fs.dirname(domain_test))
harness.assert_truthy(module and module:match 'domain$', 'domain module root')
harness.assert_eq(mt.artifact_id(module), 'domain', 'artifactId')
harness.assert_eq(vim.fs.normalize(mt.reactor_root(module)), vim.fs.normalize(repo .. '/test-project'), 'reactor')

local cmd = assert(mt.build_mvn_test_cmd('method', domain_test, 'forName_defaultsWhenBlank'))
local joined = table.concat(cmd, ' ')
harness.assert_has(joined, '-pl :domain', 'pl domain')
harness.assert_has(joined, '-am', 'also-make')
harness.assert_has(joined, '-Dtest=com.example.domain.GreetingTest#forName_defaultsWhenBlank', 'method filter')

harness.ok 'maven-tests unit suite'
vim.cmd 'qa!'
