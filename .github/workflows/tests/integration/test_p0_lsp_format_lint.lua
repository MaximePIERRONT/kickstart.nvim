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

-- Attach jdtls on a real Java file from the Maven fixture.
local java_file = repo .. '/test-project/domain/src/main/java/com/example/domain/Greeting.java'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(java_file))
vim.bo.filetype = 'java'

harness.wait_until(180000, function()
  local clients = vim.lsp.get_clients { name = 'jdtls', bufnr = 0 }
  if #clients == 0 then return false end
  return clients[1]:supports_method 'textDocument/formatting'
end, 'jdtls attach with formatting')
harness.ok 'jdtls LSP attached'

-- Mutate the attached buffer to valid-but-unformatted source that still matches
-- Greeting.java. jdtls only formats content it already owns in the workspace.
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'package com.example.domain;',
  '',
  'public record Greeting(String message) {',
  'public static Greeting forName(String name){',
  'String safe=(name==null||name.isBlank())?"world":name.trim();',
  'return new Greeting("Hello, "+safe+"!");',
  '}',
  '}',
})
local before = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
local fmt_ok, fmt_err = pcall(function()
  require('conform').format { async = false, timeout_ms = 20000, lsp_format = 'prefer' }
end)
harness.assert_truthy(fmt_ok, 'conform format java: ' .. tostring(fmt_err))
local after = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
-- Reload from disk so later tests never see the mutated buffer.
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(java_file))
harness.assert_truthy(after ~= before and after:find('forName%(String name%) {'), 'java file formatted')
harness.ok 'conform jdtls Eclipse format'

-- Google Java Format remains selectable without changing the default.
harness.assert_truthy(java_format.set('google', true), 'select Google Java Format')
harness.assert_eq(conform.formatters_by_ft.java[1], 'google-java-format', 'Google Java Format selected')

-- Prove the Google path actually formats a disposable buffer.
local google_scratch = vim.fn.tempname() .. '.java'
vim.fn.writefile({
  'package com.example.fixture;',
  '',
  'public final class FormatMe {',
  '  public static int add(int a,int b){return a+b;}',
  '}',
}, google_scratch)
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(google_scratch))
vim.bo.filetype = 'java'
local google_before = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
local google_ok, google_err = pcall(function()
  require('conform').format { async = false, timeout_ms = 10000, lsp_format = 'never' }
end)
harness.assert_truthy(google_ok, 'conform google-java-format: ' .. tostring(google_err))
local google_after = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
harness.assert_truthy(google_after ~= google_before and google_after:find('int add%(int a, int b%)'), 'google java file formatted')
harness.ok 'conform google-java-format'

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
