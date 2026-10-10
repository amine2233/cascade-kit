import CascadeKit
import Foundation
import MCP
import NotesKit

let app = AppScope()
app.register(
    NoteStoreKey.self,
    onShutdown: { _ in FileHandle.standardError.write(Data("note store closed\n".utf8)) }
) { _ in
    NoteStoreInMemory()
}

let tools = [
    Tool(
        name: "add_note",
        description: "Store a note",
        inputSchema: [
            "type": "object",
            "properties": ["text": ["type": "string", "description": "Note body"]],
            "required": ["text"]
        ]
    ),
    Tool(
        name: "list_notes",
        description: "List stored notes",
        inputSchema: ["type": "object", "properties": [:]]
    )
]

func run() async throws {
    let server = Server(
        name: "notes",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
    )
    let noteTools = NoteTools()

    await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "add_note":
            guard let text = params.arguments?["text"]?.stringValue else {
                throw MCPError.invalidParams("'text' must be a string")
            }

            do {
                return try await .init(content: [.text(noteTools.addNote(text: text))])
            } catch NotesError.emptyText {
                throw MCPError.invalidParams("'text' must not be empty")
            }
        case "list_notes":
            return await .init(content: [.text(noteTools.listNotes())])
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }

    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
}

do {
    try await withDependencies { $0.container = app } operation: {
        try await run()
    }
} catch {
    FileHandle.standardError.write(Data("server failed: \(error)\n".utf8))
}

app.shutdown()
