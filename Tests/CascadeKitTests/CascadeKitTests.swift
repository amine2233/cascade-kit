import Foundation
import Testing
@testable import CascadeKit

// =============================================================================
// MARK: - Test fixtures

// =============================================================================

/// A thread-safe counter for observing shutdown side effects.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock(); _value += 1; lock.unlock()
    }
}

// --- A simple service resolved via @Dependency ------------------------------

private protocol Greeter: Sendable {
    func greet() -> String
}

private struct LiveGreeter: Greeter {
    func greet() -> String {
        "live"
    }
}

private struct NamedGreeter: Greeter {
    let name: String
    func greet() -> String {
        name
    }
}

private enum GreeterKey: DependencyKey {
    static let liveValue: any Greeter = LiveGreeter()
    static let previewValue: any Greeter = NamedGreeter(name: "preview")
    static let testValue: any Greeter = NamedGreeter(name: "test")
}

extension DependencyValues {
    fileprivate var greeter: any Greeter {
        get { self[GreeterKey.self] }
        set { self[GreeterKey.self] = newValue }
    }
}

/// A reducer-shaped consumer that reads its dependency implicitly.
private struct Feature {
    @Dependency(\.greeter) var greeter
    func run() -> String {
        greeter.greet()
    }
}

// --- Plain StorageKeys for the low-level Storage tests -----------------------

private enum IntKey: StorageKey { typealias Value = Int }
private enum StringKey: StorageKey { typealias Value = String }

// --- Reference-type services for the Container tests -------------------------

private final class Connection: Sendable {
    let id = UUID()
}

private final class Repo: Sendable {
    let conn: Connection
    init(conn: Connection) {
        self.conn = conn
    }
}

private enum ConnectionKey: ServiceKey { typealias Value = Connection }
private enum RepoKey: ServiceKey { typealias Value = Repo }

// =============================================================================
// MARK: - Storage (type-keyed primitive)

// =============================================================================

@Suite
struct StorageTests {
    @Test
    func setAndGetRoundTrips() {
        let storage = Storage()
        storage.set(IntKey.self, to: 42)
        #expect(storage.get(IntKey.self) == 42)
    }

    @Test
    func absentKeyReturnsNil() {
        let storage = Storage()
        #expect(storage.get(IntKey.self) == nil)
    }

    @Test
    func containsReflectsPresence() {
        let storage = Storage()
        #expect(storage.contains(IntKey.self) == false)
        storage.set(IntKey.self, to: 1)
        #expect(storage.contains(IntKey.self) == true)
    }

    @Test
    func overwriteReplacesValue() {
        let storage = Storage()
        storage.set(IntKey.self, to: 1)
        storage.set(IntKey.self, to: 2)
        #expect(storage.get(IntKey.self) == 2)
    }

    @Test
    func settingNilRemovesValue() {
        let storage = Storage()
        storage.set(IntKey.self, to: 1)
        storage.set(IntKey.self, to: nil)
        #expect(storage.get(IntKey.self) == nil)
        #expect(storage.contains(IntKey.self) == false)
    }

    @Test
    func distinctKeysAreIndependent() {
        let storage = Storage()
        storage.set(IntKey.self, to: 7)
        storage.set(StringKey.self, to: "hi")
        #expect(storage.get(IntKey.self) == 7)
        #expect(storage.get(StringKey.self) == "hi")
    }

    @Test
    func onShutdownFiresWhenRemoved() {
        let counter = Counter()
        let storage = Storage()
        storage.set(IntKey.self, to: 1, onShutdown: { _ in counter.increment() })
        #expect(counter.value == 0)
        storage.set(IntKey.self, to: nil)
        #expect(counter.value == 1)
    }

    @Test
    func onShutdownFiresWhenOverwritten() {
        let counter = Counter()
        let storage = Storage()
        storage.set(IntKey.self, to: 1, onShutdown: { _ in counter.increment() })
        storage.set(IntKey.self, to: 2) // evicts the previous value
        #expect(counter.value == 1)
    }

    @Test
    func shutdownAllFiresEveryHookAndClears() {
        let counter = Counter()
        let storage = Storage()
        storage.set(IntKey.self, to: 1, onShutdown: { _ in counter.increment() })
        storage.set(StringKey.self, to: "x", onShutdown: { _ in counter.increment() })
        storage.shutdownAll()
        #expect(counter.value == 2)
        #expect(storage.get(IntKey.self) == nil)
        #expect(storage.get(StringKey.self) == nil)
    }
}

// =============================================================================
// MARK: - DependencyValues & context resolution

// =============================================================================

@Suite
struct DependencyValuesTests {
    @Test
    func liveContextUsesLiveValue() {
        let values = DependencyValues() // context defaults to .live
        #expect(values.greeter.greet() == "live")
    }

    @Test
    func previewContextUsesPreviewValue() {
        var values = DependencyValues()
        values.context = .preview
        #expect(values.greeter.greet() == "preview")
    }

    @Test
    func contextUsesTestValue() {
        var values = DependencyValues()
        values.context = .test
        #expect(values.greeter.greet() == "test")
    }

    @Test
    func explicitOverrideBeatsContextDefault() {
        var values = DependencyValues()
        values.context = .test
        values.greeter = NamedGreeter(name: "explicit")
        #expect(values.greeter.greet() == "explicit")
    }
}

// =============================================================================
// MARK: - @Dependency + withDependencies

// =============================================================================

@Suite
struct DependencyResolutionTests {
    @Test
    func dependencyDefaultsToLive() {
        #expect(Feature().run() == "live")
    }

    @Test
    func overrideAppliesInsideScope() {
        let result = withDependencies {
            $0.greeter = NamedGreeter(name: "scoped")
        } operation: {
            Feature().run()
        }
        #expect(result == "scoped")
    }

    @Test
    func overrideDoesNotLeakAfterScope() {
        withDependencies {
            $0.greeter = NamedGreeter(name: "scoped")
        } operation: {
            #expect(Feature().run() == "scoped")
        }
        // Binding ended — back to the live default.
        #expect(Feature().run() == "live")
    }

    @Test
    func overridesNestAndRestore() {
        withDependencies {
            $0.greeter = NamedGreeter(name: "outer")
        } operation: {
            #expect(Feature().run() == "outer")
            withDependencies {
                $0.greeter = NamedGreeter(name: "inner")
            } operation: {
                #expect(Feature().run() == "inner")
            }
            #expect(Feature().run() == "outer") // inner scope unwound
        }
    }

    @Test
    func asyncOverrideApplies() async {
        let result = await withDependencies {
            $0.greeter = NamedGreeter(name: "async")
        } operation: {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return Feature().run()
        }
        #expect(result == "async")
    }
}

// =============================================================================
// MARK: - Test sugar

// =============================================================================

@Suite
struct TestSugarTests {
    @Test
    func sugarUnoverriddenUsesTestValue() async {
        let result = await withTestDependencies {
            Feature().run()
        }
        #expect(result == "test") // .test context → testValue
    }

    @Test
    func sugarOverrideBeatsTestValue() async {
        let result = await withTestDependencies {
            $0.greeter = NamedGreeter(name: "mock")
        } operation: {
            Feature().run()
        }
        #expect(result == "mock")
    }

    @Test
    func syncTestSugarWorks() {
        let result = withTestDependencies {
            $0.greeter = NamedGreeter(name: "sync")
        } operation: {
            Feature().run()
        }
        #expect(result == "sync")
    }
}

// =============================================================================
// MARK: - Task isolation & the detached footgun

// =============================================================================

@Suite
struct TaskIsolationTests {
    /// Two concurrently-bound overrides must not bleed into each other.
    /// This is the property that makes the library safe under Swift Testing's
    /// parallel execution.
    @Test
    func concurrentOverridesAreIsolated() async {
        async let a: String = withTestDependencies {
            $0.greeter = NamedGreeter(name: "A")
        } operation: {
            try? await Task.sleep(nanoseconds: 2_000_000) // force overlap
            return Feature().run()
        }
        async let b: String = withTestDependencies {
            $0.greeter = NamedGreeter(name: "B")
        } operation: {
            Feature().run()
        }
        let (ra, rb) = await (a, b)
        #expect(ra == "A")
        #expect(rb == "B")
    }

    /// A plain `Task {}` copies the current bindings; a `Task.detached` inherits
    /// nothing and therefore falls back to the live default. This test pins that
    /// documented behavior so a regression is caught.
    @Test
    func detachedTaskLosesOverride() async {
        let (inherited, detached): (String, String) = await withTestDependencies {
            $0.greeter = NamedGreeter(name: "override")
        } operation: {
            let inheritedValue = await Task { Feature().run() }.value
            let detachedValue = await Task.detached { Feature().run() }.value
            return (inheritedValue, detachedValue)
        }
        #expect(inherited == "override") // copied from the binding
        #expect(detached == "live") // no inheritance → live default
    }
}

// =============================================================================
// MARK: - Vapor-style Container (make / register)

// =============================================================================

@Suite
struct ContainerTests {
    @Test
    func singletonReturnsSameInstance() {
        let app = Application()
        app.register(ConnectionKey.self) { _ in Connection() }
        #expect(app.make(ConnectionKey.self) === app.make(ConnectionKey.self))
    }

    @Test
    func transientReturnsFreshInstances() {
        let app = Application()
        app.register(ConnectionKey.self, scope: .transient) { _ in Connection() }
        #expect(app.make(ConnectionKey.self) !== app.make(ConnectionKey.self))
    }

    @Test
    func requestFallsThroughToApplication() {
        let app = Application()
        app.register(ConnectionKey.self) { _ in Connection() }
        let request = Request(application: app)
        // Resolving through the request caches the singleton on the application.
        #expect(request.make(ConnectionKey.self) === app.make(ConnectionKey.self))
    }

    @Test
    func factoryResolvesDependencyGraph() {
        let app = Application()
        app.register(ConnectionKey.self) { _ in Connection() }
        app.register(RepoKey.self) { container in
            Repo(conn: container.make(ConnectionKey.self))
        }
        #expect(app.make(RepoKey.self).conn === app.make(ConnectionKey.self))
    }

    @Test
    func requestTransientReusesApplicationSingletonDependency() {
        let app = Application()
        app.register(ConnectionKey.self) { _ in Connection() } // app singleton
        let request = Request(application: app)
        request.register(RepoKey.self, scope: .transient) { container in
            Repo(conn: container.make(ConnectionKey.self))
        }
        let r1 = request.make(RepoKey.self)
        let r2 = request.make(RepoKey.self)
        #expect(r1 !== r2) // repo is transient
        #expect(r1.conn === r2.conn) // but shares the one app connection
    }

    @Test
    func applicationShutdownRunsHooks() {
        let counter = Counter()
        let app = Application()
        app.storage.set(IntKey.self, to: 1, onShutdown: { _ in counter.increment() })
        app.shutdown()
        #expect(counter.value == 1)
    }
}
