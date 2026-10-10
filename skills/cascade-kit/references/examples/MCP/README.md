# NotesMCP

Stdio MCP server (`add_note`, `list_notes`) wired with CascadeKit. Tool logic lives in `NotesKit`
and reads its store via `@Dependency(\.noteStore)`; `NotesServer/main.swift` is the composition root
(`AppScope` + singleton with `onShutdown`, bound by `withDependencies`, `app.shutdown()` on exit).

```sh
cd <your-project>
/usr/bin/swift test
/usr/bin/swift build
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cli","version":"1"}}}' | .build/out/Products/Debug/NotesServer
```

Claude Desktop config: `{"mcpServers":{"notes":{"command":"/abs/path/<your-project>/.build/out/Products/Debug/NotesServer"}}}`
