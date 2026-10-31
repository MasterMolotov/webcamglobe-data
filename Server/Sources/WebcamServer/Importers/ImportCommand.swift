import Vapor
import WebcamKit

/// `swift run WebcamServer import [--source caltrans]`
struct ImportCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "source", help: "caltrans, wikidata, openStreetMap or us511 (default: all)")
        var source: String?
    }

    var help: String { "Imports webcams from the external sources." }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let all: [any WebcamImporter] = [CaltransImporter(), WikidataImporter(), OpenStreetMapImporter(), USStateImporter()]
        let selected = signature.source.map { name in all.filter { $0.source.rawValue == name } } ?? all
        guard !selected.isEmpty else {
            context.console.error("Unknown source: \(signature.source ?? "")")
            return
        }

        // One unreachable source must not stop the others.
        for importer in selected {
            let name = importer.source.rawValue
            do {
                let items = try await importer.fetch(using: app.client)
                let s = try await ImportService.store(items, source: importer.source, on: app.db)
                context.console.print("\(name): \(items.count) found, \(s.created) new, \(s.updated) updated, \(s.skippedDuplicates) duplicates, \(s.removed) removed")
            } catch {
                context.console.error("\(name): failed: \(error)")
            }
        }
    }
}
