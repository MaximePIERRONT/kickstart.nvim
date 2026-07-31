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

local url_ls = select(1, ensure.lazysql_asset_url 'v0.5.5')
harness.assert_truthy(url_ls, 'lazysql url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_ls, 'lazysql_Linux_x86_64.tar.gz', 'lazysql linux asset')
end
harness.ok 'lazysql asset url'

-- ripgrep / fd / node asset URLs (linux x86_64)
local url_rg = select(1, ensure.ripgrep_asset_url '15.2.0')
harness.assert_truthy(url_rg, 'ripgrep url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_rg, 'ripgrep-15.2.0-x86_64-unknown-linux-musl.tar.gz', 'rg linux musl')
end
harness.ok 'ripgrep asset url'

local url_fd = select(1, ensure.fd_asset_url 'v10.4.2')
harness.assert_truthy(url_fd, 'fd url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_fd, 'fd-v10.4.2-x86_64-unknown-linux-musl.tar.gz', 'fd linux musl')
end
harness.ok 'fd asset url'

local url_node = select(1, ensure.nodejs_asset_url 'v24.18.0')
harness.assert_truthy(url_node, 'nodejs url')
if sys == 'linux' and arch == 'x86_64' then
  harness.assert_has(url_node, 'node-v24.18.0-linux-x64.tar.xz', 'node linux x64 xz')
end
harness.ok 'nodejs asset url'

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

-- required system packages list (docs / health)
local pkgs = ensure.required_system_packages()
harness.assert_truthy(type(pkgs) == 'table' and #pkgs >= 4, 'required_system_packages')
local joined = table.concat(pkgs, ',')
harness.assert_has(joined, 'git', 'req git')
harness.assert_has(joined, 'curl', 'req curl')
harness.ok 'required_system_packages'

-- A project may intentionally set JAVA_HOME to an older JDK.  A managed JDK
-- 21 must still be reused instead of downloading it again on every startup.
do
  local temp = vim.fn.tempname()
  local old_home = vim.fs.joinpath(temp, 'java-17')
  local managed_home = vim.fs.joinpath(temp, 'kickstart-tools', 'jdk-21')
  vim.fn.mkdir(vim.fs.joinpath(old_home, 'bin'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(managed_home, 'bin'), 'p')
  vim.fn.writefile({ '' }, vim.fs.joinpath(old_home, 'bin', 'java'))
  vim.fn.writefile({ '' }, vim.fs.joinpath(managed_home, 'bin', 'java'))

  local original_tools_root = ensure.tools_root
  local original_java_major_version = ensure.java_major_version
  local original_download = ensure.download
  local original_java_home = vim.env.JAVA_HOME
  local original_jdtls_java_home = vim.env.JDTLS_JAVA_HOME
  local downloaded = false

  ensure.tools_root = function() return vim.fs.joinpath(temp, 'kickstart-tools') end
  ensure.java_major_version = function(java)
    return java:find('/java%-17/', 1, false) and 17 or 21
  end
  ensure.download = function()
    downloaded = true
    return false, 'test download must not run'
  end
  vim.env.JAVA_HOME = old_home
  vim.env.JDTLS_JAVA_HOME = nil

  local ok, home = ensure.ensure_jdk21()
  harness.assert_truthy(ok, 'reuse managed JDK 21 with older JAVA_HOME')
  harness.assert_eq(home, managed_home, 'managed JDK selected')
  harness.assert_truthy(not downloaded, 'managed JDK is not downloaded again')

  ensure.tools_root = original_tools_root
  ensure.java_major_version = original_java_major_version
  ensure.download = original_download
  vim.env.JAVA_HOME = original_java_home
  vim.env.JDTLS_JAVA_HOME = original_jdtls_java_home
  vim.fn.delete(temp, 'rf')
end
harness.ok 'managed JDK 21 reuse'

harness.ok 'ensure_tool unit suite'
vim.cmd 'qa!'
