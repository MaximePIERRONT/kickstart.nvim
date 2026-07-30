-- Herdr CLI helpers (tab create, fullscreen panes via zoom).

local M = {}

---@return boolean
function M.available()
  return vim.fn.executable 'herdr' == 1
end

---@return boolean
function M.in_pane()
  local pane = vim.env.HERDR_PANE_ID
  return pane ~= nil and pane ~= ''
end

---@param args string[]
---@return table|nil data
---@return string|nil err
local function herdr_json(args)
  local result = vim.system(vim.list_extend({ 'herdr' }, args), { text = true }):wait()
  if result.code ~= 0 then
    local msg = (result.stderr or result.stdout or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if msg == '' then msg = 'herdr exited with code ' .. tostring(result.code) end
    return nil, msg
  end
  local raw = (result.stdout or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if raw == '' then return {}, nil end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= 'table' then return nil, 'invalid herdr JSON response' end
  return data, nil
end

---@param cwd string|nil
---@param label string|nil
---@return string|nil pane_id
---@return string|nil err
local function tab_create(cwd, label)
  local args = { 'tab', 'create', '--focus' }
  if cwd and cwd ~= '' then vim.list_extend(args, { '--cwd', cwd }) end
  if label and label ~= '' then vim.list_extend(args, { '--label', label }) end

  local data, err = herdr_json(args)
  if not data then return nil, err end

  local pane_id = data.result and data.result.root_pane and data.result.root_pane.pane_id
  if not pane_id or pane_id == '' then return nil, 'herdr tab create: missing root pane id' end
  return pane_id, nil
end

---@param pane_id string
---@param cmd string
---@return string|nil err
local function pane_run(pane_id, cmd)
  local _, err = herdr_json({ 'pane', 'run', pane_id, cmd })
  return err
end

---@param pane_id string
---@return string|nil err
local function pane_zoom_on(pane_id)
  local _, err = herdr_json({ 'pane', 'zoom', '--on', '--pane', pane_id })
  return err
end

---@param cwd string|nil
---@param label string|nil
---@return boolean ok
---@return string|nil err
function M.create_tab(cwd, label)
  if not M.available() then return false, 'binaire `herdr` introuvable (PATH)' end
  local _, err = tab_create(cwd or vim.uv.cwd(), label or 'nvim')
  if err then return false, err end
  return true
end

---@param cmd string executable name or path
---@param title string
---@param cwd string|nil
---@return boolean ok
---@return string|nil err
function M.open_fullscreen(cmd, title, cwd)
  if not M.available() then return false, 'herdr unavailable' end

  local pane_id, err = tab_create(cwd, title)
  if not pane_id then return false, err end

  err = pane_run(pane_id, cmd)
  if err then return false, err end

  err = pane_zoom_on(pane_id)
  if err then return false, err end

  return true
end

return M
