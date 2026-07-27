-- E2E: auto-install LazyGit (+ LazyDocker) and run --version headless.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.ensure_tool'] = nil
package.loaded['custom.plugins.lazy-tui'] = nil

local ensure = require 'custom.ensure_tool'

-- Isolate installs under a temp directory (avoid polluting real stdpath).
local tmp = vim.fn.tempname() .. '-kickstart-tools-e2e'
vim.fn.mkdir(tmp, 'p')
ensure.tools_root = function() return tmp end
ensure.bin_dir = function() return vim.fs.joinpath(tmp, 'bin') end

local ok_lg, path_lg = ensure.ensure_lazygit()
harness.assert_truthy(ok_lg, 'ensure_lazygit: ' .. tostring(path_lg))
harness.assert_truthy(path_lg and (vim.fn.executable(path_lg) == 1), 'lazygit executable path')
local ver = vim.system({ path_lg, '--version' }, { text = true }):wait()
harness.assert_eq(ver.code, 0, 'lazygit --version')
harness.ok('lazygit installed: ' .. path_lg)

local ok_ld, path_ld = ensure.ensure_lazydocker()
harness.assert_truthy(ok_ld, 'ensure_lazydocker: ' .. tostring(path_ld))
local ver_ld = vim.system({ path_ld, '--version' }, { text = true }):wait()
if ver_ld.code ~= 0 then ver_ld = vim.system({ path_ld, '-v' }, { text = true }):wait() end
harness.assert_eq(ver_ld.code, 0, 'lazydocker version')
harness.ok('lazydocker installed: ' .. path_ld)

-- Plugin commands / keymaps
require 'custom.plugins.lazy-tui'
harness.assert_truthy(harness.command_exists 'LazyGit', ':LazyGit')
harness.assert_truthy(harness.command_exists 'LazyDocker', ':LazyDocker')
harness.assert_truthy(harness.map_exists '<leader>gg', '<leader>gg')
harness.assert_truthy(harness.map_exists '<leader>ld', '<leader>ld')

local tui = require 'custom.plugins.lazy-tui'
local ok_open = pcall(tui.open_lazygit)
harness.assert_truthy(ok_open, 'open_lazygit headless')
harness.ok 'lazy-tui headless open'

harness.ok 'ensure_tool / lazy-tui e2e'
vim.cmd 'qa!'
