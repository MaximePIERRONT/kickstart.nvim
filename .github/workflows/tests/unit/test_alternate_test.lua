-- Unit tests: custom.plugins.alternate-test helpers
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.plugins.alternate-test'] = nil
local alt = require 'custom.plugins.alternate-test'

local sep = '/'
local function p(...) return table.concat({ ... }, sep) end

-- Java stems
harness.assert_eq(alt.java_source_stems('GreetingTest')[1], 'Greeting', 'strip Test')
harness.assert_eq(alt.java_source_stems('GreetingTests')[1], 'Greeting', 'strip Tests')
harness.assert_eq(alt.java_source_stems('TestGreeting')[1], 'Greeting', 'strip Test prefix')
harness.assert_eq(alt.java_source_stems('FooIT')[1], 'Foo', 'strip IT')
harness.assert_eq(alt.java_source_stems('FooIntegrationTest')[1], 'Foo', 'strip IntegrationTest')

-- Java main → test candidates (test-project fixture)
local greeting = p(repo, 'test-project/domain/src/main/java/com/example/domain/Greeting.java')
local java_to_test = alt.java_candidates(greeting)
harness.assert_truthy(#java_to_test >= 1, 'java main has candidates')
harness.assert_has(java_to_test[1], 'src/test/java/com/example/domain/GreetingTest.java', 'first candidate FooTest')

local existing_java = alt.existing(java_to_test)
harness.assert_eq(#existing_java, 1, 'GreetingTest exists')
harness.assert_has(existing_java[1], 'GreetingTest.java', 'existing is GreetingTest')

-- Java test → main
local greeting_test = p(repo, 'test-project/domain/src/test/java/com/example/domain/GreetingTest.java')
local java_to_main = alt.java_candidates(greeting_test)
harness.assert_eq(#java_to_main, 1, 'one stem from GreetingTest')
harness.assert_has(java_to_main[1], 'src/main/java/com/example/domain/Greeting.java', 'back to Greeting')
harness.assert_eq(#alt.existing(java_to_main), 1, 'Greeting exists')

-- Web: source → test patterns
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local src_ts = p(tmp, 'foo.ts')
vim.fn.writefile({ 'export const x = 1' }, src_ts)
local web_cands = alt.web_candidates(src_ts)
harness.assert_has(table.concat(web_cands, '\n'), 'foo.test.ts', 'test.ts candidate')
harness.assert_has(table.concat(web_cands, '\n'), 'foo.spec.ts', 'spec.ts candidate')
harness.assert_has(table.concat(web_cands, '\n'), '__tests__/foo.ts', '__tests__ candidate')

local test_ts = p(tmp, 'foo.test.ts')
vim.fn.writefile({ "import { x } from './foo'" }, test_ts)
local back = alt.web_candidates(test_ts)
harness.assert_eq(#alt.existing(back), 1, 'source exists from .test.ts')
harness.assert_has(alt.existing(back)[1], 'foo.ts', 'back to foo.ts')

-- __tests__ layout
local tests_dir = p(tmp, 'pkg', '__tests__')
vim.fn.mkdir(tests_dir, 'p')
local nested_src = p(tmp, 'pkg', 'bar.ts')
vim.fn.writefile({ 'export {}' }, nested_src)
local nested_test = p(tests_dir, 'bar.test.ts')
vim.fn.writefile({ 'export {}' }, nested_test)
local from_nested = alt.existing(alt.web_candidates(nested_test))
harness.assert_eq(#from_nested, 1, '__tests__ → parent source')
harness.assert_has(from_nested[1], 'pkg/bar.ts', 'parent bar.ts')

harness.assert_eq(#alt.candidates 'readme.md', 0, 'unsupported filetype')

harness.ok 'alternate-test unit suite'
vim.cmd 'qa!'
