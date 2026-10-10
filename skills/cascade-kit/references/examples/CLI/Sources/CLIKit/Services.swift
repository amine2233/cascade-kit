import CascadeKit
import Foundation

public protocol Greeter: Sendable {
    func greeting(for name: String) -> String
}

public struct GreeterFriendly: Greeter {
    public init() {}

    public func greeting(for name: String) -> String {
        "Hello, \(name)!"
    }
}

public struct GreeterFixed: Greeter {
    public init() {}

    public func greeting(for name: String) -> String {
        "greeting:\(name)"
    }
}

public protocol StatusService: Sendable {
    func summary() -> String
    func close()
}

public final class StatusServiceLive: StatusService {
    private let startedAt = Date()

    public init() {}

    public func summary() -> String {
        "ok, up \(Int(Date().timeIntervalSince(startedAt)))s"
    }

    public func close() {
        FileHandle.standardError.write(Data("status service closed\n".utf8))
    }
}

public struct StatusServiceFixed: StatusService {
    public init() {}

    public func summary() -> String {
        "ok, up 0s"
    }

    public func close() {}
}

public enum GreeterKey: DependencyKey {
    public static let liveValue: any Greeter = GreeterFriendly()
    public static let testValue: any Greeter = GreeterFixed()
}

public enum StatusServiceKey: DependencyKey {
    public static var liveValue: any StatusService {
        StatusServiceLive()
    }

    public static var testValue: any StatusService {
        StatusServiceFixed()
    }
}

extension DependencyValues {
    public var greeter: any Greeter {
        get { self[GreeterKey.self] }
        set { self[GreeterKey.self] = newValue }
    }

    public var statusService: any StatusService {
        get { self[StatusServiceKey.self] }
        set { self[StatusServiceKey.self] = newValue }
    }
}
