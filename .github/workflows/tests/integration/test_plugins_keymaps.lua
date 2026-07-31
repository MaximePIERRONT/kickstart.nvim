-- Integration: keymaps / user commands for delivered features.
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')

vim.g.mapleader = vim.g.mapleader or ' '

local expected_maps = {
  -- P1 navigation / git
  { '\\', 'neo-tree reveal' },
  { '<leader>e', 'neo-tree toggle' },
  { '<leader>t', 'alternate source↔test' },
  -- P1 runners
  { '<leader>rd', 'npm dev' },
  { '<leader>rb', 'npm build' },
  { '<leader>rt', 'npm test' },
  { '<leader>rs', 'npm script' },
  { '<leader>rc', 'maven compile' },
  { '<leader>rp', 'maven package' },
  { '<leader>rm', 'micronaut' },
  { '<leader>rM', 'micronaut config' },
  { '<leader>rj', 'java run' },
  { '<leader>rg', 'maven goals' },
  -- P2 tests
  { '<leader>jt', 'java test class' },
  { '<leader>jm', 'java test method' },
  { '<leader>ja', 'java test all' },
  { '<leader>jf', 'java formatter selector' },
  -- P2 debug
  { '<leader>b', 'breakpoint' },
  { '<leader>B', 'conditional breakpoint' },
  { '<F5>', 'dap continue' },
  { '<F1>', 'dap step into' },
  { '<F2>', 'dap step over' },
  { '<F3>', 'dap step out' },
  { '<F7>', 'dapui toggle' },
  -- P2 LazyGit / LazyDocker / LazySQL
  { '<leader>gg', 'lazygit' },
  { '<leader>ld', 'lazydocker' },
  { '<leader>ls', 'lazysql' },
}

for _, item in ipairs(expected_maps) do
  if not harness.map_exists(item[1]) then
    harness.fail('missing keymap ' .. item[1] .. ' (' .. item[2] .. ')')
  end
  harness.ok('keymap ' .. item[1])
end

local commands = { 'Npm', 'Maven', 'Micronaut', 'RunConfig', 'MavenTest', 'JavaFormat', 'Neotree', 'Telescope', 'LazyGit', 'LazyDocker', 'LazySQL', 'KickstartEnsureTools', 'AlternateTest' }
for _, name in ipairs(commands) do
  if not harness.command_exists(name) then harness.fail('missing command :' .. name) end
  harness.ok('command :' .. name)
end

harness.ok 'keymaps + commands integration'
vim.cmd 'qa!'
