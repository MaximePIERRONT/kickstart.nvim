-- Unit tests: custom.test_alternate
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.test_alternate'] = nil
local ta = require 'custom.test_alternate'

local SEP = package.config:sub(1, 1)
local tmp_root = repo .. '/.github/workflows/tests/tmp-test-alternate'
vim.fn.mkdir(tmp_root, 'p')

local java_module = tmp_root .. SEP .. 'demo' .. SEP
local main_java = java_module .. 'src' .. SEP .. 'main' .. SEP .. 'java' .. SEP .. 'com' .. SEP .. 'example' .. SEP .. 'Foo.java'
local test_java = java_module .. 'src' .. SEP .. 'test' .. SEP .. 'java' .. SEP .. 'com' .. SEP .. 'example' .. SEP .. 'FooTest.java'
vim.fn.mkdir(vim.fs.dirname(main_java), 'p')
vim.fn.mkdir(vim.fs.dirname(test_java), 'p')
vim.fn.writefile({ 'class Foo {}' }, main_java)
vim.fn.writefile({ 'class FooTest {}' }, test_java)

local main_alts = ta.java_alternates(main_java)
harness.assert_eq(#main_alts, 1, 'main has one test alternate')
harness.assert_eq(vim.fs.normalize(main_alts[1]), vim.fs.normalize(test_java), 'main → FooTest')

local test_alts = ta.java_alternates(test_java)
harness.assert_eq(#test_alts, 1, 'test has one main alternate')
harness.assert_eq(vim.fs.normalize(test_alts[1]), vim.fs.normalize(main_java), 'FooTest → main')

local web_dir = tmp_root .. SEP .. 'web'
vim.fn.mkdir(web_dir, 'p')
local src_ts = web_dir .. SEP .. 'foo.ts'
local test_ts = web_dir .. SEP .. 'foo.test.ts'
vim.fn.writefile({ 'export const foo = 1' }, src_ts)
vim.fn.writefile({ 'import { foo } from "./foo"' }, test_ts)

local web_from_src = ta.web_alternates(src_ts)
harness.assert_eq(vim.fs.normalize(web_from_src[1]), vim.fs.normalize(test_ts), 'foo.ts → foo.test.ts')

local web_from_test = ta.web_alternates(test_ts)
harness.assert_eq(vim.fs.normalize(web_from_test[1]), vim.fs.normalize(src_ts), 'foo.test.ts → foo.ts')

vim.fn.delete(tmp_root, 'rf')

harness.ok 'test-alternate unit suite'
vim.cmd 'qa!'
