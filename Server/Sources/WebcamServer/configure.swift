import Fluent
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) async throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let path = Environment.get("DATABASE_PATH") ?? "webcams.sqlite"
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
    }

    // Reachable from the iPhone in the same network / via Tailscale.
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    app.migrations.add(CreateWebcam())
    app.migrations.add(SeedWebcams())
    try await app.autoMigrate()

    // Some public data servers are slow to accept connections.
    app.http.client.configuration.timeout = .init(connect: .seconds(60), read: .seconds(180))
    app.asyncCommands.use(ImportCommand(), as: "import")
    app.asyncCommands.use(ProbeCommand(), as: "probe")
    app.asyncCommands.use(ExportCommand(), as: "export")
    app.asyncCommands.use(DiscoverCommand(), as: "discover")
    try routes(app)
}
