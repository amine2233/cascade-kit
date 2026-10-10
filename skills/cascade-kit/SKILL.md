---
name: cascade-kit
description: Create or extend a Swift project that uses CascadeKit v2, a dependency-injection package with implicit @Dependency and an explicit AppScope container. Use when the user wants to start a new Swift app, CLI (swift-argument-parser), Vapor server, Hummingbird server or MCP server with CascadeKit, add dependency injection or testable services to a Swift project, write DependencyKey / withTestDependencies tests, wire AppScope / RequestScope, or migrate CascadeKit v1 code to v2.
---

# CascadeKit

CascadeKit v2 is a zero-dependency Swift package (Swift 6, iOS 18 / macOS 15) with one key type and two ways to set it up:

- **Implicit:** `@Dependency(\.x)` reads a task-local value; `withDependencies` / `withTestDependencies` override it for a scope.
- **Explicit:** `AppScope` / `RequestScope` containers with `register` / `make` / `resolve`, singleton or transient lifetimes, and shutdown hooks.
- **Together:** `withDependencies { $0.container = app }` makes `@Dependency` return the container's registrations.

Package URL: `https://github.com/amine2233/cascade-kit.git`, `from: "2.0.0"`, product `CascadeKit`.

## Workflow: create a new project

1. **Pick the project type** from the table. Ask the user only if it is not clear from the request.

   | Type | Reference example | Extra dependency |
   | --- | --- | --- |
   | Command-line tool | `references/examples/CLI` | swift-argument-parser |
   | Vapor server | `references/examples/VaporServer` | vapor |
   | Hummingbird 2 server | `references/examples/HummingbirdTodo` | hummingbird |
   | MCP server (stdio) | `references/examples/MCP` | modelcontextprotocol/swift-sdk |
   | SwiftUI app or plain library | `references/swiftui-and-library.md` | none |

2. **Copy the example** into the new project directory and rename it. Read its `README.md` and `Package.swift` first. Rename the package, targets and types to the user's domain; keep the structure.
   - Name the project directory differently from any dependency (`Vapor`, `Hummingbird`, `MCP` would collide with the dependency's package identity).
   - Keep logic in a library target and the executable thin, so tests can import it.
3. **Define services** as `DependencyKey` values with an accessor on `DependencyValues` (see `references/api.md`). Put each service behind a protocol; give the live implementation a descriptive suffix, not `Impl`.
4. **Write the composition root**: build an `AppScope`, `register` services that need a lifetime or `onShutdown`, bind it with `withDependencies { $0.container = app }`, and call `app.shutdown()` when the process ends (`defer` in a CLI, a lifecycle handler on a server).
5. **For servers**, create a `RequestScope(application:)` per request in a middleware and bind it, so handlers read `@Dependency` directly.
6. **Add tests** that use `withTestDependencies { $0.x = stub } operation: { … }`. Prefer Swift Testing.
7. **Build and test** with the toolchain the project targets (`swift build`, `swift test`). Fix compiler errors before reporting done.

## Rules that prevent bugs

- Declare accessors with a getter **and** setter, or `withDependencies { $0.x = … }` will not compile.
- Resolution order: explicit override, then the bound container, then the context default (`liveValue`, `previewValue`, `testValue`).
- `withTestDependencies` ignores a container bound outside it; bind the container inside the closure to opt in. A forgotten override then reaches `testValue`, not a real service.
- `testValue` is built once per `withTestDependencies` scope, so a stateful stub keeps its state across reads.
- Singleton factories run under root values: a caller's overrides are never captured in a cached instance. Transient factories see the caller's values.
- A factory or default that resolves its own key traps with `Recursive resolution of <Key>`. Break the cycle.
- Overrides do not cross `Task.detached` or `DispatchQueue`. Capture `DependencyValues.current` and re-bind with `DependencyValues.$current.withValue(values) { … }`.
- `make` traps when nothing is registered; use `resolve` (throws `CascadeKitError.serviceNotRegistered`) where that must be handled.
- Do not name your own types `Application` or `Request` in Vapor targets without module qualification; CascadeKit's container types are `AppScope` and `RequestScope` for that reason.

## Workflow: extend or migrate an existing project

- To add a service: key + accessor + registration + a test override. Search for an existing key and accessor naming pattern first and match it.
- To migrate v1 to v2, read `references/migration-v1-to-v2.md`; it lists every rename and behavior change with a checklist.

## References

- `references/api.md`: API cheat sheet with code for every feature.
- `references/swiftui-and-library.md`: app and library patterns.
- `references/migration-v1-to-v2.md`: v1 to v2 changes.
- `references/examples/`: four complete packages (CLI, VaporServer, HummingbirdTodo, MCP), each with tests and a README. Their `Package.swift` files point at the published package URL.
