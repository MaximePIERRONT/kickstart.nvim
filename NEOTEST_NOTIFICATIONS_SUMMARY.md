# Neotest Notifications - Summary of Changes

## Problem Statement

The user wanted IntelliJ-like test notifications in Neovim using neotest. When running tests with `<leader>jf` or `<leader>jt`, the following issues occurred:

1. **Initial error**: `attempt to index field 'listeners' (a nil value)` - caused by trying to use `neotest.listeners.results` which is not a public API
2. **No notification appearing** after tests complete
3. **"No tests found"** errors in some projects

## Root Causes Identified

### Issue 1: `neotest.listeners` does not exist publicly
The neotest API does not expose `neotest.listeners` directly. The original code tried to use:
```lua
neotest.listeners.results = neotest.listeners.results or {}
neotest.listeners.results['neotest_notifications'] = function(...)
```

This caused a crash at runtime.

**Solution**: Implemented polling-based notifications instead of event listeners.

### Issue 2: Duplicate `neotest.setup()` calls
Two places were calling `neotest.setup()`:
1. `lua/custom/plugins/neotest-notifications.lua` - at plugin load time
2. `ftplugin/java.lua` - in `ensure_neotest_context()` function

Calling `setup()` twice with different configurations caused conflicts and test discovery failures.

**Solution**: Removed duplicate `neotest.setup()` call from `ftplugin/java.lua`.

### Issue 3: Wrong directory for multi-module Maven projects
For multi-module Maven projects like `hexagonal-archi-micronaut`:
- `find_workspace_root()` returns the **parent** directory (with `<modules>` tag)
- But neotest-java needs the **module** directory to discover tests

Example:
- Parent: `/home/maxime/devs/hexagonal-archi-micronaut/` (has `<modules>`)
- Module: `/home/maxime/devs/hexagonal-archi-micronaut/domain/` (has actual tests)

**Solution**: Changed `run_java_test()` to use `nearest_pom_dir()` instead of `root_dir` to get the correct module directory.

### Issue 4: `neotest.state()` timing issue
When using deferred callbacks (via `vim.defer_fn`), calling `neotest.state()` can fail because the consumer's internal `client` reference becomes `nil`.

**Solution**: Wrapped `neotest.state()` call in `pcall` to handle errors gracefully.

## Files Modified

### 1. `lua/custom/neotest-notifications.lua` (new file)
Shared helper module containing:
- `count_results(results)` - counts passed/failed/skipped/total
- `notify_results(stats)` - shows nvim-notify popup with test results
- `make_run_with_notification(neotest)` - creates a polling-based notification wrapper

### 2. `lua/custom/plugins/neotest-notifications.lua`
- Removed broken `neotest.listeners.results` code
- Added polling-based notification system using the helper module
- Refactored to use `notify_module.make_run_with_notification(neotest)`

### 3. `ftplugin/java.lua`
- Added `require('custom.neotest-notifications')` import
- Modified `run_java_test()` function:
  - Uses `nearest_pom_dir()` for correct module directory
  - Wraps `neotest.run.run` with notification polling
  - Removed duplicate `neotest.setup()` call
- Removed `ensure_neotest_context()` call from `run_java_test()` (kept the function but it now only does `lcd`)

## How the Notification System Works

1. When user runs a test (e.g., `<leader>jf`)
2. `run_with_notification(neotest.run.run)` is called
3. This sets `polling_running = true` and starts `poll_results()` via `vim.defer_fn`
4. Every 500ms, `poll_results()` checks `neotest.state().results`
5. If any test is still "running", it reschedules itself
6. When all tests complete, it calls `notify_results()` showing a popup with:
   - "Tests Passed" (green/info) if no failures
   - "Tests Failed" (red/error) if any failures
   - Counts: "X passed | Y failed | Z skipped"

## Key Mappings

### Java-specific (ftplugin/java.lua):
- `<leader>jt` - Run nearest test
- `<leader>jf` - Run all tests in file
- `<leader>jd` - Debug test
- `<leader>js` - Toggle summary
- `<leader>jo` - Open output

### General neotest (neotest-notifications.lua):
- `<leader>tr` - Run nearest test
- `<leader>tf` - Run file tests
- `<leader>tl` - Run last test
- `<leader>td` - Debug test
- `<leader>ts` - Toggle summary
- `<leader>to` - Open output
- `<leader>tp` - Toggle output panel
- `<leader>tx` - Stop tests
- `[t` / `]t` - Jump to previous/next failed test

## Remaining Issues

1. **Neovim version requirement**: The `:NeotestJava setup` command requires Neovim 0.12.0+ for SHA256 checksum verification. Manual JAR download is needed for older versions.

2. **Notifications may not appear**: The polling mechanism uses `neotest.state()` which can occasionally fail with `attempt to index local 'client' (a nil value)`. This is handled with pcall but may need further investigation.

3. **Multi-module projects**: The solution uses `nearest_pom_dir()` to find the correct module directory, which works for Maven multi-module projects.

4. **"No tests found"**: Despite using `nearest_pom_dir()`, neotest-java may still not discover tests in multi-module Maven projects. This could be due to:
   - neotest-java relying on nvim-jdtls for classpath/discovery information
   - The adapter needing explicit project configuration for multi-module setups
   - neotest's internal state not being properly refreshed after directory change

5. **neotest.setup() called too early**: The `neotest.setup()` is called when `neotest-notifications.lua` plugin loads (at Neovim startup), before jdtls has attached and before we know the correct project root. This may cause adapter configuration issues.

## Planned Features

### Enhanced Test Result Notifications
- **Feature**: Show detailed popup with test summary after each test run
- **Details to display**:
  - Number of tests passed, failed, and skipped
  - For failed/crashed tests: show test name, error message, and stack trace
  - Link to open output panel for full details
- **Implementation approach**:
  - Use `neotest.state().results` to get detailed test results
  - Extract error messages and stack traces from result data
  - Format as rich notification using nvim-notify
  - Include clickable actions to jump to failure location

## Date
Created: March 19, 2026
