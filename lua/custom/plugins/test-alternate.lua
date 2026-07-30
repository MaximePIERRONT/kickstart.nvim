-- Lazy.nvim plugin: source ↔ test navigation (IntelliJ Ctrl+Shift+T).
--
-- Keymaps:
--   <C-S-t>       toggle source ↔ test
--   <leader>jT    same via leader ([J]ava test [T]oggle file)

local M = require 'custom.test_alternate'

return {
  {
    'test-alternate.nvim',
    virtual = true,
    keys = {
      { '<C-S-t>', function() M.toggle() end, desc = 'Toggle source/test file' },
      { '<leader>jT', function() M.toggle() end, desc = '[J]ava test [T]oggle source/test file' },
    },
    config = function() M.setup() end,
  },
}
