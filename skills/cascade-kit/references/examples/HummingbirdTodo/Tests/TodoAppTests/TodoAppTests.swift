import CascadeKit
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import TodoApp

struct TodoRepositoryStub: TodoRepository {
    func all() -> [Todo] {
        [Todo(id: 42, title: "stubbed")]
    }

    func add(title: String) -> Todo {
        Todo(id: 43, title: title)
    }
}

@Suite
struct TodoAppTests {
    @Test
    func listUsesOverriddenRepository() async throws {
        try await withTestDependencies {
            $0.todoRepository = TodoRepositoryStub()
        } operation: {
            let app = buildApplication(appScope: AppScope())
            try await app.test(.router) { client in
                try await client.execute(uri: "/todos", method: .get) { response in
                    #expect(response.status == .ok)
                    let todos = try JSONDecoder().decode([Todo].self, from: response.body)
                    #expect(todos == [Todo(id: 42, title: "stubbed")])
                }
            }
        }
    }

    @Test
    func postUsesRegisteredRepository() async throws {
        let app = buildApplication(appScope: makeAppScope())
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/todos", method: .post, body: ByteBuffer(string: #"{"title":"milk"}"#)
            ) { response in
                #expect(response.status == .created)
            }
            try await client.execute(uri: "/todos", method: .get) { response in
                let todos = try JSONDecoder().decode([Todo].self, from: response.body)
                #expect(todos == [Todo(id: 1, title: "milk")])
            }
        }
    }
}
