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
| Debug | [~] | Exemple `kickstart.plugins.debug` commenté ; DAP Java / JS à brancher |
| Tests | [ ] | Keymaps Maven (`mvn test`, classe / méthode courante) ; outils via Mason quand possible |
| Snippets | [~] | LuaSnip OK ; `friendly-snippets` encore commenté |
| LazyGit dans l’interface Neovim | [ ] | Terminal flottant / plugin LazyGit |
| LazyDocker dans l’interface Neovim | [ ] | Idem pour Docker |

**Critère de done P2 :** debugger, lancer les tests Maven, et gérer git/docker sans sortir de Neovim.

---

## P3 — Plus tard

| Feature | Statut | Notes |
| --- | --- | --- |
| UI / theme | [~] | Tokyo Night déjà présent ; polish optionnel |
| Sessions | [ ] | Restaurer onglets / buffers entre sessions |
| IA / assistants code | [-] | Hors scope |

---

## Ordre d’implémentation

1. **Socle langages (P0)** — ~~Java (jdtls) + Vue/TS (vtsls) + HTML/CSS/JSON/YAML/Bash/XML + prettier / eslint / google-java-format / checkstyle~~ ✅
2. **Navigation & Git (P1)** — ~~neo-tree + keymaps gitsigns~~ ✅
3. **Runners projets (P1)** — ~~npm + Maven (Java / Micronaut)~~ ✅
4. **Debug & Tests (P2)** — DAP + keymaps `mvn test` (setup auto via Mason)
5. **LazyGit / LazyDocker (P2)**
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
