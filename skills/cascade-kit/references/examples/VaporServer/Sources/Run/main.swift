import App
import Vapor

let app = try await Application.make(.detect())
configure(app)
try await app.execute()
try await app.asyncShutdown()
