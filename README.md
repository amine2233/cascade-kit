# CascadeKit

CascadeKit is a small Swift package that provides lightweight, concurrency-safe
primitives and a simple dependency/DI registry useful for apps and libraries.

Key features
- `Lock`: a minimal mutex wrapper around `NSLock` for safe state mutation.
- `Storage`: type-keyed, thread-safe storage with shutdown hooks.
- `DependencyKey` / `DependencyValues` / `@Dependency`: a simple dependency
  registry and property wrapper for resolving dependencies in different
  contexts (`live`, `preview`, `test`).
- `Container` & `Factory`: Vapor-style scoped container and lazy factories.
- Test helpers: `withDependencies`, `withTestDependencies` for scoped overrides.

Requirements
- Swift 6.3.1 (see `mise.toml`)
- macOS / iOS targets supported by Swift toolchain used in your environment

Install
1. Add as a Swift Package dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/amine2233/cascade-kit.git", from: "1.0.0"),
],
```

2. Add the package to your target's dependencies.

Build & test
```bash
swift build
swift test
```

Developers (helper tasks)
This repository includes `mise` tasks configured in `mise.toml`:
- `mise run format` — format the code
- `mise run test` — run tests
- `mise run release --dry-run` — preview a release (no tag/commit/GitHub release)
- `mise run release` — perform the release (honors `--skip-ci` / `--no-skip-ci`)

That's it — if you want the README expanded (examples, API reference or
badges), tell me what to include and I’ll add it.