import CascadeKit
import Foundation

public enum CLIError: Error, Equatable {
    case emptyName
}

public struct Actions: Sendable {
    @Dependency(\.greeter) private var greeter
    @Dependency(\.statusService) private var statusService

    public init() {}

    public func greet(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw CLIError.emptyName }

        return greeter.greeting(for: trimmed)
    }

    public func status() -> String {
        statusService.summary()
    }
}

public func runInApp<R>(_ body: () async throws -> R) async rethrows -> R {
    let app = AppScope()
    app.register(StatusServiceKey.self, onShutdown: { $0.close() }) { _ in StatusServiceLive() }
    defer { app.shutdown() }
    return try await withDependencies({ $0.container = app }, operation: body)
}
