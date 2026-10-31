import Fluent
import Foundation
import WebcamKit

struct ImportSummary: Equatable, Sendable {
    var created = 0
    var updated = 0
    var skippedDuplicates = 0
    var removed = 0
}

enum ImportService {
    /// Page links closer than this to an existing camera count as the same camera.
    /// Direct feeds are exempt: traffic cameras often stand close together.
    static let duplicateDistance = 50.0

    /// Stores one source's webcams and removes that source's entries that have disappeared.
    /// Hand-added entries are never touched by another source.
    static func store(_ items: [ImportedWebcam], source: WebcamSource, on database: any Database) async throws -> ImportSummary {
        try await database.transaction { db in
            var summary = ImportSummary()
            let existing = try await WebcamModel.query(on: db).all()
            var byURL = Dictionary(existing.map { (urlKey($0.originalURL), $0) }, uniquingKeysWith: { first, _ in first })
            var grid = ProximityGrid()
            existing.forEach { grid.insert(latitude: $0.latitude, longitude: $0.longitude) }
            var seen = Set<UUID>()

            for item in items {
                if let model = byURL[urlKey(item.originalURL)] {
                    if model.source == source.rawValue {
                        model.apply(item)
                        try await model.save(on: db)
                        summary.updated += 1
                        if let id = model.id { seen.insert(id) }
                    } else {
                        summary.skippedDuplicates += 1
                    }
                    continue
                }
                if item.streamType == .webpage,
                   grid.hasNeighbor(latitude: item.latitude, longitude: item.longitude, within: duplicateDistance) {
                    summary.skippedDuplicates += 1
                    continue
                }
                let model = WebcamModel()
                model.source = source.rawValue
                model.apply(item)
                try await model.create(on: db)
                byURL[urlKey(item.originalURL)] = model
                grid.insert(latitude: item.latitude, longitude: item.longitude)
                summary.created += 1
                if let id = model.id { seen.insert(id) }
            }

            // An empty result is more likely a broken feed than every camera vanishing.
            if !items.isEmpty {
                for model in existing where model.source == source.rawValue {
                    if let id = model.id, !seen.contains(id) {
                        try await model.delete(on: db)
                        summary.removed += 1
                    }
                }
            }
            return summary
        }
    }

    /// `http://x/` and `https://x` are treated as the same URL.
    static func urlKey(_ url: String) -> String {
        var key = url.lowercased()
        if let range = key.range(of: "://") { key.removeSubrange(key.startIndex..<range.upperBound) }
        if key.hasPrefix("www.") { key.removeFirst(4) }
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }
}

/// Fast "is anything nearby" lookup on a grid of about 1 km cells.
struct ProximityGrid {
    private struct Cell: Hashable { let x: Int; let y: Int }
    private var cells: [Cell: [(lat: Double, lon: Double)]] = [:]

    private func cell(_ latitude: Double, _ longitude: Double) -> Cell {
        Cell(x: Int((longitude * 100).rounded(.down)), y: Int((latitude * 100).rounded(.down)))
    }

    mutating func insert(latitude: Double, longitude: Double) {
        cells[cell(latitude, longitude), default: []].append((latitude, longitude))
    }

    func hasNeighbor(latitude: Double, longitude: Double, within meters: Double) -> Bool {
        let center = cell(latitude, longitude)
        let metersPerDegree = 111_320.0
        for x in (center.x - 1)...(center.x + 1) {
            for y in (center.y - 1)...(center.y + 1) {
                for point in cells[Cell(x: x, y: y)] ?? [] {
                    let dy = (point.lat - latitude) * metersPerDegree
                    let dx = (point.lon - longitude) * metersPerDegree * cos(latitude * .pi / 180)
                    if (dx * dx + dy * dy).squareRoot() <= meters { return true }
                }
            }
        }
        return false
    }
}

extension WebcamModel {
    func apply(_ item: ImportedWebcam) {
        title = item.title
        latitude = item.latitude
        longitude = item.longitude
        countryCode = item.countryCode
        originalURL = item.originalURL
        // A page link says nothing about the stream, so keep what the probe found out.
        if item.streamType == .webpage, lastChecked != nil { return }
        streamURL = item.streamURL
        streamType = item.streamType.rawValue
        isOnline = item.isOnline
        thumbnailURL = item.thumbnailURL
    }
}
