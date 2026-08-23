-- E2E: checkout a GitLab-style MR ref onto review/mr-N (local git remotes, no network).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.merge_request'] = nil
local mr = require 'custom.merge_request'

local tmp = vim.fn.tempname() .. '-mr-review-e2e'
vim.fn.mkdir(tmp, 'p')
local bare = tmp .. '/remote.git'
local work = tmp .. '/work'
vim.fn.mkdir(bare, 'p')
vim.fn.mkdir(work, 'p')

---@param args string[]
---@param cwd string
---@return vim.SystemCompleted
local function git(args, cwd)
  local result = vim.system(vim.list_extend({ 'git' }, args), { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    harness.fail(string.format('git %s (cwd=%s): %s', table.concat(args, ' '), cwd, result.stderr or result.stdout or ''))
  end
  return result
end

git({ 'init', '--bare', '-b', 'master' }, bare)
git({ 'clone', bare, work }, tmp)
git({ 'config', 'user.email', 'kickstart@example.com' }, work)
git({ 'config', 'user.name', 'Kickstart Test' }, work)
vim.fn.writefile({ 'base' }, work .. '/app.txt')
git({ 'add', 'app.txt' }, work)
git({ 'commit', '-m', 'init' }, work)
git({ 'push', '-u', 'origin', 'master' }, work)
git({ 'symbolic-ref', 'HEAD', 'refs/heads/master' }, bare)

git({ 'checkout', '-b', 'feat/widget' }, work)
vim.fn.writefile({ 'base', 'feature-change' }, work .. '/app.txt')
git({ 'add', 'app.txt' }, work)
git({ 'commit', '-m', 'feat: widget' }, work)
local feature_sha = vim.trim(git({ 'rev-parse', 'HEAD' }, work).stdout)
git({ 'push', '-u', 'origin', 'feat/widget' }, work)
git({ 'update-ref', 'refs/merge-requests/7/head', feature_sha }, bare)

-- Back to master so checkout creates review/mr-7 from the MR ref (not the feature branch).
git({ 'checkout', 'master' }, work)
harness.assert_eq(vim.trim(git({ 'branch', '--show-current' }, work).stdout), 'master', 'on master before checkout')

local kind, parsed = mr.detect_kind(work)
harness.assert_eq(kind, 'gitlab', 'detect gitlab via merge-requests refs')
harness.assert_truthy(parsed == nil or parsed.kind == 'unknown' or parsed.path ~= nil, 'parsed remote')
harness.ok 'detect_kind gitlab'

local refs = mr.list_remote_refs(work, 'gitlab')
harness.assert_eq(#refs, 1, 'one MR ref')
harness.assert_eq(refs[1].iid, 7, 'MR iid 7')
harness.assert_eq(refs[1].sha, feature_sha, 'MR sha')
harness.ok 'list_remote_refs'

local items = mr.picker_items(work)
harness.assert_eq(items[1].type, 'current', 'first item is current branch')
local found_mr
for _, item in ipairs(items) do
  if item.type == 'mr' and item.iid == 7 then found_mr = item end
end
harness.assert_truthy(found_mr, 'picker includes MR 7')
harness.ok 'picker_items'

local target = mr.default_target(work)
harness.assert_eq(target, 'origin/master', 'default target origin/master')
harness.assert_eq(mr.diff_range(target), 'origin/master...HEAD', 'three-dot')
harness.ok 'default_target'

local ok, branch = mr.checkout_mr({ type = 'mr', kind = 'gitlab', iid = 7 }, { cwd = work })
harness.assert_truthy(ok, 'checkout_mr: ' .. tostring(branch))
harness.assert_eq(branch, 'review/mr-7', 'review branch name')
harness.assert_eq(mr.current_branch(work), 'review/mr-7', 'current branch after checkout')
local body = table.concat(vim.fn.readfile(work .. '/app.txt'), '\n')
harness.assert_has(body, 'feature-change', 'review branch has MR content')
harness.ok 'checkout_mr review/mr-7'

-- Dirty tree refuses a second checkout onto another iid (simulate by editing).
vim.fn.writefile({ 'base', 'feature-change', 'local-edit' }, work .. '/app.txt')
local dirty_ok, dirty_err = mr.checkout_mr({ type = 'mr', kind = 'gitlab', iid = 7 }, { cwd = work })
harness.assert_eq(dirty_ok, false, 'dirty checkout refused')
harness.assert_has(dirty_err or '', 'non propre', 'dirty error message')
git({ 'checkout', '--', 'app.txt' }, work)
harness.ok 'dirty working tree'

-- GitHub-style PR ref on a second bare repo
local gh_bare = tmp .. '/gh.git'
local gh_work = tmp .. '/gh-work'
vim.fn.mkdir(gh_bare, 'p')
git({ 'init', '--bare', '-b', 'main' }, gh_bare)
git({ 'clone', gh_bare, gh_work }, tmp)
git({ 'config', 'user.email', 'kickstart@example.com' }, gh_work)
git({ 'config', 'user.name', 'Kickstart Test' }, gh_work)
vim.fn.writefile({ 'main' }, gh_work .. '/x.txt')
git({ 'add', 'x.txt' }, gh_work)
git({ 'commit', '-m', 'init' }, gh_work)
git({ 'branch', '-M', 'main' }, gh_work)
git({ 'push', '-u', 'origin', 'main' }, gh_work)
git({ 'checkout', '-b', 'pr-branch' }, gh_work)
vim.fn.writefile({ 'main', 'pr' }, gh_work .. '/x.txt')
git({ 'add', 'x.txt' }, gh_work)
git({ 'commit', '-m', 'pr' }, gh_work)
local pr_sha = vim.trim(git({ 'rev-parse', 'HEAD' }, gh_work).stdout)
git({ 'push', 'origin', 'HEAD:refs/pull/3/head' }, gh_work)
git({ 'checkout', 'main' }, gh_work)

harness.assert_eq(mr.detect_kind(gh_work), 'github', 'detect github via pull refs')
local ok_pr, pr_branch = mr.checkout_by_iid(3, { cwd = gh_work, kind = 'github' })
harness.assert_truthy(ok_pr, 'checkout PR: ' .. tostring(pr_branch))
harness.assert_eq(pr_branch, 'review/pr-3', 'github review branch')
harness.assert_has(table.concat(vim.fn.readfile(gh_work .. '/x.txt'), '\n'), 'pr', 'PR content')
harness.ok 'checkout_by_iid github'

-- Plugin commands (no vim.pack / Diffview — load helpers API only)
harness.assert_eq(type(mr.checkout_mr), 'function', 'checkout_mr exported')

vim.fn.delete(tmp, 'rf')
harness.ok 'merge_request e2e'
vim.cmd 'qa!'
