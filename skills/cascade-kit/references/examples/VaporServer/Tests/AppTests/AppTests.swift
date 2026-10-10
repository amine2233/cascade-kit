import CascadeKit
import Testing
import VaporTesting
@testable import App

struct UserRepositoryStub: UserRepository {
    func find(id: Int) async -> User? {
        User(id: id, name: "stub")
    }

    func create(name: String) async -> User {
        User(id: 99, name: name)
    }
}

@Suite
struct AppTests {
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        configure(app)
        return app
    }

    @Test
    func getUsesOverriddenRepository() async throws {
        let app = try await makeApp()
        try await withTestDependencies {
            $0.userRepository = UserRepositoryStub()
        } operation: {
            try await app.testing().test(.GET, "users/7") { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(User.self) == User(id: 7, name: "stub"))
            }
        }
        try await app.asyncShutdown()
    }

    @Test
    func postThenGetUsesRegisteredRepository() async throws {
        let app = try await makeApp()
        try await app.testing().test(.POST, "users", beforeRequest: { req in
            try req.content.encode(["name": "ada"])
        }, afterResponse: { res async throws in
            #expect(try res.content.decode(User.self) == User(id: 1, name: "ada"))
        })
        try await app.testing().test(.GET, "users/1") { res async throws in
            #expect(try res.content.decode(User.self).name == "ada")
        }
        try await app.testing().test(.GET, "users/2") { res async throws in
            #expect(res.status == .notFound)
        }
        try await app.asyncShutdown()
    }
}
