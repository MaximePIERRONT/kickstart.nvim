local M = {}

function M.count_results(results)
  local passed, failed, skipped, total = 0, 0, 0, 0
  for _, result in pairs(results) do
    total = total + 1
    if result.status == 'passed' then
      passed = passed + 1
    elseif result.status == 'failed' then
      failed = failed + 1
    elseif result.status == 'skipped' then
      skipped = skipped + 1
    end
  end
  return { passed = passed, failed = failed, skipped = skipped, total = total }
end

function M.notify_results(stats)
  if stats.total == 0 then
    return
  end

  local icon, level, title
  if stats.failed > 0 then
    icon = ''
    level = vim.log.levels.ERROR
    title = 'Tests Failed'
  else
    icon = ''
    level = vim.log.levels.INFO
    title = 'Tests Passed'
  end

  local parts = {}
  if stats.passed > 0 then
    table.insert(parts, stats.passed .. ' passed')
  end
  if stats.failed > 0 then
    table.insert(parts, stats.failed .. ' failed')
  end
  if stats.skipped > 0 then
    table.insert(parts, stats.skipped .. ' skipped')
  end

  local msg = icon .. table.concat(parts, '  |  ')
  vim.notify(msg, level, { title = title })
end

function M.make_run_with_notification(neotest)
  local polling_running = false

  local function poll_results()
    if not polling_running then
      return
    end
    local ok, state_result = pcall(function()
      return neotest.state()
    end)
    if not ok or not state_result then
      vim.defer_fn(poll_results, 500)
      return
    end
    local results = state_result.results or {}
    local stats = M.count_results(results)
    if stats.total == 0 then
      vim.defer_fn(poll_results, 500)
      return
    end
    local running = false
    for _, r in pairs(results) do
      if r.status == 'running' then
        running = true
        break
      end
    end
    if running then
      vim.defer_fn(poll_results, 500)
    else
      polling_running = false
      M.notify_results(stats)
    end
  end

  return function(fn)
    return function(...)
      polling_running = true
      local result = fn(...)
      vim.defer_fn(poll_results, 500)
      return result
    end
  end
end

return M
