import Fluent
import Vapor
import WebcamKit

/// `swift run WebcamServer probe [--source wikidata] [--limit 500] [--max-age-hours 24]`
struct ProbeCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "source", help: "Only check this source")
        var source: String?
        @Option(name: "type", help: "Only check this stream type")
        var type: String?
        @Flag(name: "offline", help: "Only check webcams currently marked offline")
        var offline: Bool
        @Option(name: "limit", help: "Check at most this many webcams")
        var limit: Int?
        @Option(name: "max-age-hours", help: "Skip webcams checked more recently (default: 24)")
        var maxAgeHours: Int?
    }

    var help: String { "Detects stream types and checks which webcams are online." }

    func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let cutoff = Date().addingTimeInterval(-Double(signature.maxAgeHours ?? 24) * 3600)
        let query = WebcamModel.query(on: app.db)
            .group(.or) { $0.filter(\.$lastChecked == nil).filter(\.$lastChecked < cutoff) }
        if let source = signature.source { query.filter(\.$source == source) }
        if let type = signature.type { query.filter(\.$streamType == type) }
        if signature.offline { query.filter(\.$isOnline == false) }
        var webcams = try await query.all().shuffled()
        if let limit = signature.limit { webcams = Array(webcams.prefix(limit)) }

        context.console.print("Checking \(webcams.count) webcams…")
        let summary = try await ProbeService.run(webcams, app: app)
        context.console.print("Checked \(summary.checked), online \(summary.online)")
        for (type, count) in summary.byType.sorted(by: { $0.value > $1.value }) {
            context.console.print("  \(type.rawValue): \(count)")
        }
    }
}
