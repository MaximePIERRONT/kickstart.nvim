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
| Formatage | [x] | `conform.nvim` : prettier (web), stylua, shfmt ; Java utilise par défaut le profil Eclipse 4 espaces de `config/formatter/eclipse-java.xml` via jdtls, avec Google Java Format sélectionnable (`:JavaFormat`, `<leader>jf`) |
| Linter | [x] | `nvim-lint` : eslint_d, shellcheck, markdownlint, checkstyle |

**Critère de done P0 :** ouvrir un fichier `.java`, `.vue`, `.ts` et avoir LSP + completion + format + lint utilisables.

### Format Java

- Par défaut, `jdtls` applique le profil Eclipse `Default` de `config/formatter/eclipse-java.xml`.
- `:JavaFormat` ou `<leader>jf` ouvre un sélecteur, comme le choix de code style d'un IDE.
- `:JavaFormat eclipse` restaure le profil du dépôt ; `:JavaFormat google` active
  `google-java-format` pour la session Neovim. `<leader>f` applique le choix courant.

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
| Tests | [x] | Keymaps Maven multi-module : `<leader>jt` / `jm` / `ja` + `:MavenTest` → `mvn -pl :<module> -am` ; `<leader>jT` bascule entre `src/main/java/Foo.java` et `src/test/java/FooTest.java` (pas de neotest) ; CI dans `.github/workflows/java-dap-ci.yml` |
| Snippets | [~] | LuaSnip OK ; `friendly-snippets` encore commenté |
| LazyGit dans l’interface Neovim | [x] | `<leader>gg` / `:LazyGit` — terminal flottant ; **auto-install** binaire via `custom.ensure_tool` (GitHub releases) |
| LazyDocker dans l’interface Neovim | [x] | `<leader>ld` / `:LazyDocker` — idem auto-install |
| LazySQL dans l’interface Neovim | [x] | `<leader>ls` / `:LazySQL` — explorateur SQL TUI ; idem auto-install |

**Critère de done P2 :** debugger + tests Maven + LazyGit / LazyDocker / LazySQL ✅ (snippets optionnels).

---

## Auto-install des dépendances

Objectif Ubuntu / Arch : **paquets système minimaux**, le reste au **démarrage de Neovim** ou via **Mason**.

### Paquets OS uniquement (apt / pacman)

| Paquet | Pourquoi |
| --- | --- |
| `neovim` (≥ 0.12) | éditeur |
| `git` | plugins `vim.pack` |
| `curl` (ou `wget`) | téléchargements |
| `unzip` + `tar` + `gzip` + `xz` (`xz-utils` sur Ubuntu) | archives (JDK `.tar.gz`, Node `.tar.xz`) |
| `gcc` + `make` | `telescope-fzf-native` / compile parsers |

### Auto au démarrage / à la demande

Quand un outil manque, la config le télécharge dans `stdpath('data')/kickstart-tools` (préfixe `$PATH`) :

| Outil | Déclencheur | Source |
| --- | --- | --- |
| **Node.js LTS** + npm | sync avant Mason (startup) | nodejs.org dist |
| **JDK 21+** (jdtls) | sync avant Mason si `JAVA_HOME` absent / &lt; 21 | Eclipse Temurin (Adoptium) |
| **ripgrep** (`rg`) | sync startup + warm | GitHub releases |
| **fd** | sync startup + warm | GitHub releases |
| **Maven** (`mvn`) | warm VimEnter / premier `:Maven` / tests | Apache Maven binary |
| **lazygit** | warm VimEnter / `<leader>gg` | GitHub releases |
| **lazydocker** | warm VimEnter / `<leader>ld` | GitHub releases |
| **lazysql** | warm VimEnter / `<leader>ls` | GitHub releases |
| LSP / formatters / DAP / `tree-sitter-cli` | Mason (`mason-tool-installer` au démarrage) | Mason registry |

Module : `lua/custom/ensure_tool.lua`. Commande manuelle : `:KickstartEnsureTools`.

**Non auto-installé :** le démon Docker (LazyDocker a besoin que Docker tourne déjà).

---

## P3 — Plus tard

| Feature | Statut | Notes |
| --- | --- | --- |
| UI / theme | [x] | Catppuccin Latte (clair) |
| Sessions | [ ] | Restaurer onglets / buffers entre sessions |
| IA / assistants code | [-] | Hors scope |

---

## Couverture de tests

Suite CI : `.github/workflows/features-ci.yml`

| Couche | Ce qui est vérifié |
| --- | --- |
| **Unit (Lua)** | Helpers `maven-tests` (FQCN, reactor `-pl/-am`) + `runners` (env/dotenv, Micronaut cmd, `runners.json`, scripts npm, `pom_has`) + `ensure_tool` (os/arch, asset URLs rg/fd/node/lazygit/lazysql, PATH, paquets OS) |
| **Unit/intégration (Java)** | `test-project` multi-module — domain / api / infrastructure (Micronaut) via `mvn verify` |
| **Integration (Neovim)** | Boot config, plugins (dap, neo-tree, telescope, conform, lint, blink, …), keymaps/commandes (LazyGit/LazyDocker/LazySQL/KickstartEnsureTools), Mason P0/P2, jdtls attach, format java/ts, neo-tree + gitsigns |
| **E2E (Neovim)** | npm build/test fixture, Maven compile + `runners.maven_run`, configs Micronaut persistées, tests Maven multi-module, session DAP Java, **auto-install rg/fd/LazyGit/LazyDocker/LazySQL/Maven** |

Scripts : `.github/workflows/tests/{unit,integration,e2e}/`.

1. **Socle langages (P0)** — ~~Java (jdtls) + Vue/TS (vtsls) + HTML/CSS/JSON/YAML/Bash/XML + prettier / eslint / google-java-format / checkstyle~~ ✅
2. **Navigation & Git (P1)** — ~~neo-tree + keymaps gitsigns~~ ✅
3. **Runners projets (P1)** — ~~npm + Maven (Java / Micronaut)~~ ✅
4. **Debug & Tests (P2)** — ~~DAP + keymaps `mvn test` (setup auto via Mason)~~ ✅
5. **LazyGit / LazyDocker / LazySQL (P2)** — ~~TUI flottant + auto-install binaires (+ JDK / Maven on-demand)~~ ✅
6. **Install facile Ubuntu / Arch** — ~~paquets OS minimaux ; Node / JDK / rg / fd / Maven / Lazy* + Mason au démarrage~~ ✅
7. **Sessions (P3)** — seulement si le reste est stable

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
