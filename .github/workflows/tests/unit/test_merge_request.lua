-- Unit tests: custom.merge_request helpers (no network, no Diffview).
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.merge_request'] = nil
local mr = require 'custom.merge_request'

-- Remote URL parsing
local gh_https = mr.parse_remote_url 'https://github.com/MaximePIERRONT/kickstart.nvim.git'
harness.assert_eq(gh_https.kind, 'github', 'github https kind')
harness.assert_eq(gh_https.host, 'github.com', 'github host')
harness.assert_eq(gh_https.path, 'MaximePIERRONT/kickstart.nvim', 'github path')

local gh_ssh = mr.parse_remote_url 'git@github.com:nvim-lua/kickstart.nvim.git'
harness.assert_eq(gh_ssh.kind, 'github', 'github ssh kind')
harness.assert_eq(gh_ssh.path, 'nvim-lua/kickstart.nvim', 'github ssh path')

local gh_token = mr.parse_remote_url 'https://x-access-token:secret@github.com/acme/app.git'
harness.assert_eq(gh_token.kind, 'github', 'github token kind')
harness.assert_eq(gh_token.host, 'github.com', 'github token host')

local gl_https = mr.parse_remote_url 'https://gitlab.com/group/sub/repo.git'
harness.assert_eq(gl_https.kind, 'gitlab', 'gitlab https kind')
harness.assert_eq(gl_https.path, 'group/sub/repo', 'gitlab nested path')

local gl_self = mr.parse_remote_url 'git@gitlab.company.com:team/svc.git'
harness.assert_eq(gl_self.kind, 'gitlab', 'self-hosted gitlab')
harness.assert_eq(gl_self.host, 'gitlab.company.com', 'self-hosted host')

harness.assert_eq(mr.kind_from_host 'github.com', 'github', 'kind github.com')
harness.assert_eq(mr.kind_from_host 'gitlab.example.org', 'gitlab', 'kind gitlab.*')
harness.assert_eq(mr.kind_from_host 'git.internal', 'unknown', 'kind unknown')
harness.ok 'parse_remote_url'

-- Review branch / fetch refs
harness.assert_eq(mr.review_branch_name('gitlab', 42), 'review/mr-42', 'gitlab review branch')
harness.assert_eq(mr.review_branch_name('github', 7), 'review/pr-7', 'github review branch')
harness.assert_eq(mr.fetch_ref('gitlab', 42), 'refs/merge-requests/42/head', 'gitlab fetch ref')
harness.assert_eq(mr.fetch_ref('github', 7), 'refs/pull/7/head', 'github fetch ref')
harness.assert_eq(mr.fetch_spec('gitlab', 42, 'review/mr-42'), '+refs/merge-requests/42/head:refs/heads/review/mr-42', 'gitlab fetch spec')
harness.ok 'review refs'

-- ls-remote parser
local ls = [[
abc123def456	refs/merge-requests/12/head
deadbeef0000	refs/merge-requests/3/head
111aaa222bbb	refs/merge-requests/12/merge
]]
local refs = mr.parse_ls_remote(ls, 'gitlab')
harness.assert_eq(#refs, 2, 'ignore /merge ref')
harness.assert_eq(refs[1].iid, 12, 'sorted newest iid first')
harness.assert_eq(refs[1].sha, 'abc123def456', 'sha 12')
harness.assert_eq(refs[2].iid, 3, 'second iid')

local pulls = mr.parse_ls_remote('cafebabe\trefs/pull/99/head\n', 'github')
harness.assert_eq(#pulls, 1, 'one github pr')
harness.assert_eq(pulls[1].iid, 99, 'pr number')
harness.assert_eq(pulls[1].kind, 'github', 'pr kind')
harness.ok 'parse_ls_remote'

-- gh / glab JSON
local gh_json = [[{
  "number": 8,
  "title": "feat: foo",
  "headRefName": "feat/foo",
  "baseRefName": "master",
  "url": "https://github.com/acme/app/pull/8"
}]]
-- gh pr list returns an array
local gh_items = mr.parse_gh_pr_list('[' .. gh_json .. ']')
harness.assert_eq(#gh_items, 1, 'one gh pr')
harness.assert_eq(gh_items[1].iid, 8, 'gh number')
harness.assert_eq(gh_items[1].source, 'feat/foo', 'gh source')
harness.assert_eq(gh_items[1].target, 'master', 'gh target')
harness.assert_eq(gh_items[1].kind, 'github', 'gh kind')

local glab_items = mr.parse_glab_mr_list [[
[{"iid":4,"title":"fix bar","source_branch":"fix/bar","target_branch":"main","web_url":"https://gitlab.com/a/b/-/merge_requests/4"}]
]]
harness.assert_eq(#glab_items, 1, 'one glab mr')
harness.assert_eq(glab_items[1].iid, 4, 'glab iid')
harness.assert_eq(glab_items[1].source, 'fix/bar', 'glab source')
harness.assert_eq(glab_items[1].kind, 'gitlab', 'glab kind')
harness.ok 'cli json parsers'

-- merge_by_iid keeps sha from refs, titles from CLI
local merged = mr.merge_by_iid({
  { type = 'mr', kind = 'gitlab', iid = 12, sha = 'abc' },
}, {
  { type = 'mr', kind = 'gitlab', iid = 12, title = 'feat: foo', source = 'feat/foo', target = 'master' },
  { type = 'mr', kind = 'gitlab', iid = 99, title = 'cli only' },
})
harness.assert_eq(#merged, 2, 'merged count')
harness.assert_eq(merged[1].iid, 99, 'cli-only first (higher iid)')
harness.assert_eq(merged[2].iid, 12, 'ref iid')
harness.assert_eq(merged[2].sha, 'abc', 'sha preserved')
harness.assert_eq(merged[2].title, 'feat: foo', 'title from cli')
harness.assert_eq(mr.merge_by_iid({}, gh_items)[1].iid, 8, 'cli-only when no refs')
harness.ok 'merge_by_iid'

-- format_item
harness.assert_has(mr.format_item { type = 'current', target = 'origin/master' }, 'Branche courante vs origin/master', 'current label')
harness.assert_has(mr.format_item { type = 'local', branch = 'feat/x' }, 'feat/x', 'local label')
local gl_label = mr.format_item {
  type = 'mr',
  kind = 'gitlab',
  iid = 12,
  title = 'feat: foo',
  source = 'feat/foo',
  target = 'master',
}
harness.assert_has(gl_label, '!12', 'gitlab bang')
harness.assert_has(gl_label, 'feat: foo', 'gitlab title')
harness.assert_has(gl_label, 'feat/foo → master', 'gitlab route')
harness.assert_has(mr.format_item { type = 'mr', kind = 'github', iid = 8 }, '#8', 'github hash')
harness.ok 'format_item'

-- dirty / symbolic-ref / default branch
harness.assert_eq(mr.is_dirty '', false, 'clean empty')
harness.assert_eq(mr.is_dirty(nil), false, 'clean nil')
harness.assert_eq(mr.is_dirty ' M file.txt\n', true, 'dirty')
harness.assert_eq(mr.parse_symbolic_ref 'refs/remotes/origin/master\n', 'origin/master', 'symbolic-ref')
harness.assert_eq(mr.guess_default_branch { 'origin/foo', 'origin/main' }, 'origin/main', 'prefer origin/main')
harness.assert_eq(mr.guess_default_branch { 'origin/master', 'origin/main' }, 'origin/master', 'prefer origin/master')
harness.assert_eq(mr.diff_range 'origin/master', 'origin/master...HEAD', 'three-dot range')
harness.ok 'diff helpers'

-- git_root of this repo
local root = mr.git_root(repo)
harness.assert_eq(vim.fs.normalize(root or ''), vim.fs.normalize(repo), 'git_root repo')
harness.ok 'git_root'

harness.ok 'merge_request unit suite'
vim.cmd 'qa!'
