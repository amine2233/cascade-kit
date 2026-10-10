import CascadeKit

public protocol NoteStore: Sendable {
    func add(_ text: String) async -> Int
    func all() async -> [String]
}

public actor NoteStoreInMemory: NoteStore {
    private var notes: [String] = []

    public init() {}

    public func add(_ text: String) -> Int {
        notes.append(text)
        return notes.count
    }

    public func all() -> [String] {
        notes
    }
}

public enum NoteStoreKey: DependencyKey {
    public static var liveValue: any NoteStore {
        NoteStoreInMemory()
    }
}

extension DependencyValues {
    public var noteStore: any NoteStore {
        get { self[NoteStoreKey.self] }
        set { self[NoteStoreKey.self] = newValue }
    }
}
