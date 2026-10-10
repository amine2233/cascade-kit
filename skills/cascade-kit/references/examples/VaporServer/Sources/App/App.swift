import CascadeKit
import Vapor

struct RequestScopeMiddleware: AsyncMiddleware {
    let appScope: AppScope

    func respond(to request: Vapor.Request, chainingTo next: any AsyncResponder) async throws -> Vapor
        .Response {
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

struct CreateUser: Content {
    let name: String
}

public func configure(_ app: Vapor.Application) {
    let appScope = AppScope()
    appScope.register(UserRepositoryKey.self, onShutdown: { _ in }) { _ in
        UserRepositoryInMemory()
    }

    app.lifecycle.use(AppScopeShutdown(appScope: appScope))
    app.middleware.use(RequestScopeMiddleware(appScope: appScope))

    app.get("users", ":id") { req async throws -> User in
        @Dependency(\.userRepository) var users
        guard let id = req.parameters.get("id", as: Int.self), let user = await users.find(id: id) else {
            throw Abort(.notFound)
        }

        return user
    }

    app.post("users") { req async throws -> User in
        @Dependency(\.userRepository) var users
        let input = try req.content.decode(CreateUser.self)
        return await users.create(name: input.name)
    }
}
