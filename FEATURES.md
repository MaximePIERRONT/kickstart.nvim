# Roadmap des features — kickstart.nvim

Branche de travail : `cursor/from-upstream-master-c628` (base upstream `nvim-lua/kickstart.nvim`).

Objectif : reconstruire une config Neovim personnelle, propre, en repartant d’upstream, avec une roadmap claire et priorisée.

Légende du statut :

- `[x]` déjà disponible / acceptable sur la base actuelle
- `[~]` partiellement présent (kickstart de base ou exemple commenté) — à activer / enrichir
- `[ ]` à faire

---

## P0 — Indispensable (socle IDE)

| Feature | Statut | Notes |
| --- | --- | --- |
| LSP | [~] | Kickstart fournit le socle Mason + LSP ; à étendre (Java / Vue / web) |
| Autocompletion | [x] | `blink.cmp` + LuaSnip déjà en place |
| Formatage | [~] | `conform.nvim` présent ; formatters JS/TS/Vue/Java à brancher |
| Linter | [~] | Exemple `kickstart.plugins.lint` commenté ; eslint / checkstyle à activer |

**Critère de done P0 :** ouvrir un fichier `.java`, `.vue`, `.ts` et avoir LSP + completion + format + lint utilisables.

---

## P1 — Important (workflow quotidien)

| Feature | Statut | Notes |
| --- | --- | --- |
| Navigation projet | [~] | Telescope files OK ; explorateur (oil / neo-tree) à choisir |
| Recherche fuzzy finder | [x] | Telescope (fichiers, grep, LSP) déjà là |
| Git | [~] | `gitsigns` de base ; keymaps hunks + LazyGit en P2 |
| Lancer facilement un projet frontend avec npm | [ ] | Commandes / keymaps pour `npm run …` (dev, build, test) |
| Lancer facilement un projet backend Java | [ ] | LSP jdtls (JDK 21+) + run Maven/Gradle depuis Neovim |
| Lancer facilement un projet backend Micronaut | [ ] | Au-dessus de Java : run / rechargement Micronaut |

**Critère de done P1 :** démarrer frontend npm **et** backend Java/Micronaut sans quitter Neovim.

---

## P2 — Confort

| Feature | Statut | Notes |
| --- | --- | --- |
| Debug | [~] | Exemple `kickstart.plugins.debug` commenté ; DAP Java / JS à brancher |
| Tests | [ ] | Runner tests Java (Maven/Surefire) + éventuellement frontend |
| Snippets | [~] | LuaSnip OK ; `friendly-snippets` encore commenté |
| LazyGit dans l’interface Neovim | [ ] | Terminal flottant / plugin LazyGit |
| LazyDocker dans l’interface Neovim | [ ] | Idem pour Docker |

**Critère de done P2 :** debugger, lancer les tests, et gérer git/docker sans sortir de Neovim.

---

## P3 — Plus tard

| Feature | Statut | Notes |
| --- | --- | --- |
| UI / theme | [~] | Tokyo Night déjà présent ; polish optionnel |
| Sessions | [ ] | Restaurer onglets / buffers entre sessions |
| IA / assistants code | [ ] | À trancher plus tard (Copilot, Codeium, etc.) |

---

## Ordre d’implémentation proposé

1. **Socle langages (P0)** — Java (jdtls) + Vue/TS (vtsls) + HTML/CSS/JSON/YAML/Bash/XML + prettier / eslint / google-java-format / checkstyle
2. **Navigation & Git (P1)** — oil ou neo-tree + keymaps gitsigns
3. **Runners projets (P1)** — npm + Java/Maven + Micronaut
4. **Debug & Tests (P2)** — DAP + runner de tests
5. **LazyGit / LazyDocker (P2)**
6. **Sessions / IA (P3)** — seulement si le reste est stable

---

## Décisions ouvertes (à trancher ensemble)

1. Explorateur de fichiers : **oil.nvim** (déjà utiliséé sur `kickstart-fresh`) ou **neo-tree** (exemple kickstart) ?
2. Stack Java : **Maven uniquement**, ou Maven + Gradle ?
3. Micronaut : run via terminal intégré, ou tâche dédiée (`:MicronautRun`) ?
4. Tests Java : reprendre le runner custom `java-test` de `kickstart-fresh`, ou un plugin (neotest) ?
5. IA (P3) : on garde hors scope pour l’instant ?

---

## Idées non priorisées

- [ ] Pin de fichiers type Harpoon / arglist (déjà exploré sur `kickstart-fresh`)
- [ ] Refactoring assisté (`refactoring.nvim`)
- [ ] Indent guides (`indent_line`)
- [ ] Autopairs
- [ ] …

---

## Historique utile (référence, pas à merger tel quel)

- `origin/clean-kickstart` — FEATURES.md + LSP Java/Vue + format/lint
- `origin/kickstart-fresh` — oil, lazygit, arglist, java-test, etc.

Cette branche repart **propre** d’upstream ; on réimporte feature par feature selon cette roadmap.
