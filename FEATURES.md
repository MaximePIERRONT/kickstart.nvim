# Roadmap des features — kickstart.nvim

Branche de travail : `cursor/from-upstream-master-c628` (base upstream `nvim-lua/kickstart.nvim`).

Objectif : reconstruire une config Neovim personnelle, propre, en repartant d’upstream, avec une roadmap claire et priorisée.

Légende du statut :

- `[x]` déjà disponible / acceptable sur la base actuelle
- `[~]` partiellement présent (kickstart de base ou exemple commenté) — à activer / enrichir
- `[ ]` à faire
- `[-]` hors scope

---

## Décisions actées

| Sujet | Choix |
| --- | --- |
| Explorateur | **neo-tree** — arborescence type IntelliJ (Project tool window) |
| Build Java | **Maven uniquement** (pas de Gradle) |
| Tests Java | **Config minimale auto-installée** — Mason + keymaps `mvn test` (pas de runner custom fragile, pas de neotest) |
| IA / assistants | **Hors scope** |

---

## P0 — Indispensable (socle IDE)

| Feature | Statut | Notes |
| --- | --- | --- |
| LSP | [x] | Mason + LSP : `jdtls` (JDK 21 via `JDTLS_JAVA_HOME`), `vtsls` + `vue_ls`, HTML/CSS/JSON/YAML/Bash/XML |
| Autocompletion | [x] | `blink.cmp` + LuaSnip déjà en place |
| Formatage | [x] | `conform.nvim` : prettier (web), stylua, shfmt, **google-java-format** (style Google, pas AOSP) + format on save |
| Linter | [x] | `nvim-lint` : eslint_d, shellcheck, markdownlint, checkstyle |

**Critère de done P0 :** ouvrir un fichier `.java`, `.vue`, `.ts` et avoir LSP + completion + format + lint utilisables.

---

## P1 — Important (workflow quotidien)

| Feature | Statut | Notes |
| --- | --- | --- |
| Navigation projet | [x] | Telescope + **neo-tree** (`\` / `<leader>e`, suivi du fichier courant) |
| Recherche fuzzy finder | [x] | Telescope (fichiers, grep, LSP) déjà là |
| Git | [x] | `gitsigns` + keymaps hunks (`<leader>h…`, `]c`/`[c`) ; LazyGit en P2 |
| Lancer facilement un projet frontend avec npm | [x] | `<leader>rd/rb/rt/rs` + `:Npm` — terminal split, racine via `package.json` |
| Lancer facilement un projet backend Java | [x] | `<leader>rc/rp/rj/rg` + `:Maven` — compile / package / spring-boot:run / goals libres |
| Lancer facilement un projet backend Micronaut | [x] | `<leader>rm` picker configs / `rM` créer-éditer ; sauvé dans `.nvim/runners.json` (environments + config files + env) |

**Critère de done P1 :** démarrer frontend npm **et** backend Java/Micronaut (Maven) sans quitter Neovim.

---

## P2 — Confort

| Feature | Statut | Notes |
| --- | --- | --- |
| Debug | [x] | `kickstart.plugins.debug` : DAP UI + **js-debug-adapter** + **java-debug-adapter** (bundles jdtls) ; F5/F1–F3/F7, `<leader>b`/`B` ; smoke CI `test-dap-smoke.lua` |
| Tests | [x] | Keymaps Maven multi-module : `<leader>jt` / `jm` / `ja` + `:MavenTest` → `mvn -pl :<module> -am` (pas de neotest) ; CI dans `.github/workflows/java-dap-ci.yml` |
| Snippets | [~] | LuaSnip OK ; `friendly-snippets` encore commenté |
| LazyGit dans l’interface Neovim | [x] | `<leader>gg` / `:LazyGit` — terminal flottant ; **auto-install** binaire via `custom.ensure_tool` (GitHub releases) |
| LazyDocker dans l’interface Neovim | [x] | `<leader>ld` / `:LazyDocker` — idem auto-install |

**Critère de done P2 :** debugger + tests Maven + LazyGit / LazyDocker ✅ (snippets optionnels).

---

## Auto-install des dépendances

Quand un outil manque, la config le télécharge dans `stdpath('data')/kickstart-tools` (préfixe `$PATH`) :

| Outil | Déclencheur | Source |
| --- | --- | --- |
| **JDK 21+** (jdtls) | démarrage LSP si `JDTLS_JAVA_HOME` / `JAVA_HOME` absents ou < 21 | Eclipse Temurin (Adoptium) |
| **Maven** (`mvn`) | premier `:Maven` / test Java / runner | Apache Maven binary |
| **lazygit** | `<leader>gg` / `:LazyGit` (+ warm VimEnter) | GitHub releases |
| **lazydocker** | `<leader>ld` / `:LazyDocker` (+ warm VimEnter) | GitHub releases |
| LSP / formatters / DAP | Mason (`mason-tool-installer`) | Mason registry |

Module : `lua/custom/ensure_tool.lua`.

---

## P3 — Plus tard

| Feature | Statut | Notes |
| --- | --- | --- |
| UI / theme | [~] | Tokyo Night déjà présent ; polish optionnel |
| Sessions | [ ] | Restaurer onglets / buffers entre sessions |
| IA / assistants code | [-] | Hors scope |

---

## Couverture de tests

Suite CI : `.github/workflows/features-ci.yml`

| Couche | Ce qui est vérifié |
| --- | --- |
| **Unit (Lua)** | Helpers `maven-tests` (FQCN, reactor `-pl/-am`) + `runners` (env/dotenv, Micronaut cmd, `runners.json`, scripts npm, `pom_has`) + `ensure_tool` (os/arch, asset URLs, PATH) |
| **Unit/intégration (Java)** | `test-project` multi-module — domain / api / infrastructure (Micronaut) via `mvn verify` |
| **Integration (Neovim)** | Boot config, plugins (dap, neo-tree, telescope, conform, lint, blink, …), keymaps/commandes (LazyGit/LazyDocker), Mason P0/P2, jdtls attach, format java/ts, neo-tree + gitsigns |
| **E2E (Neovim)** | npm build/test fixture, Maven compile + `runners.maven_run`, configs Micronaut persistées, tests Maven multi-module, session DAP Java, **auto-install LazyGit/LazyDocker** |

Scripts : `.github/workflows/tests/{unit,integration,e2e}/`.

1. **Socle langages (P0)** — ~~Java (jdtls) + Vue/TS (vtsls) + HTML/CSS/JSON/YAML/Bash/XML + prettier / eslint / google-java-format / checkstyle~~ ✅
2. **Navigation & Git (P1)** — ~~neo-tree + keymaps gitsigns~~ ✅
3. **Runners projets (P1)** — ~~npm + Maven (Java / Micronaut)~~ ✅
4. **Debug & Tests (P2)** — ~~DAP + keymaps `mvn test` (setup auto via Mason)~~ ✅
5. **LazyGit / LazyDocker (P2)** — ~~TUI flottant + auto-install binaires (+ JDK / Maven on-demand)~~ ✅
6. **Sessions (P3)** — seulement si le reste est stable

---

## Idées non priorisées

- [ ] Pin de fichiers type Harpoon / arglist
- [ ] Refactoring assisté (`refactoring.nvim`)
- [ ] Indent guides (`indent_line`)
- [ ] Autopairs
- [ ] oil.nvim (écarté au profit de neo-tree)
- [ ] …

---

## Historique utile (référence, pas à merger tel quel)

- `origin/clean-kickstart` — FEATURES.md + LSP Java/Vue + format/lint
- `origin/kickstart-fresh` — oil, lazygit, arglist, java-test, etc.

Cette branche repart **propre** d’upstream ; on réimporte feature par feature selon cette roadmap.
