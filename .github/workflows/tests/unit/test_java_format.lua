-- Unit tests: custom.java_format (Eclipse default / Google detect / preference)
local harness = dofile(vim.fn.getcwd() .. '/.github/workflows/tests/harness.lua')
local repo = harness.repo_root()
vim.opt.runtimepath:prepend(repo)

package.loaded['custom.java_format'] = nil
local jf = require 'custom.java_format'

-- Bundled Eclipse profile exists
local profile = jf.eclipse_profile_path()
harness.assert_truthy(vim.uv.fs_stat(profile), 'eclipse profile file')
harness.assert_has(profile, 'eclipse-java.xml', 'eclipse profile name')
harness.ok 'eclipse profile path'

-- Checkstyle configs
local eclipse_cs = jf.checkstyle_config_path 'eclipse'
local google_cs = jf.checkstyle_config_path 'google'
harness.assert_truthy(vim.uv.fs_stat(eclipse_cs), 'eclipse checkstyle')
harness.assert_truthy(vim.uv.fs_stat(google_cs), 'google checkstyle')
harness.assert_eq(jf.indent_width 'eclipse', 4, 'eclipse indent')
harness.assert_eq(jf.indent_width 'google', 2, 'google indent')
harness.ok 'checkstyle + indent widths'

-- Temp project without Google markers → eclipse
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({
  '<?xml version="1.0"?><project><modelVersion>4.0.0</modelVersion>',
  '<groupId>t</groupId><artifactId>t</artifactId><version>1</version></project>',
}, tmp .. '/pom.xml')

harness.assert_eq(jf.get_preference(tmp), 'auto', 'default preference auto')
local detected, reason = jf.detect_google(tmp)
harness.assert_eq(detected, false, 'no google without markers')
harness.assert_eq(reason, nil, 'no detect reason')

-- Simulate resolve by temporarily editing a buffer under tmp
local java_file = tmp .. '/Src.java'
vim.fn.writefile({ 'class Src {}' }, java_file)
pcall(vim.cmd, 'edit! ' .. vim.fn.fnameescape(java_file))
-- project_root should find tmp via pom.xml
local root = jf.project_root(0)
harness.assert_eq(root, tmp, 'project root from java buffer')

local effective, preference = jf.resolve(0)
harness.assert_eq(preference, 'auto', 'resolve preference auto')
harness.assert_eq(effective, 'eclipse', 'resolve effective eclipse')
harness.assert_eq(#jf.conform_formatters(0), 0, 'conform empty → jdtls/eclipse')
harness.ok 'default resolves to eclipse'

-- Persist google preference
local ok_set = jf.set_preference('google', tmp)
harness.assert_truthy(ok_set, 'set preference google')
harness.assert_eq(jf.get_preference(tmp), 'google', 'read preference google')
effective = select(1, jf.resolve(0))
harness.assert_eq(effective, 'google', 'forced google')
harness.assert_eq(jf.conform_formatters(0)[1], 'google-java-format', 'conform google')
harness.ok 'preference google'

-- Auto + Google detection via marker file
jf.set_preference('auto', tmp)
vim.fn.writefile({ '' }, tmp .. '/.google-java-format')
detected, reason = jf.detect_google(tmp)
harness.assert_eq(detected, true, 'detect marker file')
harness.assert_has(tostring(reason), '.google-java-format', 'marker reason')
effective = select(1, jf.resolve(0))
harness.assert_eq(effective, 'google', 'auto → google when marker')
harness.ok 'auto detects google marker'

-- Detection via pom google-java-format
local tmp2 = vim.fn.tempname()
vim.fn.mkdir(tmp2, 'p')
vim.fn.writefile({
  '<?xml version="1.0"?><project><modelVersion>4.0.0</modelVersion>',
  '<groupId>t</groupId><artifactId>t</artifactId><version>1</version>',
  '<build><plugins><plugin><artifactId>google-java-format-maven-plugin</artifactId></plugin></plugins></build>',
  '</project>',
}, tmp2 .. '/pom.xml')
detected, reason = jf.detect_google(tmp2)
harness.assert_eq(detected, true, 'detect pom google-java-format')
harness.assert_has(tostring(reason), 'pom.xml', 'pom reason')
harness.ok 'detect from pom'

-- jdtls settings fragment
local settings = jf.jdtls_format_settings()
harness.assert_eq(settings.enabled, true, 'jdtls format enabled')
harness.assert_eq(settings.settings.profile, 'Default', 'jdtls profile name')
harness.assert_has(settings.settings.url, 'eclipse-java.xml', 'jdtls url')
harness.ok 'jdtls format settings'

harness.ok 'java_format unit'
vim.cmd 'qa!'
