-- Auto-install CLI tools into stdpath('data')/kickstart-tools.
-- Currently: LazySQL (TUI database browser).

local M = {}

local INSTALLING = {}

---@return string
function M.tools_root()
  return vim.fs.joinpath(vim.fn.stdpath 'data', 'kickstart-tools')
end

---@return string
function M.bin_dir()
  return vim.fs.joinpath(M.tools_root(), 'bin')
end

---@param dir string
local function prepend_dir(dir)
  if not dir or dir == '' then return end
  if not vim.uv.fs_stat(dir) then return end
  local path = vim.env.PATH or ''
  local needle = dir:gsub('(%W)', '%%%1')
  if not path:find(needle, 1, false) then vim.env.PATH = dir .. ':' .. path end
end

function M.prepend_path()
  local bin = M.bin_dir()
  vim.fn.mkdir(bin, 'p')
  prepend_dir(bin)
end

---@return string sys: linux|darwin|windows
---@return string arch: x86_64|arm64|i386|...
function M.os_arch()
  local uname = vim.uv.os_uname()
  local sys = (uname.sysname or ''):lower()
  if sys:find 'darwin' or sys:find 'mac' then
    sys = 'darwin'
  elseif sys:find 'windows' or sys:find 'mingw' then
    sys = 'windows'
  else
    sys = 'linux'
  end

  local machine = (uname.machine or ''):lower()
  local arch
  if machine == 'x86_64' or machine == 'amd64' then
    arch = 'x86_64'
  elseif machine == 'aarch64' or machine == 'arm64' then
    arch = 'arm64'
  elseif machine == 'i386' or machine == 'i686' or machine == 'x86' then
    arch = 'i386'
  else
    arch = machine
  end
  return sys, arch
end

---@return boolean
local function is_windows()
  return M.os_arch() == 'windows'
end

---@param exe string
---@return string|nil
function M.find_executable(exe)
  M.prepend_path()
  if vim.fn.executable(exe) == 1 then return vim.fn.exepath(exe) end
  local local_bin = vim.fs.joinpath(M.bin_dir(), exe)
  if vim.fn.executable(local_bin) == 1 then return local_bin end
  if is_windows() then
    local local_exe = local_bin .. '.exe'
    if vim.fn.executable(local_exe) == 1 then return local_exe end
  end
  return nil
end

---@param url string
---@param dest string
---@return boolean ok
---@return string|nil err
function M.download(url, dest)
  vim.fn.mkdir(vim.fs.dirname(dest), 'p')
  if vim.fn.executable 'curl' == 1 then
    local result = vim.system({ 'curl', '-fsSL', '-o', dest, url }, { text = true }):wait()
    if result.code ~= 0 then return false, result.stderr or ('curl failed: ' .. tostring(result.code)) end
    return true
  end
  if vim.fn.executable 'wget' == 1 then
    local result = vim.system({ 'wget', '-q', '-O', dest, url }, { text = true }):wait()
    if result.code ~= 0 then return false, result.stderr or ('wget failed: ' .. tostring(result.code)) end
    return true
  end
  return false, 'curl or wget required to download tools'
end

---@param archive string
---@param outdir string
---@return boolean ok
---@return string|nil err
function M.extract(archive, outdir)
  vim.fn.mkdir(outdir, 'p')
  if archive:match '%.zip$' then
    if vim.fn.executable 'unzip' ~= 1 then return false, 'unzip required' end
    local result = vim.system({ 'unzip', '-qo', archive, '-d', outdir }, { text = true }):wait()
    if result.code ~= 0 then return false, result.stderr or 'unzip failed' end
    return true
  end
  if vim.fn.executable 'tar' ~= 1 then return false, 'tar required' end
  local flags = '-xf'
  if archive:match '%.tar%.gz$' or archive:match '%.tgz$' then
    flags = '-xzf'
  elseif archive:match '%.tar%.xz$' or archive:match '%.txz$' then
    flags = '-xJf'
  end
  local result = vim.system({ 'tar', flags, archive, '-C', outdir }, { text = true }):wait()
  if result.code ~= 0 then return false, result.stderr or ('tar extract failed (' .. flags .. ')') end
  return true
end

---@param root string
---@param name string
---@return string|nil
local function find_in_tree(root, name)
  local matches = vim.fs.find(name, { path = root, type = 'file', limit = 5 })
  for _, path in ipairs(matches) do
    if vim.fn.executable(path) == 1 or path:match(name .. '$') then return path end
  end
  return matches[1]
end

---@param src string
---@param dest_name string
---@return boolean ok
---@return string|nil err
function M.link_to_bin(src, dest_name)
  local bin = M.bin_dir()
  vim.fn.mkdir(bin, 'p')
  local dest = vim.fs.joinpath(bin, dest_name)
  if vim.uv.fs_stat(dest) then vim.fn.delete(dest) end
  local result = vim.system({ 'cp', '-f', src, dest }, { text = true }):wait()
  if result.code ~= 0 then
    local ok_read, data = pcall(vim.fn.readfile, src, 'b')
    if not ok_read then return false, 'failed to copy ' .. src end
    vim.fn.writefile(data, dest, 'b')
  end
  vim.fn.setfperm(dest, 'rwxr-xr-x')
  M.prepend_path()
  return true
end

---@param repo string owner/name
---@return string|nil tag
---@return string|nil err
function M.latest_release_tag(repo)
  local url = 'https://api.github.com/repos/' .. repo .. '/releases/latest'
  local tmp = vim.fn.tempname() .. '-release.json'
  local ok, err = M.download(url, tmp)
  if not ok then return nil, err end
  local lines = vim.fn.readfile(tmp)
  vim.fn.delete(tmp)
  local decoded = vim.json.decode(table.concat(lines, '\n'))
  if not decoded or not decoded.tag_name then return nil, 'no tag_name in release JSON' end
  return decoded.tag_name, nil
end

---Build LazySQL GitHub release asset URL (jorgerojas26/lazysql).
---@param tag string e.g. v0.5.5
---@return string|nil url
---@return string|nil err
function M.lazysql_asset_url(tag)
  local sys, arch = M.os_arch()
  local os_part = ({ linux = 'Linux', darwin = 'Darwin', windows = 'Windows' })[sys]
  if not os_part then return nil, 'unsupported OS for lazysql: ' .. sys end
  if arch == 'armv7' or arch == 'armv6' then return nil, 'unsupported arch for lazysql: ' .. arch end
  local ext = sys == 'windows' and '.zip' or '.tar.gz'
  local asset = string.format('lazysql_%s_%s%s', os_part, arch, ext)
  return string.format('https://github.com/jorgerojas26/lazysql/releases/download/%s/%s', tag, asset), nil
end

---@param tool string
---@param exe string
---@param repo string
---@param asset_url_fn fun(tag: string): string|nil, string|nil
---@return boolean ok
---@return string|nil path_or_err
local function ensure_github_cli(tool, exe, repo, asset_url_fn)
  local existing = M.find_executable(exe)
  if existing then return true, existing end

  if INSTALLING[tool] then return false, tool .. ' install already in progress' end
  INSTALLING[tool] = true
  vim.notify(string.format('Installing %s (auto)…', tool), vim.log.levels.INFO)

  local tag, tag_err = M.latest_release_tag(repo)
  if not tag then
    INSTALLING[tool] = nil
    return false, tag_err
  end

  local url, url_err = asset_url_fn(tag)
  if not url then
    INSTALLING[tool] = nil
    return false, url_err
  end

  local work = vim.fs.joinpath(M.tools_root(), 'downloads', tool)
  vim.fn.mkdir(work, 'p')
  local archive = vim.fs.joinpath(work, url:match '[^/]+$')
  local ok_dl, dl_err = M.download(url, archive)
  if not ok_dl then
    INSTALLING[tool] = nil
    return false, dl_err
  end

  local extract_dir = vim.fs.joinpath(work, 'extract')
  vim.fn.delete(extract_dir, 'rf')
  local ok_ex, ex_err = M.extract(archive, extract_dir)
  if not ok_ex then
    INSTALLING[tool] = nil
    return false, ex_err
  end

  local bin_name = exe .. (is_windows() and '.exe' or '')
  local found = find_in_tree(extract_dir, bin_name)
  if not found then
    INSTALLING[tool] = nil
    return false, 'binary not found in archive: ' .. bin_name
  end

  local ok_link, link_err = M.link_to_bin(found, bin_name)
  INSTALLING[tool] = nil
  if not ok_link then return false, link_err end

  local path = M.find_executable(exe)
  if not path then return false, tool .. ' installed but not executable' end
  vim.notify(string.format('%s installed → %s', tool, path), vim.log.levels.INFO)
  return true, path
end

---Ensure LazySQL binary (PATH or auto-download).
---@return boolean ok
---@return string|nil path_or_err
function M.ensure_lazysql()
  return ensure_github_cli('lazysql', 'lazysql', 'jorgerojas26/lazysql', M.lazysql_asset_url)
end

return M
