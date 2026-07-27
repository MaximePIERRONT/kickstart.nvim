-- Unit tests: custom.ensure_tool helpers (no network for URL/os_arch).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.ensure_tool'] = nil
local ensure = require 'custom.ensure_tool'

local sys, arch = ensure.os_arch()
harness.assert_truthy(sys == 'linux' or sys == 'darwin' or sys == 'windows', 'os sys')
harness.assert_truthy(arch ~= nil and arch ~= '', 'os arch')
harness.ok('os_arch=' .. sys .. '/' .. arch)

-- Asset URL naming (linux x86_64)
local url_lg = select(1, ensure.jesseduffield_asset_url('jesseduffield/lazygit', 'v0.63.1', 'lazygit'))
harness.assert_truthy(url_lg, 'lazygit url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_lg, 'lazygit_0.63.1_linux_x86_64.tar.gz', 'lazygit linux asset')
end
harness.ok 'lazygit asset url'

local url_ld = select(1, ensure.jesseduffield_asset_url('jesseduffield/lazydocker', 'v0.25.2', 'lazydocker'))
harness.assert_truthy(url_ld, 'lazydocker url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_ld, 'lazydocker_0.25.2_Linux_x86_64.tar.gz', 'lazydocker linux asset')
end
harness.ok 'lazydocker asset url'

-- tools root / bin dir
local root = ensure.tools_root()
harness.assert_has(root, 'kickstart-tools', 'tools_root')
ensure.prepend_path()
harness.assert_has(vim.env.PATH or '', ensure.bin_dir(), 'PATH prepend')
harness.ok 'tools paths'

-- find_executable: known system binary
local sh = ensure.find_executable 'sh'
harness.assert_truthy(sh, 'find sh')
harness.ok 'find_executable'

harness.ok 'ensure_tool unit suite'
vim.cmd 'qa!'
