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

-- Java format style module + Eclipse profile
local jf = harness.require_ok 'custom.java_format'
harness.assert_truthy(vim.uv.fs_stat(jf.eclipse_profile_path()), 'eclipse formatter xml')
harness.assert_truthy(harness.command_exists 'JavaFormatStyle', 'command JavaFormatStyle')
harness.assert_truthy(harness.map_exists '<leader>fS', 'keymap format style')

-- Conform: java is a function (eclipse → {} / google → google-java-format)
local conform = require 'conform'
local java_fmts_cfg = conform.formatters_by_ft.java
harness.assert_eq(type(java_fmts_cfg), 'function', 'java formatters_by_ft is function')
local ts_fmts = conform.formatters_by_ft.typescript or {}
harness.assert_eq(ts_fmts[1], 'prettier', 'ts formatter')

-- Force google for format-on-demand smoke (reliable without waiting on jdtls format)
local tmp_proj = vim.fn.tempname()
vim.fn.mkdir(tmp_proj, 'p')
vim.fn.writefile({
  '<?xml version="1.0"?><project><modelVersion>4.0.0</modelVersion>',
  '<groupId>t</groupId><artifactId>t</artifactId><version>1</version></project>',
}, tmp_proj .. '/pom.xml')
jf.set_preference('google', tmp_proj)

local fmt_file = repo .. '/fixtures/samples/java/FormatMe.java'
local scratch = tmp_proj .. '/FormatMe.java'
vim.fn.writefile(vim.fn.readfile(fmt_file), scratch)
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(scratch))
vim.bo.filetype = 'java'

harness.assert_eq(select(1, jf.resolve(0)), 'google', 'resolve google in tmp proj')
local java_fmts = java_fmts_cfg(0)
harness.assert_eq(java_fmts[1], 'google-java-format', 'java formatter google')

local before = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
local fmt_ok, fmt_err = pcall(function()
  require('conform').format { async = false, lsp_fallback = false }
end)
harness.assert_truthy(fmt_ok, 'conform format java: ' .. tostring(fmt_err))
local after = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
harness.assert_truthy(after ~= before or after:find 'int add%(int a, int b%)', 'java file formatted')
harness.ok 'conform google-java-format'

-- Eclipse path: empty conform list → LSP fallback (jdtls uses bundled profile)
jf.set_preference('eclipse', tmp_proj)
harness.assert_eq(#jf.conform_formatters(0), 0, 'eclipse uses LSP/jdtls')
harness.ok 'eclipse conform empty'

-- nvim-lint linters configured
local lint = require 'lint'
harness.assert_truthy(vim.tbl_contains(lint.linters_by_ft.java or {}, 'checkstyle'), 'java checkstyle')
harness.assert_truthy(vim.tbl_contains(lint.linters_by_ft.typescript or {}, 'eslint_d'), 'ts eslint_d')

-- blink.cmp + luasnip
harness.require_ok 'blink.cmp'
harness.require_ok 'luasnip'

-- Attach jdtls on a real Java file
local java_file = repo .. '/test-project/domain/src/main/java/com/example/domain/Greeting.java'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(java_file))
vim.bo.filetype = 'java'

harness.wait_until(180000, function()
  return #vim.lsp.get_clients { name = 'jdtls' } > 0
end, 'jdtls attach')
harness.ok 'jdtls LSP attached'

-- jdtls should advertise Eclipse format settings
local clients = vim.lsp.get_clients { name = 'jdtls' }
local settings = clients[1].config.settings or {}
local fmt_url = (((settings.java or {}).format or {}).settings or {}).url
harness.assert_truthy(fmt_url and tostring(fmt_url):find('eclipse%-java%.xml'), 'jdtls eclipse format url')
harness.ok 'jdtls eclipse format settings'

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
