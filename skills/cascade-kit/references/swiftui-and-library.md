# SwiftUI apps and libraries

## SwiftUI app

Use `@Dependency` inside `@Observable` models and override in previews and tests.

```swift
@Observable
final class ItemsModel {
    @ObservationIgnored @Dependency(\.itemsClient) private var client
    private(set) var items: [Item] = []

    func load() async {
        items = (try? await client.fetchItems()) ?? []
    }
}

#Preview {
    withDependencies {
        $0.context = .preview
    } operation: {
        ItemsView(model: ItemsModel())
    }
}
```

Build long-lived services once at launch with an `AppScope`, and bind it where the app starts:

```swift
@main
struct MyApp: App {
    let appScope = AppScope()

    init() {
        appScope.register(DatabaseKey.self) { _ in Database() }
        DependencyValues.current.container = appScope
    }
}
```

`DependencyValues.current` is task-local, so prefer `withDependencies` around the work that needs the container rather than assigning to it. For previews and tests always override with `withDependencies` / `withTestDependencies`.

## Library targets

- Expose services as protocols plus a `DependencyKey` and a `DependencyValues` accessor; do not register on a global container.
- Let the host app choose live and test values.
- Keep CascadeKit as a dependency of the library target that declares keys; the app target and the library share the same `DependencyValues`.
