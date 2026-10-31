import Fluent
import Foundation
import Vapor
import WebcamKit

/// `swift run WebcamServer export [--output path]` writes the list the app ships with.
struct ExportCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "output", help: "Target file (default: ../App/WebcamGlobe/webcams.json)")
        var output: String?
    }

    var help: String { "Exports all online webcams as JSON for the app bundle." }

    func run(using context: CommandContext, signature: Signature) async throws {
        let models = try await WebcamModel.query(on: context.application.db)
            .filter(\.$isOnline == true)
            .all()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(models.compactMap { $0.toDTO() })
        let path = signature.output ?? "../App/WebcamGlobe/webcams.json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        context.console.print("Exported \(models.count) webcams (\(data.count / 1024) KB) to \(path)")
    }
}
