-- Revue de merge request façon GitLab dans IntelliJ :
-- liste des MR/PR → checkout d'une branche `review/mr-N` (ou `review/pr-N`) →
-- panneau de fichiers + diffs côte à côte (diffview.nvim, three-dot vs la cible).

local mr = require 'custom.merge_request'

vim.pack.add {
  { src = 'https://github.com/sindrets/diffview.nvim', version = vim.version.range '*' },
}

require('diffview').setup {
  enhanced_diff_hl = true,
  view = {
    default = { layout = 'diff2_horizontal' },
    merge_tool = { layout = 'diff3_horizontal' },
  },
  file_panel = {
    listing_style = 'tree',
    win_config = { position = 'left', width = 40 },
  },
}

local M = {}

---@param range string
---@return boolean
---@return string|nil
function M.open_review(range)
  if #vim.api.nvim_list_uis() == 0 then
    vim.notify('Revue ' .. range .. ' (headless)', vim.log.levels.INFO)
    return true, range
  end
  local ok, err = pcall(vim.cmd, 'DiffviewOpen ' .. range)
  if not ok then
    vim.notify('Diffview: ' .. tostring(err), vim.log.levels.ERROR)
    return false, tostring(err)
  end
  return true, range
end

function M.close_review()
  if vim.fn.exists ':DiffviewClose' == 2 then vim.cmd 'DiffviewClose' end
end

---@param item kickstart.MR
---@param cwd string|nil
local function review_item(item, cwd)
  cwd = cwd or mr.git_root()
  local target = mr.resolve_target(item, cwd)

  if item.type == 'mr' then
    vim.notify(string.format('Checkout revue %s…', mr.format_item(item)), vim.log.levels.INFO)
    local ok, branch_or_err = mr.checkout_mr(item, { cwd = cwd })
    if not ok then
      vim.notify(branch_or_err, vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format('Branche %s — diffs vs %s', branch_or_err, target), vim.log.levels.INFO)
  elseif item.type == 'local' and item.branch then
    local ok, branch_or_err = mr.checkout_local(item.branch, { cwd = cwd })
    if not ok then
      vim.notify(branch_or_err, vim.log.levels.ERROR)
      return
    end
  end

  M.open_review(mr.diff_range(target))
end

function M.review_current()
  local cwd = mr.git_root()
  if not cwd then
    vim.notify('Pas un dépôt git', vim.log.levels.ERROR)
    return
  end
  local target = mr.default_target(cwd)
  vim.notify('Revue de la branche courante vs ' .. target, vim.log.levels.INFO)
  M.open_review(mr.diff_range(target))
end

---@param iid string|nil
function M.pick_or_checkout(iid)
  local cwd = mr.git_root()
  if not cwd then
    vim.notify('Pas un dépôt git', vim.log.levels.ERROR)
    return
  end

  if iid and iid ~= '' then
    local ok, branch_or_err = mr.checkout_by_iid(iid, { cwd = cwd })
    if not ok then
      vim.notify(branch_or_err, vim.log.levels.ERROR)
      return
    end
    local target = mr.default_target(cwd)
    vim.notify(string.format('Branche %s — diffs vs %s', branch_or_err, target), vim.log.levels.INFO)
    M.open_review(mr.diff_range(target))
    return
  end

  local items, err = mr.picker_items(cwd)
  if err and #items == 0 then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if #items == 0 then
    vim.notify('Aucune merge request / branche à revoir', vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = 'Revue merge request (GitLab / GitHub)',
    format_item = mr.format_item,
  }, function(choice)
    if choice then review_item(choice, cwd) end
  end)
end

vim.api.nvim_create_user_command('MergeRequest', function(opts) M.pick_or_checkout(opts.args) end, {
  nargs = '?',
  desc = 'Checkout une MR/PR sur une branche review/* et ouvrir les diffs (comme GitLab dans IntelliJ)',
})

vim.api.nvim_create_user_command('MergeRequestReview', function() M.review_current() end, {
  desc = 'Ouvrir la revue de la branche courante vs la branche cible (Diffview three-dot)',
})

vim.api.nvim_create_user_command('MergeRequestClose', function() M.close_review() end, {
  desc = 'Fermer la vue de revue (Diffview)',
})

vim.keymap.set('n', '<leader>gm', function() M.pick_or_checkout() end, { desc = '[G]it [M]erge request (checkout + revue)', silent = true })
vim.keymap.set('n', '<leader>gr', function() M.review_current() end, { desc = '[G]it [R]eview branche courante', silent = true })
vim.keymap.set('n', '<leader>gC', function() M.close_review() end, { desc = '[G]it [C]lose revue', silent = true })

return M
