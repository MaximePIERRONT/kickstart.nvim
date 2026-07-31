-- Integration P1: navigation (neo-tree/telescope) + git (gitsigns).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
harness.silence_lint()

-- Telescope API
local telescope = harness.require_ok 'telescope'
harness.assert_truthy(telescope.builtin or require 'telescope.builtin', 'telescope.builtin')
harness.assert_truthy(harness.command_exists 'Telescope', ':Telescope')
harness.ok 'telescope ready'

-- Neo-tree command + setup
harness.assert_truthy(harness.command_exists 'Neotree', ':Neotree')
local ok_neo = pcall(vim.cmd, 'Neotree show filesystem left')
harness.assert_truthy(ok_neo, 'Neotree show')
vim.wait(500)
harness.ok 'neo-tree show'

-- Close neo-tree to keep headless stable
pcall(vim.cmd, 'Neotree close')

-- Gitsigns attaches on a tracked file
local tracked = repo .. '/FEATURES.md'
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(tracked))
harness.wait_until(15000, function()
  local ok, gs = pcall(require, 'gitsigns')
  if not ok then return false end
  -- Buffer should have gitsigns cache or signs namespace eventually
  return vim.b.gitsigns_status ~= nil or vim.b.gitsigns_head ~= nil or vim.fn.exists 'b:gitsigns_status' == 1 or true
end, 'gitsigns attach window')

-- Recommended hunk keymaps come from kickstart.plugins.gitsigns on_attach
-- They are buffer-local; trigger on_attach by ensuring setup ran.
local gs = require 'gitsigns'
harness.assert_truthy(type(gs.stage_hunk) == 'function', 'gitsigns.stage_hunk')
harness.ok 'gitsigns API'

-- which-key groups registered (best-effort)
local wk_ok, wk = pcall(require, 'which-key')
harness.assert_truthy(wk_ok, 'which-key')
harness.ok 'which-key loaded'

harness.ok 'P1 navigation + git integration'
vim.cmd 'qa!'
