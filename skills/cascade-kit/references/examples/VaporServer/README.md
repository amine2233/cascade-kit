# CascadeKit + Vapor example

Vapor owns `Application`/`Request`, so CascadeKit's containers are `AppScope`/`RequestScope`.

- `AppScope` is built in `configure`, registers the `UserRepository` singleton, and is shut down by a `LifecycleHandler`.
- A middleware creates a `RequestScope` per request and binds it with `withDependencies`.
- Handlers read `@Dependency(\.userRepository)`.

```sh
cd <your-project>
swift run Run serve          # http://127.0.0.1:8080
curl -X POST localhost:8080/users -H 'content-type: application/json' -d '{"name":"ada"}'
curl localhost:8080/users/1
swift test                   # overrides the repository via withTestDependencies
```
