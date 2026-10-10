# CascadeKit + Hummingbird 2

A todo API where handlers use `@Dependency(\.todoRepository)`.

- `makeAppScope()` registers the in-memory repository as a singleton with `onShutdown`.
- `RequestScopeMiddleware` creates a `RequestScope` per request and runs the chain inside `withDependencies`.
- `Run` calls `appScope.shutdown()` after `app.runService()` returns (Ctrl-C triggers graceful shutdown).

```
swift run Run
curl -X POST localhost:8080/todos -d '{"title":"milk"}'
curl localhost:8080/todos
swift test
```
