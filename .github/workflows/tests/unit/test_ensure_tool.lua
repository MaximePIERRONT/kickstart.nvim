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

-- JDK 21 reuse: old JAVA_HOME must not force a re-download when managed jdk-21 exists.
do
  local tmp = vim.fn.tempname()
  local old_home = vim.fs.joinpath(tmp, 'jdk-17')
  local managed = vim.fs.joinpath(tmp, 'kickstart-tools', 'jdk-21')
  vim.fn.mkdir(vim.fs.joinpath(old_home, 'bin'), 'p')
  vim.fn.mkdir(vim.fs.joinpath(managed, 'bin'), 'p')

  local function write_fake_java(bin_dir, major)
    local path = vim.fs.joinpath(bin_dir, 'java')
    local script = table.concat({
      '#!/bin/sh',
      string.format('echo \'openjdk version "%s.0.2" 2024-01-16\' >&2', major),
      'exit 0',
      '',
    }, '\n')
    vim.fn.writefile(vim.split(script, '\n', { plain = true }), path)
    vim.fn.setfperm(path, 'rwxr-xr-x')
  end

  write_fake_java(vim.fs.joinpath(old_home, 'bin'), 17)
  write_fake_java(vim.fs.joinpath(managed, 'bin'), 21)

  local prev_java_home = vim.env.JAVA_HOME
  local prev_jdtls = vim.env.JDTLS_JAVA_HOME
  local real_tools_root = ensure.tools_root
  local download_calls = 0
  local real_download = ensure.download

  ensure.tools_root = function() return vim.fs.joinpath(tmp, 'kickstart-tools') end
  ensure.download = function(...)
    download_calls = download_calls + 1
    return real_download(...)
  end
  vim.env.JAVA_HOME = old_home
  vim.env.JDTLS_JAVA_HOME = nil

  local found = ensure.existing_jdk_home()
  harness.assert_eq(found, managed, 'existing_jdk_home prefers managed 21 over JAVA_HOME 17')

  local ok, home = ensure.ensure_jdk21()
  harness.assert_truthy(ok, 'ensure_jdk21 ok with managed JDK')
  harness.assert_eq(home, managed, 'ensure_jdk21 returns managed JDK')
  harness.assert_eq(download_calls, 0, 'ensure_jdk21 must not re-download JDK 21')
  harness.assert_eq(vim.env.JDTLS_JAVA_HOME, managed, 'JDTLS_JAVA_HOME set to managed JDK')

  -- Second call (simulate reopening a Java project / Neovim restart with same env)
  ok, home = ensure.ensure_jdk21()
  harness.assert_truthy(ok, 'ensure_jdk21 idempotent')
  harness.assert_eq(home, managed, 'ensure_jdk21 still managed')
  harness.assert_eq(download_calls, 0, 'second ensure_jdk21 still no download')

  ensure.tools_root = real_tools_root
  ensure.download = real_download
  vim.env.JAVA_HOME = prev_java_home
  vim.env.JDTLS_JAVA_HOME = prev_jdtls
  vim.fn.delete(tmp, 'rf')
  harness.ok 'jdk21 reuse skips reinstall when JAVA_HOME is older'
end

harness.ok 'ensure_tool unit suite'
vim.cmd 'qa!'
