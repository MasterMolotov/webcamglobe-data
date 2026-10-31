import Fluent
import Vapor
import WebcamKit

extension Webcam: @retroactive Content {}
extension CreateWebcamRequest: @retroactive Content {}

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    let webcams = app.grouped("webcams")

    // GET /webcams?bbox=south,west,north,east&online=true&limit=500
    webcams.get { req async throws -> [Webcam] in
        let query = WebcamModel.query(on: req.db)

        if let raw = req.query[String.self, at: "bbox"] {
            guard let box = BoundingBox(queryValue: raw) else {
                throw Abort(.badRequest, reason: "bbox must be south,west,north,east")
            }
            query.filter(\.$latitude >= box.south).filter(\.$latitude <= box.north)
            if box.crossesAntimeridian {
                query.group(.or) { $0.filter(\.$longitude >= box.west).filter(\.$longitude <= box.east) }
            } else {
                query.filter(\.$longitude >= box.west).filter(\.$longitude <= box.east)
            }
        }
        if req.query[Bool.self, at: "online"] == true {
            query.filter(\.$isOnline == true)
        }

        let limit = min(req.query[Int.self, at: "limit"] ?? 2000, 5000)
        return try await query.limit(limit).all().compactMap { $0.toDTO() }
    }

    webcams.get(":id") { req async throws -> Webcam in
        guard let id = req.parameters.get("id", as: UUID.self),
              let model = try await WebcamModel.find(id, on: req.db),
              let dto = model.toDTO()
        else { throw Abort(.notFound) }
        return dto
    }

    webcams.post { req async throws -> Response in
        let body = try req.content.decode(CreateWebcamRequest.self)
        guard (-90...90).contains(body.latitude), (-180...180).contains(body.longitude) else {
            throw Abort(.badRequest, reason: "Invalid coordinates")
        }
        if try await WebcamModel.query(on: req.db)
            .filter(\.$originalURL == body.originalURL.absoluteString).first() != nil {
            throw Abort(.conflict, reason: "Webcam with this URL already exists")
        }
        let model = WebcamModel(from: body, source: .manual)
        try await model.create(on: req.db)
        guard let dto = model.toDTO() else { throw Abort(.internalServerError) }
        return try await dto.encodeResponse(status: .created, for: req)
    }

    webcams.delete(":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id", as: UUID.self),
              let model = try await WebcamModel.find(id, on: req.db)
        else { throw Abort(.notFound) }
        try await model.delete(on: req.db)
        return .noContent
    }
}
