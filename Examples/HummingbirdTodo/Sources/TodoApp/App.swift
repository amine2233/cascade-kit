import CascadeKit
import Hummingbird

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

public func makeAppScope() -> AppScope {
    let appScope = AppScope()
    appScope.register(TodoRepositoryKey.self, onShutdown: { _ in print("TodoRepository shut down") }) { _ in
        TodoRepositoryInMemory()
    }
    return appScope
}

public func buildApplication(appScope: AppScope) -> some ApplicationProtocol {
    let router = Router()
    router.add(middleware: RequestScopeMiddleware(appScope: appScope))

    router.get("todos") { _, _ -> [Todo] in
        @Dependency(\.todoRepository) var repository
        return repository.all()
    }

    router.post("todos") { request, context -> EditedResponse<Todo> in
        @Dependency(\.todoRepository) var repository
        let body = try await request.decode(as: NewTodo.self, context: context)
        return EditedResponse(status: .created, response: repository.add(title: body.title))
    }

    return Application(router: router)
}
