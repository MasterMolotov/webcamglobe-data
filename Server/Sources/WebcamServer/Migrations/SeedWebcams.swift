import Fluent
import Foundation
import WebcamKit

/// Inserts the hand-picked starter webcams from `Resources/seed.json` once.
struct SeedWebcams: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let url = Bundle.module.url(forResource: "seed", withExtension: "json") else { return }
        let entries = try JSONDecoder().decode([CreateWebcamRequest].self, from: Data(contentsOf: url))
        for entry in entries {
            try await WebcamModel(from: entry, source: .manual).create(on: database)
        }
    }

    func revert(on database: any Database) async throws {
        try await WebcamModel.query(on: database).filter(\.$source == WebcamSource.manual.rawValue).delete()
    }
}
