import CascadeKit
import Testing
@testable import NotesKit

@Suite
struct NoteToolsTests {
    @Test
    func addThenListUsesInjectedStore() async throws {
        let store = NoteStoreInMemory()
        try await withTestDependencies { $0.noteStore = store } operation: {
            let tools = NoteTools()
            let added = try await tools.addNote(text: "  buy milk ")
            let listed = await tools.listNotes()
            #expect(added == "Added note #1")
            #expect(listed == "1. buy milk")
        }
        let stored = await store.all()
        #expect(stored == ["buy milk"])
    }

    @Test
    func emptyTextIsRejected() async {
        await withTestDependencies {
            await #expect(throws: NotesError.emptyText) { try await NoteTools().addNote(text: "   ") }
        }
    }
}
