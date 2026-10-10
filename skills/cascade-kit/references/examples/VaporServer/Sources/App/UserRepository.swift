import CascadeKit
import Vapor

public struct User: Content, Equatable {
    public let id: Int
    public let name: String
}

public protocol UserRepository: Sendable {
    func find(id: Int) async -> User?
    func create(name: String) async -> User
}

public actor UserRepositoryInMemory: UserRepository {
    private var users: [Int: User] = [:]

    public init() {}

    public func find(id: Int) -> User? {
        users[id]
    }

    public func create(name: String) -> User {
        let user = User(id: users.count + 1, name: name)
        users[user.id] = user
        return user
    }
}

public struct UserRepositoryKey: DependencyKey {
    public typealias Value = any UserRepository
    public static var liveValue: any UserRepository {
        UserRepositoryInMemory()
    }
}

extension DependencyValues {
    public var userRepository: any UserRepository {
        get { self[UserRepositoryKey.self] }
        set { self[UserRepositoryKey.self] = newValue }
    }
}
