import CascadeKit
import Hummingbird
import Synchronization

public struct Todo: Codable, Sendable, Equatable, ResponseEncodable {
    public let id: Int
    public let title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

struct NewTodo: Decodable {
    let title: String
}

public protocol TodoRepository: Sendable {
    func all() -> [Todo]
    func add(title: String) -> Todo
}

public final class TodoRepositoryInMemory: TodoRepository {
    private let todos = Mutex<[Todo]>([])

    public init() {}

    public func all() -> [Todo] {
        todos.withLock { $0 }
    }

    public func add(title: String) -> Todo {
        todos.withLock { todos in
            let todo = Todo(id: todos.count + 1, title: title)
            todos.append(todo)
            return todo
        }
    }
}

public struct TodoRepositoryKey: DependencyKey {
    public static var liveValue: any TodoRepository {
        TodoRepositoryInMemory()
    }
}

extension DependencyValues {
    public var todoRepository: any TodoRepository {
        get { self[TodoRepositoryKey.self] }
        set { self[TodoRepositoryKey.self] = newValue }
    }
}
