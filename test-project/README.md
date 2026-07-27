# test-project

Multi-module Maven demo used to validate kickstart P2 (Maven tests + Java DAP).

```
kickstart-demo/
├── domain/           # pure Java domain
├── api/              # ports / contracts (depends on domain)
└── infrastructure/   # Micronaut app only (depends on api + domain)
```

## Commands

```bash
cd test-project
mvn clean verify
```

Neovim keymaps (from any module source file):

- `<leader>jt` / `jm` / `ja` → `mvn -pl :<module> -am test …`
- `F5` on `infrastructure/.../DebugProbe.java` after jdtls attaches
