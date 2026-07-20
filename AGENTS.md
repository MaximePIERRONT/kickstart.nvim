# AGENTS.md

## Cursor Cloud specific instructions

This repo is **kickstart.nvim** — a single-file Neovim configuration (Lua). "Running the app" means launching Neovim with this repo as its config; there is no server/DB/web service. Plugins are managed at runtime by `lazy.nvim` (bootstrapped in `init.lua`); LSP servers/formatters are managed by `mason.nvim`.

### How the config is wired up
- The repo is symlinked to `~/.config/nvim` (`ln -sfn /workspace ~/.config/nvim`), so plain `nvim` loads this config. This symlink lives in the home dir and is captured by the VM snapshot; a fresh `git pull` into `/workspace` is picked up automatically. If `nvim` ever loads an empty config, re-create that symlink.
- Plugin state lives in `~/.local/share/nvim` / `~/.local/state/nvim` (also snapshot-captured), not in the repo. `lazy-lock.json` is gitignored, so plugins are not version-pinned.

### Run / lint / test
- Run (interactive): `nvim`. Plugin manager UI: `:Lazy`. LSP/tool manager: `:Mason`. Health: `:checkhealth`.
- Install/refresh plugins headlessly: `nvim --headless "+Lazy! install" +qa` (this is the update script).
- Install LSP tools headlessly: `nvim --headless "+MasonToolsInstallSync" +qa`. Mason also auto-installs configured tools on normal startup.
- Lint (this is the repo's CI check): `stylua --check .`. NOTE: the upstream CI only runs on `nvim-lua/kickstart.nvim`. Currently `lua/custom/plugins/docker.lua` and `ftplugin/java.lua` (fork-local files) do NOT pass `stylua --check`; all upstream kickstart files do. Fix with `stylua .` if desired.
- There is no automated test suite.

### Non-obvious gotchas
- In `--headless` mode Neovim exits before Mason finishes async installs, printing `Neovim is exiting while packages are still installing`. Use `+MasonToolsInstallSync` (blocks) instead of relying on startup auto-install when scripting.
- `delve` (Go debug adapter) fails to install because Go is not present — optional, only needed for Go debugging. Similarly `luarocks` and `tree-sitter-cli` show up as optional `:checkhealth` errors and are not required.
- Java tooling (`jdtls`, etc. via `ftplugin/java.lua`) needs a JDK to actually run; the Mason packages install regardless.
