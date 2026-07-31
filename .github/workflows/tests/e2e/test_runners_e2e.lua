-- E2E: npm + Maven + Micronaut runners against fixtures / test-project.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)
harness.silence_lint()

package.loaded['custom.plugins.runners'] = nil
local runners = require 'custom.plugins.runners'

-- --- npm fixture ---
local frontend = repo .. '/fixtures/frontend'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(frontend .. '/package.json'))
local npm_root = select(1, runners.npm_root())
harness.assert_eq(vim.fs.normalize(npm_root), vim.fs.normalize(frontend), 'npm_root fixture')

local npm_test = vim.system({ 'npm', 'test' }, { cwd = frontend, text = true }):wait()
harness.assert_eq(npm_test.code, 0, 'npm test exit')
harness.assert_has(npm_test.stdout or '', 'test-ok', 'npm test output')
harness.ok 'e2e npm test'

local npm_build = vim.system({ 'npm', 'run', 'build' }, { cwd = frontend, text = true }):wait()
harness.assert_eq(npm_build.code, 0, 'npm build exit')
harness.assert_has(npm_build.stdout or '', 'build-ok', 'npm build output')
harness.ok 'e2e npm build'

-- --- Maven compile/package via runners API (headless run_in_terminal) ---
local infra_java = repo .. '/test-project/infrastructure/src/main/java/com/example/infrastructure/Application.java'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(infra_java))
local mvn_root = select(1, runners.maven_root())
harness.assert_truthy(mvn_root and mvn_root:match 'infrastructure$', 'maven_root infrastructure')

-- Prefer reactor-aware compile from infrastructure module directory using -pl via shell for certainty
local compile = vim.system({ 'mvn', '-pl', ':infrastructure', '-am', '-DskipTests', 'compile' }, {
  cwd = repo .. '/test-project',
  text = true,
}):wait()
harness.assert_eq(compile.code, 0, 'mvn compile infrastructure')
harness.ok 'e2e maven compile'

-- runners.maven_run from module context (headless) after reactor install/compile
local ok_compile = pcall(function() runners.maven_run { '-q', 'test-compile' } end)
harness.assert_truthy(ok_compile, 'runners.maven_run test-compile')
harness.ok 'e2e runners.maven_run'

-- --- Micronaut config persistence + command build ---
local cfg = {
  name = 'e2e-local',
  type = 'micronaut',
  environments = 'test',
  config_files = { 'src/main/resources/application.yml' },
  env = { E2E_FLAG = '1' },
  goals = { 'mn:run' },
}
runners.save_runners_file(mvn_root, { version = 1, default = 'e2e-local', configs = { cfg } })
local loaded = runners.load_runners_file(mvn_root)
harness.assert_eq(loaded.default, 'e2e-local', 'micronaut config saved')

local cmd, env = runners.build_micronaut_cmd(mvn_root, cfg)
harness.assert_eq(env.E2E_FLAG, '1', 'micronaut env')
harness.assert_eq(env.MICRONAUT_ENVIRONMENTS, 'test', 'micronaut environments')
harness.assert_has(table.concat(cmd, ' '), 'mn:run', 'micronaut goal')
harness.assert_has(table.concat(cmd, ' '), '-Dmicronaut.environments=test', 'micronaut -D env')
harness.ok 'e2e micronaut config → cmd'

-- User commands exist for interactive use
harness.assert_truthy(harness.command_exists 'Npm', ':Npm')
harness.assert_truthy(harness.command_exists 'Maven', ':Maven')
harness.assert_truthy(harness.command_exists 'Micronaut', ':Micronaut')
harness.assert_truthy(harness.command_exists 'RunConfig', ':RunConfig')

harness.ok 'runners e2e suite'
vim.cmd 'qa!'
