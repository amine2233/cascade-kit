# CascadeKit CLI example

A thin `swift-argument-parser` executable (`cascade-cli`) over a testable `CLIKit` library.

```sh
cd <your-project>
/usr/bin/swift run cascade-cli greet Ada
/usr/bin/swift run cascade-cli status
/usr/bin/swift test
```

- `Services.swift`: `DependencyKey`s and the `DependencyValues` extension.
- `Actions.swift`: command logic via `@Dependency`, plus the composition root (`runInApp`: `AppScope`, `register(_:onShutdown:)`, `withDependencies`, `shutdown()`).
- Tests override dependencies with `withTestDependencies`.
- Diagnostics (service shutdown) go to stderr; results go to stdout.
