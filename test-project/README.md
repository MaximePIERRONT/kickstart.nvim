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
- `<leader>jT` → bascule entre un fichier `src/main/java/.../Foo.java` et son test `src/test/java/.../FooTest.java`
- `F5` on `infrastructure/.../DebugProbe.java` after jdtls attaches
