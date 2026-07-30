-- Unit tests: JDK 21 must not re-download when kickstart-tools/jdk-21 exists
-- but the shell still exports an older JAVA_HOME (common on Linux).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

---@param home string JDK root
---@param major number Java major version reported by mock bin/java
---@return string home
local function write_mock_jdk(home, major)
  local bin = vim.fs.joinpath(home, 'bin')
  vim.fn.mkdir(bin, 'p')
  local java = vim.fs.joinpath(bin, 'java')
  local version = major < 9 and string.format('1.%d.0', major) or string.format('%d.0.0', major)
  vim.fn.writefile({
    '#!/bin/sh',
    string.format('echo \'openjdk version "%s" 2024-01-01\' >&2', version),
  }, java)
  vim.fn.setfperm(java, 'rwxr-xr-x')
  return home
end

package.loaded['custom.ensure_tool'] = nil
local ensure = require 'custom.ensure_tool'

local jdk21_home = write_mock_jdk(vim.fn.tempname() .. '-jdk21', 21)
local jdk17_home = write_mock_jdk(vim.fn.tempname() .. '-jdk17', 17)
local jdk8_home = write_mock_jdk(vim.fn.tempname() .. '-jdk8', 8)

harness.assert_eq(ensure.java_major_version(vim.fs.joinpath(jdk21_home, 'bin', 'java')), 21, 'parse java 21')
harness.assert_eq(ensure.java_major_version(vim.fs.joinpath(jdk17_home, 'bin', 'java')), 17, 'parse java 17')
harness.assert_eq(ensure.java_major_version(vim.fs.joinpath(jdk8_home, 'bin', 'java')), 8, 'parse java 8')
harness.ok 'java_major_version'

local tmp_tools = vim.fn.tempname() .. '-kickstart-tools-jdk'
vim.fn.mkdir(tmp_tools, 'p')
local managed_home = write_mock_jdk(vim.fs.joinpath(tmp_tools, 'jdk-21'), 21)

package.loaded['custom.ensure_tool'] = nil
local ensure_isolated = require 'custom.ensure_tool'
ensure_isolated.tools_root = function() return tmp_tools end

local saved_java_home = vim.env.JAVA_HOME
local saved_jdtls = vim.env.JDTLS_JAVA_HOME
vim.env.JAVA_HOME = jdk17_home
vim.env.JDTLS_JAVA_HOME = nil

-- Managed jdk-21 must be preferred over a stale shell JAVA_HOME.
harness.assert_eq(ensure_isolated.existing_jdk_home(), managed_home, 'existing_jdk_home prefers managed jdk-21')
harness.assert_eq(ensure_isolated.find_jdk21_home(), managed_home, 'find_jdk21_home prefers managed jdk-21')

local download_called = false
ensure_isolated.download = function()
  download_called = true
  return false, 'download should not be called'
end

local ok, home = ensure_isolated.ensure_jdk21()
harness.assert_truthy(ok, 'ensure_jdk21 ok with stale JAVA_HOME')
harness.assert_eq(home, managed_home, 'ensure_jdk21 uses managed jdk-21')
harness.assert_eq(vim.env.JDTLS_JAVA_HOME, managed_home, 'JDTLS_JAVA_HOME points to managed jdk-21')
harness.assert_truthy(not download_called, 'no download when managed jdk-21 is valid')

local ok2, home2 = ensure_isolated.ensure_jdk21()
harness.assert_truthy(ok2, 'second ensure_jdk21 ok')
harness.assert_eq(home2, managed_home, 'second call still uses managed jdk-21')
harness.assert_truthy(not download_called, 'second startup does not re-download')

vim.env.JAVA_HOME = saved_java_home
vim.env.JDTLS_JAVA_HOME = saved_jdtls

harness.ok 'ensure_tool jdk21 idempotency suite'
vim.cmd 'qa!'
