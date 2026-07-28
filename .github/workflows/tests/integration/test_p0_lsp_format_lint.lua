-- Integration P0: LSP / format / lint / completion stack is wired.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
harness.silence_lint()

if vim.fn.executable 'jdtls' ~= 1 then
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  vim.env.PATH = mason_bin .. ':' .. (vim.env.PATH or '')
end

harness.assert_truthy(vim.env.JDTLS_JAVA_HOME and vim.env.JDTLS_JAVA_HOME ~= '', 'JDTLS_JAVA_HOME')

-- Mason packages expected for P0/P2
local mason_pkg = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'packages')
for _, pkg in ipairs {
  'jdtls',
  'google-java-format',
  'prettier',
  'eslint_d',
  'stylua',
  'java-debug-adapter',
  'js-debug-adapter',
} do
  local path = vim.fs.joinpath(mason_pkg, pkg)
  harness.assert_truthy(vim.fn.isdirectory(path) == 1, 'mason package ' .. pkg)
  harness.ok('mason ' .. pkg)
end

-- Conform formatters configured
local conform = require 'conform'
local java_format = require 'custom.plugins.java-format'
local java_fmts = conform.formatters_by_ft.java or {}
harness.assert_eq(java_format.current(), 'eclipse', 'java formatter defaults to Eclipse')
harness.assert_eq(java_fmts.lsp_format, 'prefer', 'java prefers jdtls/Eclipse formatting')
local ts_fmts = conform.formatters_by_ft.typescript or {}
harness.assert_eq(ts_fmts[1], 'prettier', 'ts formatter')

-- nvim-lint linters configured
local lint = require 'lint'
harness.assert_truthy(vim.tbl_contains(lint.linters_by_ft.java or {}, 'checkstyle'), 'java checkstyle')
harness.assert_truthy(vim.tbl_contains(lint.linters_by_ft.typescript or {}, 'eslint_d'), 'ts eslint_d')

-- blink.cmp + luasnip
harness.require_ok 'blink.cmp'
harness.require_ok 'luasnip'

-- Attach jdtls on a real project file, then format a sibling scratch type.
local java_file = repo .. '/test-project/domain/src/main/java/com/example/domain/Greeting.java'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(java_file))
vim.bo.filetype = 'java'

harness.wait_until(180000, function()
  return #vim.lsp.get_clients { name = 'jdtls' } > 0
end, 'jdtls attach')
harness.ok 'jdtls LSP attached'

local scratch = repo .. '/test-project/domain/src/main/java/com/example/domain/FormatScratch.java'
vim.fn.writefile({
  'package com.example.domain;',
  '',
  'public final class FormatScratch {',
  'public static int add(int a,int b){return a+b;}',
  '}',
}, scratch)

local function cleanup_scratch()
  pcall(vim.fn.delete, scratch)
end

pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(scratch))
vim.bo.filetype = 'java'
harness.wait_until(60000, function()
  local clients = vim.lsp.get_clients { name = 'jdtls', bufnr = 0 }
  return #clients > 0 and clients[1].server_capabilities.documentFormattingProvider
end, 'jdtls format capability on scratch')

local before = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
local fmt_ok, fmt_err = pcall(function()
  require('conform').format { async = false, timeout_ms = 15000, lsp_format = 'prefer' }
end)
if not fmt_ok then
  cleanup_scratch()
  harness.fail('conform format java: ' .. tostring(fmt_err))
end
local after = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
cleanup_scratch()
harness.assert_truthy(after ~= before and after:find('int add%(int a, int b%)'), 'java file formatted')
harness.ok 'conform jdtls Eclipse format'

-- Google Java Format remains selectable without changing the default.
harness.assert_truthy(java_format.set('google', true), 'select Google Java Format')
harness.assert_eq(conform.formatters_by_ft.java[1], 'google-java-format', 'Google Java Format selected')
harness.assert_truthy(java_format.set('eclipse', true), 'restore Eclipse formatter')
harness.assert_eq(conform.formatters_by_ft.java.lsp_format, 'prefer', 'Eclipse formatter restored')

-- TypeScript sample: prettier available (format may no-op if already pretty)
local ts_file = repo .. '/fixtures/samples/typescript/greet.ts'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(ts_file))
vim.bo.filetype = 'typescript'
local ts_fmt_ok, ts_fmt_err = pcall(function()
  require('conform').format { async = false, lsp_fallback = false }
end)
harness.assert_truthy(ts_fmt_ok, 'conform format ts: ' .. tostring(ts_fmt_err))
harness.ok 'conform prettier typescript'

-- Vue sample opens without crash
local vue_file = repo .. '/fixtures/samples/vue/HelloFixture.vue'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(vue_file))
vim.bo.filetype = 'vue'
harness.ok 'vue buffer opens'

harness.ok 'P0 LSP/format/lint/completion integration'
vim.cmd 'qa!'
