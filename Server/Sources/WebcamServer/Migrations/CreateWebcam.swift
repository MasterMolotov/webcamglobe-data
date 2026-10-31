import Fluent

struct CreateWebcam: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(WebcamModel.schema)
            .id()
            .field("title", .string, .required)
            .field("latitude", .double, .required)
            .field("longitude", .double, .required)
            .field("country_code", .string)
            .field("source", .string, .required)
            .field("original_url", .string, .required)
            .field("stream_url", .string)
            .field("stream_type", .string, .required)
            .field("is_online", .bool, .required)
            .field("last_checked", .datetime)
            .field("thumbnail_url", .string)
            .unique(on: "original_url")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(WebcamModel.schema).delete()
    }
}
