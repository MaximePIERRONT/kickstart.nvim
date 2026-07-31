-- debug.lua
--
-- DAP for this kickstart fork: Java (jdtls + java-debug-adapter) and JS/TS
-- (js-debug-adapter). Go/delve from upstream kickstart is intentionally omitted.

vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/rcarriga/nvim-dap-ui',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/mason-org/mason.nvim',
  'https://github.com/jay-babu/mason-nvim-dap.nvim',
  'https://github.com/mfussenegger/nvim-jdtls',
}

-- Basic debugging keymaps
vim.keymap.set('n', '<F5>', function() require('dap').continue() end, { desc = 'Debug: Start/Continue' })
vim.keymap.set('n', '<F1>', function() require('dap').step_into() end, { desc = 'Debug: Step Into' })
vim.keymap.set('n', '<F2>', function() require('dap').step_over() end, { desc = 'Debug: Step Over' })
vim.keymap.set('n', '<F3>', function() require('dap').step_out() end, { desc = 'Debug: Step Out' })
vim.keymap.set('n', '<leader>b', function() require('dap').toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
vim.keymap.set('n', '<leader>B', function() require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, { desc = 'Debug: Set Breakpoint' })
-- Toggle to see last session result. Without this, you can't see session output in case of unhandled exception.
vim.keymap.set('n', '<F7>', function() require('dapui').toggle() end, { desc = 'Debug: See last session result.' })

local dap = require 'dap'
local dapui = require 'dapui'

-- Adapters are installed by mason-tool-installer in init.lua (java-debug-adapter,
-- js-debug-adapter). Do NOT also ensure_installed here — dual install on startup
-- races Mason ("Package is already installing") and flakes CI.
require('mason-nvim-dap').setup {
  automatic_installation = false,
  -- Default handlers for everything except Java: nvim-jdtls owns the `java` DAP adapter
  -- once java-debug-adapter bundles are loaded into jdtls (see init.lua).
  handlers = {
    function(config) require('mason-nvim-dap').default_setup(config) end,
    javadbg = function() end,
    javatest = function() end,
  },
  ensure_installed = {},
}

-- Wire js-debug-adapter (pwa-node) when the Mason package is present.
do
  local dap_server = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'packages', 'js-debug-adapter', 'js-debug', 'src', 'dapDebugServer.js')
  if vim.uv.fs_stat(dap_server) then
    dap.adapters['pwa-node'] = {
      type = 'server',
      host = 'localhost',
      port = '${port}',
      executable = {
        command = 'node',
        args = { dap_server, '${port}' },
      },
    }
  end
end

-- Dap UI setup
-- For more information, see |:help nvim-dap-ui|
---@diagnostic disable-next-line: missing-fields
dapui.setup {
  -- Set icons to characters that are more likely to work in every terminal.
  icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
  ---@diagnostic disable-next-line: missing-fields
  controls = {
    icons = {
      pause = '⏸',
      play = '▶',
      step_into = '⏎',
      step_over = '⏭',
      step_out = '⏮',
      step_back = 'b',
      run_last = '▶▶',
      terminate = '⏹',
      disconnect = '⏏',
    },
  },
}

dap.listeners.after.event_initialized['dapui_config'] = dapui.open
dap.listeners.before.event_terminated['dapui_config'] = dapui.close
dap.listeners.before.event_exited['dapui_config'] = dapui.close

-- JS / TS: pwa-node via mason js-debug-adapter (handlers above usually cover this;
-- keep explicit configs so F5 works in a typical Node project without launch.json).
for _, language in ipairs { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' } do
  dap.configurations[language] = {
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch current file',
      program = '${file}',
      cwd = '${workspaceFolder}',
    },
    {
      type = 'pwa-node',
      request = 'attach',
      name = 'Attach',
      processId = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
    },
  }
end

---Wire nvim-jdtls DAP helpers once java-debug-adapter bundles are loaded in jdtls.
local function setup_java_dap()
  local ok, jdtls = pcall(require, 'jdtls')
  if not ok then return end
  jdtls.setup_dap { hotcodereplace = 'auto' }
  pcall(function() require('jdtls.dap').setup_dap_main_class_configs() end)
end

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('kickstart-java-dap', { clear = true }),
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and client.name == 'jdtls' then setup_java_dap() end
  end,
})

-- If jdtls already attached when this module loads, wire DAP immediately.
for _, client in ipairs(vim.lsp.get_clients { name = 'jdtls' }) do
  if client then setup_java_dap() end
end
