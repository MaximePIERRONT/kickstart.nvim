-- Unit tests: custom.plugins.herdr (config paths + install merge, no live Herdr).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.plugins.herdr'] = nil
local herdr = require 'custom.plugins.herdr'

local bundled = herdr.bundled_config_path()
harness.assert_truthy(vim.uv.fs_stat(bundled), 'bundled config exists')
local text = table.concat(vim.fn.readfile(bundled), '\n')
harness.assert_has(text, 'new_tab', 'new_tab binding')
harness.assert_has(text, 'ctrl+alt+c', 'direct new tab chord')
harness.assert_has(text, 'lazygit', 'lazygit popup')
harness.assert_has(text, 'lazydocker', 'lazydocker popup')
harness.assert_has(text, 'width = "100%"', 'fullscreen width')
harness.assert_has(text, 'height = "100%"', 'fullscreen height')
harness.ok 'bundled herdr config'

-- Isolate user config path under TMPDIR
local tmp = vim.fs.joinpath(vim.fn.tempname() .. '-herdr-test')
vim.fn.mkdir(tmp, 'p')
vim.env.HERDR_CONFIG_PATH = vim.fs.joinpath(tmp, 'config.toml')

local ok_write, msg_write = herdr.install_config()
harness.assert_truthy(ok_write, 'install_config write: ' .. tostring(msg_write))
harness.assert_truthy(vim.uv.fs_stat(vim.env.HERDR_CONFIG_PATH), 'user config created')
local installed = table.concat(vim.fn.readfile(vim.env.HERDR_CONFIG_PATH), '\n')
harness.assert_has(installed, '# BEGIN kickstart.nvim herdr keys', 'begin mark')
harness.assert_has(installed, 'prefix+alt+g', 'lazygit key')
harness.assert_has(installed, 'prefix+alt+d', 'lazydocker key')
harness.ok 'install_config creates file'

-- Pre-existing config: merge without losing user content
vim.fn.writefile({ '# user setting', 'onboarding = false', '' }, vim.env.HERDR_CONFIG_PATH)
local ok_merge, msg_merge = herdr.install_config()
harness.assert_truthy(ok_merge, 'install_config merge: ' .. tostring(msg_merge))
local merged = table.concat(vim.fn.readfile(vim.env.HERDR_CONFIG_PATH), '\n')
harness.assert_has(merged, 'onboarding = false', 'preserved user setting')
harness.assert_has(merged, '# BEGIN kickstart.nvim herdr keys', 'managed block added')
harness.assert_truthy(vim.uv.fs_stat(vim.env.HERDR_CONFIG_PATH .. '.bak-kickstart'), 'backup created')
harness.ok 'install_config merges'

-- Idempotent re-install
local ok_again, msg_again = herdr.install_config()
harness.assert_truthy(ok_again, 'reinstall: ' .. tostring(msg_again))
local again = table.concat(vim.fn.readfile(vim.env.HERDR_CONFIG_PATH), '\n')
local _, count_begin = again:gsub('# BEGIN kickstart.nvim herdr keys', '')
harness.assert_eq(count_begin, 1, 'single managed block after reinstall')
harness.ok 'install_config idempotent'

-- new_tab without herdr session fails clearly
vim.env.HERDR_SOCKET_PATH = nil
vim.env.HERDR_PANE_ID = nil
vim.env.HERDR_TAB_ID = nil
harness.assert_eq(herdr.inside_herdr(), false, 'inside_herdr false')
local ok_tab, err_tab = herdr.new_tab()
harness.assert_eq(ok_tab, false, 'new_tab fails outside herdr')
harness.assert_truthy(err_tab and err_tab ~= '', 'new_tab error message')
harness.ok 'new_tab guard'

harness.ok 'herdr unit'
vim.cmd 'qa!'
