-- GitLab / GitHub merge-request review helpers (IntelliJ-style checkout + diff).
-- Checkout creates a local `review/mr-<iid>` or `review/pr-<n>` branch from the
-- remote MR/PR ref, then the UI opens a three-dot Diffview against the target.

local M = {}

---@class kickstart.MR
---@field type 'mr'|'current'|'local'
---@field kind 'gitlab'|'github'|'local'|'unknown'
---@field iid integer|nil
---@field title string|nil
---@field source string|nil
---@field target string|nil
---@field sha string|nil
---@field url string|nil
---@field branch string|nil local branch name for type='local'

---@param args string[]
---@param opts { cwd: string|nil, env: table|nil }|nil
---@return vim.SystemCompleted
function M.git(args, opts)
  opts = opts or {}
  local result = vim.system(vim.list_extend({ 'git' }, args), {
    cwd = opts.cwd,
    text = true,
    env = opts.env,
  }):wait()
  return result
end

---@param text string|nil
---@return string
local function trim(text)
  return (text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

---@param start string|nil
---@return string|nil
---@return string|nil
function M.git_root(start)
  local result = M.git({ 'rev-parse', '--show-toplevel' }, { cwd = start or vim.uv.cwd() })
  if result.code ~= 0 then return nil, trim(result.stderr) end
  local root = trim(result.stdout)
  if root == '' then return nil, 'not a git repository' end
  return root
end

---Parse origin-style remote URLs (https, ssh, git@, with optional credentials).
---@param url string
---@return { host: string|nil, path: string|nil, kind: 'github'|'gitlab'|'unknown', url: string }
function M.parse_remote_url(url)
  url = trim(url)
  url = url:gsub('%.git$', '')
  url = url:gsub('://[^@/]+@', '://') -- https://user:token@host → https://host

  local host, path
  host, path = url:match '^git@([^:]+):(.+)$'
  if not host then host, path = url:match '^ssh://git@([^/]+)/(.+)$' end
  if not host then host, path = url:match '^ssh://([^/]+)/(.+)$' end
  if not host then host, path = url:match '^https?://([^/]+)/(.+)$' end

  local kind = M.kind_from_host(host)
  return { host = host, path = path, kind = kind, url = url }
end

---@param host string|nil
---@return 'github'|'gitlab'|'unknown'
function M.kind_from_host(host)
  if not host or host == '' then return 'unknown' end
  local h = host:lower()
  if h == 'github.com' or h:match '%.github%.com$' then return 'github' end
  if h:find('gitlab', 1, true) then return 'gitlab' end
  return 'unknown'
end

---@param kind 'gitlab'|'github'|string
---@param iid integer|string
---@return string
function M.review_branch_name(kind, iid)
  if kind == 'github' then return 'review/pr-' .. tostring(iid) end
  return 'review/mr-' .. tostring(iid)
end

---@param kind 'gitlab'|'github'|string
---@param iid integer|string
---@return string
function M.fetch_ref(kind, iid)
  if kind == 'github' then return 'refs/pull/' .. tostring(iid) .. '/head' end
  return 'refs/merge-requests/' .. tostring(iid) .. '/head'
end

---@param kind 'gitlab'|'github'|string
---@param iid integer|string
---@param branch string
---@return string
function M.fetch_spec(kind, iid, branch)
  return string.format('+%s:refs/heads/%s', M.fetch_ref(kind, iid), branch)
end

---@param stdout string|nil
---@param kind 'gitlab'|'github'|string
---@return kickstart.MR[]
function M.parse_ls_remote(stdout, kind)
  local items = {}
  for line in (stdout or ''):gmatch '[^\r\n]+' do
    local sha, ref = line:match '^(%x+)%s+(.+)$'
    if sha and ref then
      local iid = ref:match 'refs/merge%-requests/(%d+)/head$'
      if not iid then iid = ref:match 'refs/pull/(%d+)/head$' end
      if iid then
        table.insert(items, {
          type = 'mr',
          kind = kind,
          iid = tonumber(iid),
          sha = sha,
        })
      end
    end
  end
  table.sort(items, function(a, b) return (a.iid or 0) > (b.iid or 0) end)
  return items
end

---@param raw string|nil
---@return kickstart.MR[]
function M.parse_gh_pr_list(raw)
  if not raw or trim(raw) == '' then return {} end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= 'table' then return {} end
  local items = {}
  for _, row in ipairs(decoded) do
    if type(row) == 'table' then
      table.insert(items, {
        type = 'mr',
        kind = 'github',
        iid = tonumber(row.number or row.iid),
        title = row.title,
        source = row.headRefName or row.head_ref_name,
        target = row.baseRefName or row.base_ref_name,
        url = row.url,
      })
    end
  end
  return items
end

---@param raw string|nil
---@return kickstart.MR[]
function M.parse_glab_mr_list(raw)
  if not raw or trim(raw) == '' then return {} end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= 'table' then return {} end
  -- glab may wrap the array
  if decoded[1] == nil and decoded.items then decoded = decoded.items end
  local items = {}
  for _, row in ipairs(decoded) do
    if type(row) == 'table' then
      table.insert(items, {
        type = 'mr',
        kind = 'gitlab',
        iid = tonumber(row.iid or row.Iid or row.number),
        title = row.title or row.Title,
        source = row.source_branch or row.sourceBranch or row.head_ref_name,
        target = row.target_branch or row.targetBranch or row.base_ref_name,
        url = row.web_url or row.webUrl or row.url,
      })
    end
  end
  return items
end

---Overlay CLI metadata (title, branches) onto git-ref items by iid.
---@param refs kickstart.MR[]
---@param cli kickstart.MR[]
---@return kickstart.MR[]
function M.merge_by_iid(refs, cli)
  local by_iid = {}
  for _, item in ipairs(cli or {}) do
    if item.iid then by_iid[item.iid] = item end
  end
  if #refs == 0 then return cli or {} end
  local merged = {}
  local seen = {}
  for _, item in ipairs(refs) do
    local extra = item.iid and by_iid[item.iid]
    local sha = item.sha
    if extra then
      item = vim.tbl_extend('force', item, extra)
      item.sha = sha or extra.sha
    end
    item.type = 'mr'
    seen[item.iid or 0] = true
    table.insert(merged, item)
  end
  -- CLI-only MRs (fork refs sometimes missing from ls-remote)
  for _, item in ipairs(cli or {}) do
    if item.iid and not seen[item.iid] then table.insert(merged, item) end
  end
  table.sort(merged, function(a, b) return (a.iid or 0) > (b.iid or 0) end)
  return merged
end

---@param item kickstart.MR
---@return string
function M.format_item(item)
  if item.type == 'current' then
    local target = item.target or 'origin/HEAD'
    return '●  Branche courante vs ' .. target
  end
  if item.type == 'local' then
    return string.format('⎇  %s  (branche locale)', item.branch or item.source or '?')
  end
  local bang = item.kind == 'github' and '#' or '!'
  local id = string.format('%s%s', bang, tostring(item.iid or '?'))
  local title = item.title and ('  ' .. item.title) or ''
  local route = ''
  if item.source or item.target then
    route = string.format('  (%s → %s)', item.source or '?', item.target or '?')
  end
  return id .. title .. route
end

---@param stdout string|nil
---@return boolean
function M.is_dirty(stdout)
  return trim(stdout) ~= ''
end

---@param stdout string|nil
---@return string|nil
function M.parse_symbolic_ref(stdout)
  local ref = trim(stdout)
  if ref == '' then return nil end
  local short = ref:match '^refs/remotes/(.+)$'
  return short or ref
end

---@param names string[]
---@return string|nil
function M.guess_default_branch(names)
  local set = {}
  for _, name in ipairs(names) do
    set[name] = true
  end
  for _, candidate in ipairs { 'origin/master', 'origin/main', 'master', 'main' } do
    if set[candidate] then return candidate end
  end
  return names[1]
end

---@param cwd string|nil
---@return string|nil
function M.remote_url(cwd)
  local result = M.git({ 'remote', 'get-url', 'origin' }, { cwd = cwd })
  if result.code ~= 0 then return nil end
  return trim(result.stdout)
end

---@param cwd string|nil
---@return 'gitlab'|'github'|'unknown'
---@return table|nil parsed remote
function M.detect_kind(cwd)
  local url = M.remote_url(cwd)
  local parsed = url and M.parse_remote_url(url) or nil
  if parsed and parsed.kind ~= 'unknown' then return parsed.kind, parsed end

  local gl = M.git({ 'ls-remote', 'origin', 'refs/merge-requests/*/head' }, { cwd = cwd })
  if gl.code == 0 and (gl.stdout or ''):find 'merge%-requests' then return 'gitlab', parsed end

  local gh = M.git({ 'ls-remote', 'origin', 'refs/pull/*/head' }, { cwd = cwd })
  if gh.code == 0 and (gh.stdout or ''):find 'refs/pull' then return 'github', parsed end

  return 'unknown', parsed
end

---@param cwd string|nil
---@param ref string
---@return boolean
function M.ref_exists(cwd, ref)
  local result = M.git({ 'rev-parse', '--verify', '--quiet', ref }, { cwd = cwd })
  return result.code == 0
end

---@param cwd string|nil
---@return string
function M.default_target(cwd)
  local sym = M.git({ 'symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD' }, { cwd = cwd })
  if sym.code == 0 then
    local parsed = M.parse_symbolic_ref(sym.stdout)
    if parsed then return parsed end
  end
  for _, candidate in ipairs { 'origin/master', 'origin/main', 'master', 'main' } do
    if M.ref_exists(cwd, candidate) then return candidate end
  end
  return 'HEAD'
end

---@param item kickstart.MR|nil
---@param cwd string|nil
---@return string
function M.resolve_target(item, cwd)
  if item and item.target and item.target ~= '' then
    local remote = item.target:match '^origin/' and item.target or ('origin/' .. item.target)
    if M.ref_exists(cwd, remote) then return remote end
    if M.ref_exists(cwd, item.target) then return item.target end
  end
  return M.default_target(cwd)
end

---@param target string|nil
---@return string
function M.diff_range(target)
  return (target or 'origin/HEAD') .. '...HEAD'
end

---@param cwd string|nil
---@return string|nil
function M.current_branch(cwd)
  local result = M.git({ 'branch', '--show-current' }, { cwd = cwd })
  if result.code ~= 0 then return nil end
  local name = trim(result.stdout)
  if name == '' then return nil end
  return name
end

---@param cwd string|nil
---@return boolean
---@return string|nil err
function M.working_tree_dirty(cwd)
  local result = M.git({ 'status', '--porcelain' }, { cwd = cwd })
  if result.code ~= 0 then return true, trim(result.stderr) end
  return M.is_dirty(result.stdout)
end

---@param cwd string|nil
---@param kind 'gitlab'|'github'|string
---@return kickstart.MR[]
---@return string|nil err
function M.list_remote_refs(cwd, kind)
  local pattern = kind == 'github' and 'refs/pull/*/head' or 'refs/merge-requests/*/head'
  local result = M.git({ 'ls-remote', 'origin', pattern }, { cwd = cwd })
  if result.code ~= 0 then return {}, trim(result.stderr) end
  return M.parse_ls_remote(result.stdout, kind)
end

---@param cwd string|nil
---@param kind 'gitlab'|'github'|string
---@return kickstart.MR[]
function M.list_from_cli(cwd, kind)
  if kind == 'github' and vim.fn.executable 'gh' == 1 then
    local result = vim.system({
      'gh',
      'pr',
      'list',
      '--json',
      'number,title,headRefName,baseRefName,url',
      '--limit',
      '50',
    }, { cwd = cwd, text = true }):wait()
    if result.code == 0 then return M.parse_gh_pr_list(result.stdout) end
  end
  if kind == 'gitlab' and vim.fn.executable 'glab' == 1 then
    local attempts = {
      { 'glab', 'mr', 'list', '-F', 'json' },
      { 'glab', 'mr', 'list', '--output', 'json' },
    }
    for _, cmd in ipairs(attempts) do
      local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
      if result.code == 0 and trim(result.stdout) ~= '' then
        local parsed = M.parse_glab_mr_list(result.stdout)
        if #parsed > 0 then return parsed end
      end
    end
  end
  return {}
end

---@param cwd string|nil
---@return kickstart.MR[]
function M.list_local_branches(cwd)
  local result = M.git({ 'branch', '--format', '%(refname:short)' }, { cwd = cwd })
  if result.code ~= 0 then return {} end
  local current = M.current_branch(cwd)
  local items = {}
  for line in (result.stdout or ''):gmatch '[^\r\n]+' do
    local name = trim(line)
    if name ~= '' and name ~= current and not name:match '^review/' then
      table.insert(items, {
        type = 'local',
        kind = 'local',
        branch = name,
        source = name,
      })
    end
  end
  table.sort(items, function(a, b) return (a.branch or '') < (b.branch or '') end)
  return items
end

---@param cwd string|nil
---@return kickstart.MR[]
---@return string|nil err
function M.picker_items(cwd)
  cwd = cwd or M.git_root()
  if not cwd then return {}, 'pas un dépôt git' end

  local target = M.default_target(cwd)
  local items = {
    { type = 'current', kind = 'local', target = target },
  }

  local kind = M.detect_kind(cwd)
  if kind == 'gitlab' or kind == 'github' then
    local refs = M.list_remote_refs(cwd, kind)
    local cli = M.list_from_cli(cwd, kind)
    local mrs = M.merge_by_iid(refs, cli)
    for _, mr in ipairs(mrs) do
      if not mr.target then mr.target = target:gsub('^origin/', '') end
      table.insert(items, mr)
    end
  end

  if #items == 1 then
    for _, branch in ipairs(M.list_local_branches(cwd)) do
      branch.target = target:gsub('^origin/', '')
      table.insert(items, branch)
    end
  end

  return items
end

---@param item kickstart.MR
---@param opts { cwd: string|nil }|nil
---@return boolean ok
---@return string branch_or_err
function M.checkout_mr(item, opts)
  opts = opts or {}
  local cwd = opts.cwd or M.git_root()
  if not cwd then return false, 'pas un dépôt git' end
  if not item or not item.iid then return false, 'merge request invalide' end

  local dirty, dirty_err = M.working_tree_dirty(cwd)
  if dirty then
    return false, dirty_err or 'arbre de travail non propre — commit ou stash avant le checkout'
  end

  local kind = item.kind
  if kind ~= 'gitlab' and kind ~= 'github' then return false, 'hôte inconnu (GitLab / GitHub)' end

  local branch = M.review_branch_name(kind, item.iid)
  local spec = M.fetch_spec(kind, item.iid, branch)
  local fetch = M.git({ 'fetch', 'origin', spec }, { cwd = cwd })
  if fetch.code ~= 0 then
    -- Already on the review branch: fetch into it is refused. Update via FETCH_HEAD.
    local fetch_head = M.git({ 'fetch', 'origin', M.fetch_ref(kind, item.iid) }, { cwd = cwd })
    if fetch_head.code ~= 0 then
      return false, trim(fetch.stderr ~= '' and fetch.stderr or fetch_head.stderr)
    end
    local reset = M.git({ 'checkout', '-B', branch, 'FETCH_HEAD' }, { cwd = cwd })
    if reset.code ~= 0 then return false, trim(reset.stderr) end
    return true, branch
  end

  local co = M.git({ 'checkout', branch }, { cwd = cwd })
  if co.code ~= 0 then return false, trim(co.stderr) end
  return true, branch
end

---@param iid integer|string
---@param opts { cwd: string|nil, kind: string|nil }|nil
---@return boolean
---@return string
function M.checkout_by_iid(iid, opts)
  opts = opts or {}
  local cwd = opts.cwd or M.git_root()
  local kind = opts.kind or M.detect_kind(cwd)
  iid = tonumber(iid)
  if not iid then return false, 'numéro de MR invalide' end

  if kind == 'gitlab' or kind == 'github' then return M.checkout_mr({ type = 'mr', kind = kind, iid = iid }, { cwd = cwd }) end

  local ok, result = M.checkout_mr({ type = 'mr', kind = 'gitlab', iid = iid }, { cwd = cwd })
  if ok then return ok, result end
  return M.checkout_mr({ type = 'mr', kind = 'github', iid = iid }, { cwd = cwd })
end

---@param branch string
---@param opts { cwd: string|nil }|nil
---@return boolean
---@return string
function M.checkout_local(branch, opts)
  opts = opts or {}
  local cwd = opts.cwd or M.git_root()
  if not cwd then return false, 'pas un dépôt git' end
  local dirty, dirty_err = M.working_tree_dirty(cwd)
  if dirty then return false, dirty_err or 'arbre de travail non propre — commit ou stash avant le checkout' end
  local co = M.git({ 'checkout', branch }, { cwd = cwd })
  if co.code ~= 0 then return false, trim(co.stderr) end
  return true, branch
end

return M
