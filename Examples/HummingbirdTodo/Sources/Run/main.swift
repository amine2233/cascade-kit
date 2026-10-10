import TodoApp

let appScope = makeAppScope()
let app = buildApplication(appScope: appScope)
do {
    try await app.runService()
} catch {
    appScope.shutdown()
    throw error
}

appScope.shutdown()
