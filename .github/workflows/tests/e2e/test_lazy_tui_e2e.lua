-- E2E: auto-install managed CLIs (ripgrep, fd, lazygit, lazydocker, rainfrog, maven) headless.
-- Node/JDK are large; we still verify URL helpers + install of smaller tools.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.ensure_tool'] = nil
package.loaded['custom.plugins.lazy-tui'] = nil
package.loaded['custom.plugins.ensure'] = nil

local ensure = require 'custom.ensure_tool'

-- Isolate installs under a temp directory (avoid polluting real stdpath).
local tmp = vim.fn.tempname() .. '-kickstart-tools-e2e'
vim.fn.mkdir(tmp, 'p')
ensure.tools_root = function() return tmp end
ensure.bin_dir = function() return vim.fs.joinpath(tmp, 'bin') end

local function assert_tool(ok, path, label)
  harness.assert_truthy(ok, label .. ': ' .. tostring(path))
  harness.assert_truthy(path and (vim.fn.executable(path) == 1), label .. ' executable')
end

local ok_rg, path_rg = ensure.ensure_ripgrep()
assert_tool(ok_rg, path_rg, 'ripgrep')
harness.ok('ripgrep installed: ' .. path_rg)

local ok_fd, path_fd = ensure.ensure_fd()
assert_tool(ok_fd, path_fd, 'fd')
harness.ok('fd installed: ' .. path_fd)

local ok_lg, path_lg = ensure.ensure_lazygit()
assert_tool(ok_lg, path_lg, 'lazygit')
local ver = vim.system({ path_lg, '--version' }, { text = true }):wait()
harness.assert_eq(ver.code, 0, 'lazygit --version')
harness.ok('lazygit installed: ' .. path_lg)

local ok_ld, path_ld = ensure.ensure_lazydocker()
assert_tool(ok_ld, path_ld, 'lazydocker')
local ver_ld = vim.system({ path_ld, '--version' }, { text = true }):wait()
if ver_ld.code ~= 0 then ver_ld = vim.system({ path_ld, '-v' }, { text = true }):wait() end
harness.assert_eq(ver_ld.code, 0, 'lazydocker version')
harness.ok('lazydocker installed: ' .. path_ld)

local ok_rf, path_rf = ensure.ensure_rainfrog()
assert_tool(ok_rf, path_rf, 'rainfrog')
local ver_rf = vim.system({ path_rf, '--version' }, { text = true }):wait()
harness.assert_eq(ver_rf.code, 0, 'rainfrog --version')
harness.ok('rainfrog installed: ' .. path_rf)

local ok_mvn, path_mvn = ensure.ensure_maven()
assert_tool(ok_mvn, path_mvn, 'maven')
harness.ok('maven installed: ' .. path_mvn)

-- Plugin commands / keymaps
require 'custom.plugins.lazy-tui'
require 'custom.plugins.ensure'
harness.assert_truthy(harness.command_exists 'LazyGit', ':LazyGit')
harness.assert_truthy(harness.command_exists 'LazyDocker', ':LazyDocker')
harness.assert_truthy(harness.command_exists 'Rainfrog', ':Rainfrog')
harness.assert_truthy(harness.command_exists 'KickstartEnsureTools', ':KickstartEnsureTools')
harness.assert_truthy(harness.map_exists '<leader>gg', '<leader>gg')
harness.assert_truthy(harness.map_exists '<leader>ld', '<leader>ld')
harness.assert_truthy(harness.map_exists '<leader>db', '<leader>db')

local tui = require 'custom.plugins.lazy-tui'
local ok_open = pcall(tui.open_lazygit)
harness.assert_truthy(ok_open, 'open_lazygit headless')
local ok_open_rf = pcall(tui.open_rainfrog)
harness.assert_truthy(ok_open_rf, 'open_rainfrog headless')
harness.ok 'lazy-tui headless open'

harness.ok 'ensure_tool / lazy-tui e2e'
vim.cmd 'qa!'
