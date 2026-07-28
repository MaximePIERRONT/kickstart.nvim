-- Auto-install missing CLI / runtime deps into stdpath('data')/kickstart-tools.
-- Used for Node.js, ripgrep, fd, LazyGit, LazyDocker, LazySQL, JDK 21 (jdtls), and Maven —
-- same idea as Mason for LSPs. Designed so Ubuntu/Arch only need a few OS packages.

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

---Prepend a directory to PATH if not already present (idempotent).
---@param dir string
local function prepend_dir(dir)
  if not dir or dir == '' then return end
  if not vim.uv.fs_stat(dir) then return end
  local path = vim.env.PATH or ''
  local needle = dir:gsub('(%W)', '%%%1')
  if not path:find(needle, 1, false) then vim.env.PATH = dir .. ':' .. path end
end

---Prepend managed tool bin dirs to PATH (idempotent).
function M.prepend_path()
  local bin = M.bin_dir()
  vim.fn.mkdir(bin, 'p')
  -- Order: shims first, then full distributions (node/npm need their real bin dir).
  prepend_dir(bin)
  prepend_dir(vim.fs.joinpath(M.tools_root(), 'nodejs', 'bin'))
  prepend_dir(vim.fs.joinpath(M.tools_root(), 'maven', 'bin'))
  prepend_dir(vim.fs.joinpath(M.tools_root(), 'jdk-21', 'bin'))
end

---@return string sys lowercase: linux|darwin|windows
---@return string arch: x86_64|arm64|armv6|i386
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
  elseif machine:find 'armv7' or machine:find 'armv6' then
    arch = machine:find 'armv7' and 'armv7' or 'armv6'
  elseif machine == 'i386' or machine == 'i686' or machine == 'x86' then
    arch = 'i386'
  else
    arch = machine
  end
  return sys, arch
end

---@return boolean
local function is_windows()
  local sys = M.os_arch()
  return sys == 'windows'
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
  -- Support .tar.gz / .tgz / .tar.xz / plain .tar (Node ships linux builds as .tar.xz).
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
---@param name string binary name inside extracted tree
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
  if vim.uv.fs_stat(dest) then
    vim.fn.delete(dest)
  end
  -- Prefer hard copy for portability across OS (symlink needs admin on Windows).
  local result = vim.system({ 'cp', '-f', src, dest }, { text = true }):wait()
  if result.code ~= 0 then
    -- Fallback: read/write
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

---Build GitHub release asset URL for jesseduffield-style archives.
---@param repo string
---@param tag string e.g. v0.63.1
---@param tool string lazygit|lazydocker
---@return string|nil url
---@return string|nil err
function M.jesseduffield_asset_url(repo, tag, tool)
  local sys, arch = M.os_arch()
  local version = tag:gsub('^v', '')
  local asset
  if tool == 'lazygit' then
    local os_part = sys -- linux|darwin|windows (lowercase)
    local arch_part = arch
    if arch == 'i386' then arch_part = '32-bit' end
    if sys == 'windows' then
      asset = string.format('%s_%s_%s_%s.zip', tool, version, os_part, arch_part == 'x86_64' and 'x86_64' or arch_part)
    else
      asset = string.format('%s_%s_%s_%s.tar.gz', tool, version, os_part, arch_part)
    end
  elseif tool == 'lazydocker' then
    -- Assets use Linux/Darwin/Windows capitalization
    local os_part = ({ linux = 'Linux', darwin = 'Darwin', windows = 'Windows' })[sys] or 'Linux'
    local arch_part = arch
    if arch == 'i386' then arch_part = 'x86' end
    if sys == 'windows' then
      asset = string.format('%s_%s_%s_%s.zip', tool, version, os_part, arch_part)
    else
      asset = string.format('%s_%s_%s_%s.tar.gz', tool, version, os_part, arch_part)
    end
  else
    return nil, 'unknown jesseduffield tool: ' .. tool
  end
  return string.format('https://github.com/%s/releases/download/%s/%s', repo, tag, asset), nil
end

---@param tool 'lazygit'|'lazydocker'
---@return boolean ok
---@return string|nil path_or_err
function M.ensure_jesseduffield(tool)
  local existing = M.find_executable(tool)
  if existing then return true, existing end

  if INSTALLING[tool] then
    return false, tool .. ' install already in progress'
  end
  INSTALLING[tool] = true

  local repo = 'jesseduffield/' .. tool
  vim.notify(string.format('Installing %s (auto)…', tool), vim.log.levels.INFO)

  local tag, tag_err = M.latest_release_tag(repo)
  if not tag then
    INSTALLING[tool] = nil
    return false, tag_err
  end

  local url, url_err = M.jesseduffield_asset_url(repo, tag, tool)
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

  local bin_name = tool .. (is_windows() and '.exe' or '')
  local found = find_in_tree(extract_dir, bin_name)
  if not found then
    INSTALLING[tool] = nil
    return false, 'binary not found in archive: ' .. bin_name
  end

  local ok_link, link_err = M.link_to_bin(found, bin_name)
  INSTALLING[tool] = nil
  if not ok_link then return false, link_err end

  local path = M.find_executable(tool)
  if not path then return false, tool .. ' installed but not executable' end
  vim.notify(string.format('%s installed → %s', tool, path), vim.log.levels.INFO)
  return true, path
end

---@return string|nil java_home
function M.existing_jdk_home()
  if vim.env.JDTLS_JAVA_HOME and vim.env.JDTLS_JAVA_HOME ~= '' then
    local java = vim.fs.joinpath(vim.env.JDTLS_JAVA_HOME, 'bin', 'java')
    if vim.uv.fs_stat(java) then return vim.env.JDTLS_JAVA_HOME end
  end
  if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= '' then
    local java = vim.fs.joinpath(vim.env.JAVA_HOME, 'bin', 'java')
    if vim.uv.fs_stat(java) then return vim.env.JAVA_HOME end
  end
  local managed = vim.fs.joinpath(M.tools_root(), 'jdk-21')
  local java = vim.fs.joinpath(managed, 'bin', 'java')
  if vim.uv.fs_stat(java) then return managed end
  return nil
end

---@param java_bin string
---@return number|nil
function M.java_major_version(java_bin)
  if not java_bin or java_bin == '' then return nil end
  local result = vim.system({ java_bin, '-version' }, { text = true }):wait()
  local output = (result.stderr or '') .. (result.stdout or '')
  local major = output:match 'version%s+"(.-)"'
  if not major then return nil end
  if major:match '^1%.' then return tonumber(major:match '^1%.(%d+)') end
  return tonumber(major:match '^(%d+)')
end

---Ensure a JDK 21+ is available; sets JDTLS_JAVA_HOME when installing/managed.
---@return boolean ok
---@return string|nil java_home_or_err
function M.ensure_jdk21()
  local home = M.existing_jdk_home()
  if home then
    local java = vim.fs.joinpath(home, 'bin', 'java')
    local major = M.java_major_version(java)
    if major and major >= 21 then
      vim.env.JDTLS_JAVA_HOME = home
      return true, home
    end
  end

  if INSTALLING.jdk21 then return false, 'JDK 21 install already in progress' end
  INSTALLING.jdk21 = true
  vim.notify('Installing JDK 21 (Temurin) for jdtls…', vim.log.levels.INFO)

  local sys, arch = M.os_arch()
  local os_map = { linux = 'linux', darwin = 'mac', windows = 'windows' }
  local arch_map = { x86_64 = 'x64', arm64 = 'aarch64', armv7 = 'arm', i386 = 'x86' }
  local os_name = os_map[sys] or 'linux'
  local arch_name = arch_map[arch] or 'x64'
  -- Adoptium latest GA JDK 21 binary (follows redirects via curl -L)
  local url = string.format(
    'https://api.adoptium.net/v3/binary/latest/21/ga/%s/%s/jdk/hotspot/normal/eclipse?project=jdk',
    os_name,
    arch_name
  )

  local work = vim.fs.joinpath(M.tools_root(), 'downloads', 'jdk')
  vim.fn.mkdir(work, 'p')
  local archive = vim.fs.joinpath(work, 'jdk21.tar.gz')
  if sys == 'windows' then archive = vim.fs.joinpath(work, 'jdk21.zip') end

  local ok_dl, dl_err = M.download(url, archive)
  if not ok_dl then
    INSTALLING.jdk21 = nil
    return false, dl_err
  end

  local extract_dir = vim.fs.joinpath(work, 'extract')
  vim.fn.delete(extract_dir, 'rf')
  local ok_ex, ex_err = M.extract(archive, extract_dir)
  if not ok_ex then
    INSTALLING.jdk21 = nil
    return false, ex_err
  end

  -- Extracted as jdk-21+… / Contents/Home on mac sometimes
  local java_bins = vim.fs.find('java', { path = extract_dir, type = 'file', limit = 20 })
  local jdk_home
  for _, path in ipairs(java_bins) do
    if path:match('/bin/java$') or path:match('\\bin\\java%.exe$') or path:match('/bin/java%.exe$') then
      jdk_home = vim.fs.dirname(vim.fs.dirname(path))
      -- macOS Adoptium may nest Contents/Home
      if jdk_home:match 'Contents$' then jdk_home = vim.fs.joinpath(jdk_home, 'Home') end
      break
    end
  end
  if not jdk_home then
    INSTALLING.jdk21 = nil
    return false, 'JDK bin/java not found in Temurin archive'
  end

  local dest = vim.fs.joinpath(M.tools_root(), 'jdk-21')
  vim.fn.delete(dest, 'rf')
  vim.fn.mkdir(dest, 'p')
  local result = vim.system({ 'cp', '-a', jdk_home .. '/.', dest }, { text = true }):wait()
  if result.code ~= 0 then
    INSTALLING.jdk21 = nil
    return false, result.stderr or 'failed to install JDK into kickstart-tools'
  end
  -- Link java into bin for convenience
  local java_src = vim.fs.joinpath(dest, 'bin', 'java')
  M.link_to_bin(java_src, 'java')

  vim.env.JDTLS_JAVA_HOME = dest
  if not vim.env.JAVA_HOME or vim.env.JAVA_HOME == '' then vim.env.JAVA_HOME = dest end

  INSTALLING.jdk21 = nil
  vim.notify('JDK 21 installed → ' .. dest, vim.log.levels.INFO)
  return true, dest
end

local MAVEN_VERSION = '3.9.9'

---@return boolean ok
---@return string|nil path_or_err
function M.ensure_maven()
  local existing = M.find_executable 'mvn'
  if existing then return true, existing end

  if INSTALLING.maven then return false, 'Maven install already in progress' end
  INSTALLING.maven = true
  vim.notify('Installing Apache Maven ' .. MAVEN_VERSION .. '…', vim.log.levels.INFO)

  local url = string.format('https://dlcdn.apache.org/maven/maven-3/%s/binaries/apache-maven-%s-bin.tar.gz', MAVEN_VERSION, MAVEN_VERSION)
  local work = vim.fs.joinpath(M.tools_root(), 'downloads', 'maven')
  vim.fn.mkdir(work, 'p')
  local archive = vim.fs.joinpath(work, 'maven.tgz')
  local ok_dl, dl_err = M.download(url, archive)
  if not ok_dl then
    -- Fallback archive CDN
    url = string.format('https://archive.apache.org/dist/maven/maven-3/%s/binaries/apache-maven-%s-bin.tar.gz', MAVEN_VERSION, MAVEN_VERSION)
    ok_dl, dl_err = M.download(url, archive)
    if not ok_dl then
      INSTALLING.maven = nil
      return false, dl_err
    end
  end

  local extract_dir = vim.fs.joinpath(work, 'extract')
  vim.fn.delete(extract_dir, 'rf')
  local ok_ex, ex_err = M.extract(archive, extract_dir)
  if not ok_ex then
    INSTALLING.maven = nil
    return false, ex_err
  end

  local mvn = find_in_tree(extract_dir, 'mvn')
  if not mvn then
    INSTALLING.maven = nil
    return false, 'mvn not found in Maven archive'
  end

  local maven_home = vim.fs.dirname(vim.fs.dirname(mvn))
  local dest = vim.fs.joinpath(M.tools_root(), 'maven')
  vim.fn.delete(dest, 'rf')
  vim.fn.mkdir(dest, 'p')
  local result = vim.system({ 'cp', '-a', maven_home .. '/.', dest }, { text = true }):wait()
  if result.code ~= 0 then
    INSTALLING.maven = nil
    return false, result.stderr or 'failed to install Maven'
  end

  M.link_to_bin(vim.fs.joinpath(dest, 'bin', 'mvn'), 'mvn')
  vim.env.MAVEN_HOME = dest
  INSTALLING.maven = nil
  local path = M.find_executable 'mvn'
  vim.notify('Maven installed → ' .. tostring(path), vim.log.levels.INFO)
  return true, path
end

---Ensure LazyGit binary (PATH or auto-download).
function M.ensure_lazygit()
  return M.ensure_jesseduffield 'lazygit'
end

---Ensure LazyDocker binary (PATH or auto-download).
function M.ensure_lazydocker()
  return M.ensure_jesseduffield 'lazydocker'
end

---Build LazySQL GitHub release asset URL (GoReleaser naming, no version in filename).
---@param tag string e.g. v0.5.5
---@return string|nil url
---@return string|nil err
function M.lazysql_asset_url(tag)
  local sys, arch = M.os_arch()
  local os_part = ({ linux = 'Linux', darwin = 'Darwin', windows = 'Windows' })[sys]
  if not os_part then return nil, 'unsupported OS for lazysql: ' .. sys end
  local arch_part = arch
  if arch == 'armv7' or arch == 'armv6' then return nil, 'unsupported arch for lazysql: ' .. arch end
  local ext = sys == 'windows' and 'zip' or 'tar.gz'
  local asset = string.format('lazysql_%s_%s.%s', os_part, arch_part, ext)
  local version = tag:match '^v' and tag or ('v' .. tag)
  return string.format('https://github.com/jorgerojas26/lazysql/releases/download/%s/%s', version, asset), nil
end

---Build ripgrep GitHub release asset URL (musl preferred on Linux for portability).
---@param tag string e.g. 15.2.0 (no leading v) or v15.2.0
---@return string|nil url
---@return string|nil err
function M.ripgrep_asset_url(tag)
  local sys, arch = M.os_arch()
  local version = tag:gsub('^v', '')
  local asset
  if sys == 'linux' then
    local triple
    if arch == 'x86_64' then
      triple = 'x86_64-unknown-linux-musl'
    elseif arch == 'arm64' then
      triple = 'aarch64-unknown-linux-musl'
    elseif arch == 'armv7' then
      triple = 'armv7-unknown-linux-gnueabihf'
    else
      return nil, 'unsupported arch for ripgrep: ' .. arch
    end
    asset = string.format('ripgrep-%s-%s.tar.gz', version, triple)
  elseif sys == 'darwin' then
    local triple = arch == 'arm64' and 'aarch64-apple-darwin' or 'x86_64-apple-darwin'
    asset = string.format('ripgrep-%s-%s.tar.gz', version, triple)
  elseif sys == 'windows' then
    local triple = arch == 'arm64' and 'aarch64-pc-windows-msvc' or 'x86_64-pc-windows-msvc'
    asset = string.format('ripgrep-%s-%s.zip', version, triple)
  else
    return nil, 'unsupported OS for ripgrep: ' .. sys
  end
  return string.format('https://github.com/BurntSushi/ripgrep/releases/download/%s/%s', version, asset), nil
end

---Build fd GitHub release asset URL.
---@param tag string e.g. v10.4.2
---@return string|nil url
---@return string|nil err
function M.fd_asset_url(tag)
  local sys, arch = M.os_arch()
  local version = tag:match '^v' and tag or ('v' .. tag)
  local asset
  if sys == 'linux' then
    local triple
    if arch == 'x86_64' then
      triple = 'x86_64-unknown-linux-musl'
    elseif arch == 'arm64' then
      triple = 'aarch64-unknown-linux-musl'
    elseif arch == 'armv7' then
      triple = 'arm-unknown-linux-musleabihf'
    else
      return nil, 'unsupported arch for fd: ' .. arch
    end
    asset = string.format('fd-%s-%s.tar.gz', version, triple)
  elseif sys == 'darwin' then
    local triple = arch == 'arm64' and 'aarch64-apple-darwin' or 'x86_64-apple-darwin'
    asset = string.format('fd-%s-%s.tar.gz', version, triple)
  elseif sys == 'windows' then
    local triple = arch == 'arm64' and 'aarch64-pc-windows-msvc' or 'x86_64-pc-windows-msvc'
    asset = string.format('fd-%s-%s.zip', version, triple)
  else
    return nil, 'unsupported OS for fd: ' .. sys
  end
  return string.format('https://github.com/sharkdp/fd/releases/download/%s/%s', version, asset), nil
end

---@param tool string display / INSTALLING key
---@param exe string binary name on PATH
---@param repo string owner/name
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

---Ensure ripgrep (`rg`) for Telescope live grep.
function M.ensure_ripgrep()
  return ensure_github_cli('ripgrep', 'rg', 'BurntSushi/ripgrep', M.ripgrep_asset_url)
end

---Ensure fd (`fd` / `fdfind`) for Telescope / file finders.
function M.ensure_fd()
  -- Debian/Ubuntu package installs as fdfind
  local existing = M.find_executable 'fd'
  if existing then return true, existing end
  local fdfind = M.find_executable 'fdfind'
  if fdfind then
    M.link_to_bin(fdfind, 'fd')
    return true, M.find_executable 'fd' or fdfind
  end
  return ensure_github_cli('fd', 'fd', 'sharkdp/fd', M.fd_asset_url)
end

---Ensure LazySQL binary (PATH or auto-download).
function M.ensure_lazysql()
  return ensure_github_cli('lazysql', 'lazysql', 'jorgerojas26/lazysql', M.lazysql_asset_url)
end

---Resolve Node.js dist archive URL for current OS/arch (LTS).
---@param version string e.g. v24.18.0
---@return string|nil url
---@return string|nil err
function M.nodejs_asset_url(version)
  local sys, arch = M.os_arch()
  local ver = version:match '^v' and version or ('v' .. version)
  local platform, arch_part, ext
  if sys == 'linux' then
    platform = 'linux'
    arch_part = arch == 'arm64' and 'arm64' or (arch == 'x86_64' and 'x64' or nil)
    ext = 'tar.xz'
  elseif sys == 'darwin' then
    platform = 'darwin'
    arch_part = arch == 'arm64' and 'arm64' or (arch == 'x86_64' and 'x64' or nil)
    ext = 'tar.gz'
  elseif sys == 'windows' then
    platform = 'win'
    arch_part = arch == 'arm64' and 'arm64' or (arch == 'x86_64' and 'x64' or nil)
    ext = 'zip'
  else
    return nil, 'unsupported OS for nodejs: ' .. sys
  end
  if not arch_part then return nil, 'unsupported arch for nodejs: ' .. arch end
  local name = string.format('node-%s-%s-%s.%s', ver, platform, arch_part, ext)
  return string.format('https://nodejs.org/dist/%s/%s', ver, name), nil
end

---@return string|nil version e.g. v24.18.0
---@return string|nil err
function M.latest_node_lts_version()
  local tmp = vim.fn.tempname() .. '-node-index.json'
  local ok, err = M.download('https://nodejs.org/dist/index.json', tmp)
  if not ok then return nil, err end
  local lines = vim.fn.readfile(tmp)
  vim.fn.delete(tmp)
  local decoded = vim.json.decode(table.concat(lines, '\n'))
  if type(decoded) ~= 'table' then return nil, 'invalid nodejs index.json' end
  for _, entry in ipairs(decoded) do
    if entry.lts and entry.lts ~= false and entry.version then return entry.version, nil end
  end
  return nil, 'no LTS version found in nodejs index.json'
end

---Ensure Node.js + npm (needed by Mason for JS/TS/Vue tools and npm runners).
---@return boolean ok
---@return string|nil path_or_err
function M.ensure_nodejs()
  local existing = M.find_executable 'node'
  if existing then
    -- Prefer having npm too; if node exists without npm, still accept.
    return true, existing
  end

  if INSTALLING.nodejs then return false, 'Node.js install already in progress' end
  INSTALLING.nodejs = true
  vim.notify('Installing Node.js LTS (auto)…', vim.log.levels.INFO)

  local version, ver_err = M.latest_node_lts_version()
  if not version then
    INSTALLING.nodejs = nil
    return false, ver_err
  end

  local url, url_err = M.nodejs_asset_url(version)
  if not url then
    INSTALLING.nodejs = nil
    return false, url_err
  end

  local work = vim.fs.joinpath(M.tools_root(), 'downloads', 'nodejs')
  vim.fn.mkdir(work, 'p')
  local archive = vim.fs.joinpath(work, url:match '[^/]+$')
  local ok_dl, dl_err = M.download(url, archive)
  if not ok_dl then
    INSTALLING.nodejs = nil
    return false, dl_err
  end

  local extract_dir = vim.fs.joinpath(work, 'extract')
  vim.fn.delete(extract_dir, 'rf')
  local ok_ex, ex_err = M.extract(archive, extract_dir)
  if not ok_ex then
    INSTALLING.nodejs = nil
    return false, ex_err
  end

  local node_bin = find_in_tree(extract_dir, is_windows() and 'node.exe' or 'node')
  if not node_bin then
    INSTALLING.nodejs = nil
    return false, 'node binary not found in Node.js archive'
  end

  local node_home = vim.fs.dirname(vim.fs.dirname(node_bin))
  local dest = vim.fs.joinpath(M.tools_root(), 'nodejs')
  vim.fn.delete(dest, 'rf')
  vim.fn.mkdir(dest, 'p')
  local result = vim.system({ 'cp', '-a', node_home .. '/.', dest }, { text = true }):wait()
  if result.code ~= 0 then
    INSTALLING.nodejs = nil
    return false, result.stderr or 'failed to install Node.js'
  end

  -- Do not copy npm/npx into kickstart-tools/bin — they are scripts/symlinks that
  -- resolve relative to the Node distribution. Prefer PATH → nodejs/bin.
  M.prepend_path()

  INSTALLING.nodejs = nil
  local path = M.find_executable 'node'
  if not path then return false, 'Node.js installed but not executable' end
  vim.notify('Node.js installed → ' .. path, vim.log.levels.INFO)
  return true, path
end

---Sync bootstrap before Mason: PATH + Node (JS tools) + JDK 21 (jdtls).
---Blocking on first launch only when tools are missing.
---@return table results map of tool -> { ok, detail }
function M.ensure_startup_sync()
  M.prepend_path()
  local results = {}
  local ok_node, node_detail = M.ensure_nodejs()
  results.nodejs = { ok = ok_node, detail = node_detail }
  if not ok_node then
    vim.schedule(function() vim.notify('Node.js auto-install: ' .. tostring(node_detail), vim.log.levels.WARN) end)
  end
  local ok_jdk, jdk_detail = M.ensure_jdk21()
  results.jdk21 = { ok = ok_jdk, detail = jdk_detail }
  if not ok_jdk then
    vim.schedule(function() vim.notify('JDK auto-install: ' .. tostring(jdk_detail), vim.log.levels.WARN) end)
  end
  -- Small CLIs used immediately by Telescope / health — sync if missing.
  local ok_rg, rg_detail = M.ensure_ripgrep()
  results.ripgrep = { ok = ok_rg, detail = rg_detail }
  local ok_fd, fd_detail = M.ensure_fd()
  results.fd = { ok = ok_fd, detail = fd_detail }
  return results
end

---Background ensure for tools commonly needed (non-blocking schedule).
function M.ensure_common_async()
  vim.schedule(function()
    pcall(M.ensure_lazygit)
    pcall(M.ensure_lazydocker)
    pcall(M.ensure_lazysql)
    pcall(M.ensure_maven)
    pcall(M.ensure_ripgrep)
    pcall(M.ensure_fd)
    pcall(M.ensure_nodejs)
  end)
end

---Install / refresh all managed tools (sync). Useful via :KickstartEnsureTools.
---@return table results
function M.ensure_all()
  M.prepend_path()
  local results = {
    nodejs = { M.ensure_nodejs() },
    jdk21 = { M.ensure_jdk21() },
    ripgrep = { M.ensure_ripgrep() },
    fd = { M.ensure_fd() },
    maven = { M.ensure_maven() },
    lazygit = { M.ensure_lazygit() },
    lazydocker = { M.ensure_lazydocker() },
    lazysql = { M.ensure_lazysql() },
  }
  return results
end

---System packages that cannot be auto-downloaded (must come from apt/pacman).
---Documented for Ubuntu / Arch install recipes.
---@return string[]
function M.required_system_packages()
  return {
    'git', -- clone plugins / kickstart
    'curl', -- or wget — download tools
    'unzip', -- zip archives (Windows/Linux assets)
    'tar', -- usually base system
    'gzip', -- extract .tar.gz (JDK, ripgrep, …)
    'xz', -- extract Node.js .tar.xz (xz-utils on Debian/Ubuntu)
    'make', -- telescope-fzf-native
    'gcc', -- telescope-fzf-native / treesitter compilers
  }
end

return M
