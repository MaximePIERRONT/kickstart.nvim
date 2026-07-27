-- Unit tests: custom.plugins.runners helpers
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.plugins.runners'] = nil
local runners = require 'custom.plugins.runners'

-- merge_env
local merged = runners.merge_env { FOO = 'bar' }
harness.assert_eq(merged.FOO, 'bar', 'merge_env')

-- parse_env_inline
local inline = runners.parse_env_inline 'A=1;B=two,C=3'
harness.assert_eq(inline.A, '1', 'inline A')
harness.assert_eq(inline.B, 'two', 'inline B')
harness.assert_eq(inline.C, '3', 'inline C')

-- Temporary project root for runners.json / dotenv
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'HELLO=from-dotenv', '# comment', 'QUOTED="x y"' }, tmp .. '/.env.local')

local from_file = runners.parse_env_file(tmp, '.env.local')
harness.assert_eq(from_file.HELLO, 'from-dotenv', 'dotenv HELLO')
harness.assert_eq(from_file.QUOTED, 'x y', 'dotenv quoted')

local cfg = {
  name = 'ci-local',
  type = 'micronaut',
  environments = 'dev,local',
  config_files = { 'config/application-local.yml' },
  env_file = '.env.local',
  env = { EXTRA = '1' },
  jvm_args = '-Xmx128m',
  app_args = '--verbose',
  goals = { 'mn:run' },
}

local env, mvn_args = runners.build_micronaut_env_and_args(tmp, cfg)
harness.assert_eq(env.MICRONAUT_ENVIRONMENTS, 'dev,local', 'MICRONAUT_ENVIRONMENTS')
harness.assert_eq(env.EXTRA, '1', 'cfg.env overlay')
harness.assert_eq(env.HELLO, 'from-dotenv', 'dotenv merged')
harness.assert_has(env.MICRONAUT_CONFIG_FILES, 'application-local.yml', 'config files abs')
harness.assert_has(table.concat(mvn_args, ' '), '-Dmicronaut.environments=dev,local', 'mvn env arg')
harness.assert_has(table.concat(mvn_args, ' '), '-Dmn.jvmArgs=-Xmx128m', 'jvm args')
harness.assert_has(table.concat(mvn_args, ' '), '-Dmn.appArgs=--verbose', 'app args')

local cmd = runners.build_micronaut_cmd(tmp, cfg)
harness.assert_eq(cmd[1], 'mvn', 'cmd mvn')
harness.assert_eq(cmd[#cmd], 'mn:run', 'goal mn:run')

runners.save_runners_file(tmp, { version = 1, default = 'ci-local', configs = { cfg } })
local loaded = runners.load_runners_file(tmp)
harness.assert_eq(loaded.default, 'ci-local', 'saved default')
harness.assert_eq(#loaded.configs, 1, 'saved configs')
harness.assert_eq(loaded.configs[1].name, 'ci-local', 'saved name')

-- Fixture frontend package.json scripts
local pkg = repo .. '/fixtures/frontend/package.json'
local scripts = runners.read_npm_scripts(pkg)
harness.assert_eq(scripts.dev ~= nil, true, 'npm script dev')
harness.assert_eq(scripts.test ~= nil, true, 'npm script test')

-- pom_has on infrastructure
local infra_pom = repo .. '/test-project/infrastructure/pom.xml'
harness.assert_eq(runners.pom_has(infra_pom, 'micronaut'), true, 'infra has micronaut')
harness.assert_eq(runners.pom_has(infra_pom, 'spring-boot'), false, 'infra no spring-boot')

local domain_pom = repo .. '/test-project/domain/pom.xml'
harness.assert_eq(runners.pom_has(domain_pom, 'micronaut'), false, 'domain no micronaut')

harness.ok 'runners unit suite'
vim.cmd 'qa!'
