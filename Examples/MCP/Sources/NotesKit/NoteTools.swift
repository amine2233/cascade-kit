import CascadeKit
import Foundation

public enum NotesError: Error, Equatable {
    case emptyText
}

public struct NoteTools: Sendable {
    @Dependency(\.noteStore) private var store

    public init() {}

    public func addNote(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NotesError.emptyText }

        let id = await store.add(trimmed)
        return "Added note #\(id)"
    }

    public func listNotes() async -> String {
        let notes = await store.all()
        guard !notes.isEmpty else { return "No notes yet." }

        return notes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}
