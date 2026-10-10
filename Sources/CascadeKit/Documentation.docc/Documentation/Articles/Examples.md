# Examples

Four runnable packages show CascadeKit in a command-line tool, two web servers and an MCP server.

## Overview

Each example is in `skills/cascade-kit/references/examples/` with its own `Package.swift` that depends on the published package, so the library stays dependency free. They are also the reference templates of the `cascade-kit` agent skill. Every one follows the same shape:

1. Declare services as ``DependencyKey`` values and expose them on ``DependencyValues``.
2. Build an ``AppScope`` at the composition root and register the services that need a lifetime or a shutdown hook.
3. Bind the container with `withDependencies { $0.container = … }` around the work.
4. Read services with `@Dependency` and test them with `withTestDependencies`.

Run an example from its directory with `swift run` and test it with `swift test`.

## Command-line tool

`references/examples/CLI` uses swift-argument-parser. The logic lives in a library target so it can be tested without parsing arguments.

```swift
public struct Actions: Sendable {
    @Dependency(\.greeter) private var greeter
    @Dependency(\.statusService) private var statusService
}

public func runInApp<R>(_ body: () async throws -> R) async rethrows -> R {
    let app = AppScope()
    app.register(StatusServiceKey.self, onShutdown: { $0.close() }) { _ in StatusServiceLive() }
    defer { app.shutdown() }
    return try await withDependencies({ $0.container = app }, operation: body)
}

struct Greet: AsyncParsableCommand {
    @Argument var name: String

    func run() async throws {
        print(try await runInApp { try Actions().greet(name: name) })
    }
}
```

`defer { app.shutdown() }` guarantees the shutdown hooks run when the command ends or throws.

## Vapor

`references/examples/VaporServer` shows why the container types are named ``AppScope`` and ``RequestScope``: Vapor already owns `Application` and `Request`. A middleware creates a request scope for each request and binds it, so handlers read `@Dependency` without touching the request.

```swift
struct RequestScopeMiddleware: AsyncMiddleware {
    let appScope: AppScope

    func respond(to request: Vapor.Request, chainingTo next: any AsyncResponder) async throws -> Vapor.Response {
        let requestScope = RequestScope(application: appScope)
        return try await withDependencies {
            $0.container = requestScope
        } operation: {
            try await next.respond(to: request)
        }
    }
}

struct AppScopeShutdown: LifecycleHandler {
    let appScope: AppScope

    func shutdown(_ application: Vapor.Application) {
        appScope.shutdown()
    }
}
```

The application's singletons are visible through the request scope, and anything registered on the request scope stays private to that request. A Vapor test overrides the repository with `withTestDependencies`.

## Hummingbird

`references/examples/HummingbirdTodo` uses the same middleware idea with Hummingbird 2's `RouterMiddleware`.

```swift
struct RequestScopeMiddleware<Context: RequestContext>: RouterMiddleware {
    let appScope: AppScope

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let requestScope = RequestScope(application: appScope)
        return try await withDependencies {
            $0.container = requestScope
        } operation: {
            try await next(request, context)
        }
    }
}
```

The entry point shuts the scope down once the server stops:

```swift
let appScope = makeAppScope()
let app = buildApplication(appScope: appScope)
do {
    try await app.runService()
} catch {
    appScope.shutdown()
    throw error
}
appScope.shutdown()
```

## MCP server

`references/examples/MCP` is a stdio server built on the Swift MCP SDK with two tools, `add_note` and `list_notes`. The tool logic reads its store with `@Dependency`, so a test swaps in an in-memory store.

```swift
public struct NoteTools: Sendable {
    @Dependency(\.noteStore) private var store

    public func addNote(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NotesError.emptyText }
        return "Added note #\(await store.add(trimmed))"
    }
}
```

The composition root registers the store with a shutdown hook and binds the container around the server run:

```swift
let app = AppScope()
app.register(NoteStoreKey.self, onShutdown: { _ in … }) { _ in NoteStoreInMemory() }

try await withDependencies { $0.container = app } operation: {
    try await run()
}
app.shutdown()
```

## Notes

- Name an example package directory differently from its dependency. SwiftPM derives a package identity from the directory name, so a directory called `Vapor` or `Hummingbird` collides with the dependency of the same name. That is why these are `VaporServer` and `HummingbirdTodo`.
- Overrides do not cross `Task.detached` or dispatch queues. Servers that hand work to those must re-bind the values; see the propagation table in <doc:CompleteGuide>.
