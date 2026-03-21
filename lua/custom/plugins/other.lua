return {
  {
    'rgroli/other.nvim',
    ft = { 'java' },
    keys = {
      {
        '<leader>tt',
        '<cmd>Other<CR>',
        mode = 'n',
        desc = '[T]oggle Java [T]est/Source',
      },
    },
    config = function()
      local function normalize_path(path)
        return path:gsub('\\', '/')
      end

      local function split_java_path(filename)
        local normalized = normalize_path(filename)
        local rel = normalized:match('/src/.-/java/(.*)%.java$')
        if not rel then
          return nil, nil
        end

        local package_path, class_name = rel:match('^(.*)/([^/]+)$')
        if not class_name then
          package_path = ''
          class_name = rel
        end

        return package_path, class_name
      end

      local function package_decl(package_path)
        if not package_path or package_path == '' then
          return nil
        end
        return 'package ' .. package_path:gsub('/', '.') .. ';'
      end

      local function build_test_skeleton(filename)
        local package_path, class_name = split_java_path(filename)
        if not class_name then
          return nil
        end

        local lines = {}
        local pkg = package_decl(package_path)
        if pkg then
          table.insert(lines, pkg)
          table.insert(lines, '')
        end

        table.insert(lines, 'import org.junit.jupiter.api.Test;')
        table.insert(lines, '')
        table.insert(lines, 'class ' .. class_name .. ' {')
        table.insert(lines, '')
        table.insert(lines, '  @Test')
        table.insert(lines, '  void shouldDoSomething() {')
        table.insert(lines, '  }')
        table.insert(lines, '}')

        return lines
      end

      local function build_source_skeleton(filename)
        local package_path, class_name = split_java_path(filename)
        if not class_name then
          return nil
        end

        local lines = {}
        local pkg = package_decl(package_path)
        if pkg then
          table.insert(lines, pkg)
          table.insert(lines, '')
        end

        table.insert(lines, 'public class ' .. class_name .. ' {')
        table.insert(lines, '}')

        return lines
      end

      require('other-nvim').setup {
        showMissingFiles = true,
        mappings = {
          {
            pattern = '/src/main/java/(.*)%.java$',
            target = '/src/test/java/%1Test.java',
            context = 'test',
          },
          {
            pattern = '/src/test/java/(.*)Test%.java$',
            target = '/src/main/java/%1.java',
            context = 'source',
          },
        },
        hooks = {
          onOpenFile = function(filename, exists)
            if exists then
              return true
            end

            local normalized = normalize_path(filename)
            local is_test_file = normalized:match('/src/test/java/.*Test%.java$') ~= nil
            local lines = is_test_file and build_test_skeleton(filename) or build_source_skeleton(filename)

            if lines and #lines > 0 then
              vim.fn.mkdir(vim.fn.fnamemodify(filename, ':h'), 'p')
              vim.fn.writefile(lines, filename)
            end

            return true
          end,
        },
      }
    end,
  },
}
