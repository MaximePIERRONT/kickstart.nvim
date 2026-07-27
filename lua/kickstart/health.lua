--[[
--
-- This file is not required for your own configuration,
-- but helps people determine if their system is setup correctly.
--
--]]

local check_version = function()
  local verstr = tostring(vim.version())
  if not vim.version.ge then
    vim.health.error(string.format("Neovim out of date: '%s'. Upgrade to latest stable or nightly", verstr))
    return
  end

  if vim.version.ge(vim.version(), '0.12') then
    vim.health.ok(string.format("Neovim version is: '%s'", verstr))
  else
    vim.health.error(string.format("Neovim out of date: '%s'. Upgrade to latest stable or nightly", verstr))
  end
end

local check_external_reqs = function()
  -- Must come from the OS package manager (apt / pacman) — not auto-downloaded.
  for _, exe in ipairs { 'git', 'curl', 'unzip', 'tar', 'gzip', 'xz', 'make', 'gcc' } do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(string.format("Found system executable: '%s'", exe))
    else
      local critical = { git = true, curl = true, unzip = true, tar = true, gzip = true, xz = true }
      local level = critical[exe] and 'error' or 'warn'
      vim.health[level](string.format("Missing system executable: '%s' (install via apt/pacman)", exe))
    end
  end

  -- Auto-installed into stdpath('data')/kickstart-tools when missing.
  local ok_ensure, ensure = pcall(require, 'custom.ensure_tool')
  if ok_ensure then
    ensure.prepend_path()
    vim.health.info('Managed tools root: ' .. ensure.tools_root())
  end

  for _, exe in ipairs { 'rg', 'fd', 'node', 'npm', 'java', 'mvn', 'lazygit', 'lazydocker' } do
    if vim.fn.executable(exe) == 1 then
      vim.health.ok(string.format("Found tool: '%s' → %s", exe, vim.fn.exepath(exe)))
    else
      vim.health.warn(string.format("Tool not on PATH yet: '%s' (auto-install on startup / :KickstartEnsureTools)", exe))
    end
  end

  return true
end

return {
  check = function()
    vim.health.start 'kickstart.nvim'

    vim.health.info [[NOTE: Not every warning is a 'must-fix' in `:checkhealth`

  On Ubuntu / Arch: install only git, curl, unzip, tar, gcc, make (+ Neovim).
  Node, JDK 21, Maven, ripgrep, fd, LazyGit, LazyDocker auto-install into
  stdpath data. LSP / formatters / DAP install via Mason on startup.

  Fix only warnings for plugins and languages you intend to use.
    Mason will give warnings for languages that are not installed.
    You do not need to install, unless you want to use those languages!]]

    local uv = vim.uv or vim.loop
    vim.health.info('System Information: ' .. vim.inspect(uv.os_uname()))

    check_version()
    check_external_reqs()
  end,
}
