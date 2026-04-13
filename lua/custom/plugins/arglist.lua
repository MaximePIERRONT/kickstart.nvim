local function get_arglist()
  local args = vim.fn.argv()
  if #args == 0 then
    return nil, 'Arg list is empty'
  end
  return args
end

local function buf_in_arglist(bufnr)
  local args = vim.fn.argv()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  for _, arg in ipairs(args) do
    if arg == bufname then
      return true
    end
  end
  return false
end

local function toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == '' then
    vim.notify('Cannot pin unnamed buffer', vim.log.levels.WARN)
    return
  end

  if buf_in_arglist(bufnr) then
    vim.cmd('argdelete ' .. vim.fn.shellescape(bufname))
    vim.notify('Unpinned: ' .. vim.fs.basename(bufname), vim.log.levels.INFO)
  else
    vim.cmd('argadd ' .. vim.fn.shellescape(bufname))
    vim.notify('Pinned: ' .. vim.fs.basename(bufname), vim.log.levels.INFO)
  end
end

local function list()
  local args = get_arglist()
  if not args then
    vim.notify('Arg list is empty. Use <leader>aa to pin files.', vim.log.levels.INFO)
    return
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local sorters = require('telescope.sorters')
  local actions = require('telescope.actions')
  local action_set = require('telescope.actions.set')

  local results = {}
  for i, arg in ipairs(args) do
    local name = vim.fs.basename(arg)
    table.insert(results, {
      index = i,
      name = name,
      path = arg,
      display = string.format('%d: %s', i, name),
    })
  end

  pickers.new({}, {
    prompt_title = 'Pinned Files',
    results_title = 'Arg List',
    finder = finders.new_table({
      results = results,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
          path = entry.path,
        }
      end,
    }),
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, _map)
      actions.select_default:replace(function()
        local selection = action_set.get_selected_entry()
        if selection then
          local entry = selection.value
          vim.cmd('argdelete *')
          vim.cmd('argadd ' .. vim.fn.shellescape(entry.path))
          vim.cmd('edit ' .. vim.fn.shellescape(entry.path))
          actions.close(prompt_bufnr)
        end
      end)
      return true
    end,
  }):find()
end

local function next_file()
  vim.cmd('next')
end

local function prev_file()
  vim.cmd('previous')
end

local function clear()
  vim.cmd('argdelete *')
  vim.notify('Arg list cleared', vim.log.levels.INFO)
end

---@type LazySpec
return {
  'custom.plugins.arglist',
  keys = {
    { '<leader>aa', toggle, desc = '[A]rglist: toggle [a]dd current file' },
    { '<leader>al', list, desc = '[A]rglist: [l]ist pinned files' },
    { '<leader>an', next_file, desc = '[A]rglist: [n]ext file' },
    { '<leader>ap', prev_file, desc = '[A]rglist: [p]revious file' },
    { '<leader>ac', clear, desc = '[A]rglist: [c]lear all' },
  },
}
