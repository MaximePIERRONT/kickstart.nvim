-- Integration: full config boots and core plugins/modules load.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')

harness.require_ok 'dap'
harness.require_ok 'dapui'
harness.require_ok 'jdtls'
harness.require_ok 'neo-tree'
harness.require_ok 'gitsigns'
harness.require_ok 'telescope'
harness.require_ok 'conform'
harness.require_ok 'lint'
harness.require_ok 'blink.cmp'
harness.require_ok 'luasnip'
harness.require_ok 'which-key'
harness.require_ok 'mason'
harness.require_ok 'custom.plugins.runners'
harness.require_ok 'custom.plugins.maven-tests'

harness.ok 'config boot + core modules'
vim.cmd 'qa!'
