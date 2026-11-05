import Fluent
import Foundation
import Vapor
import WebcamKit

/// `swift run WebcamServer discover` searches YouTube for live cameras and adds new ones.
/// Needs `YOUTUBE_API_KEY`. A search costs 100 of the 10,000 free quota units per day.
struct DiscoverCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Option(name: "set", help: "general (default), traffic or animals")
        var set: String?

        @Option(name: "batch", help: "Only this many searches, continuing where yesterday's run stopped")
        var batch: Int?
    }

    var help: String { "Finds live webcams on YouTube." }

    func run(using context: CommandContext, signature: Signature) async throws {
        guard let key = Environment.get("YOUTUBE_API_KEY") else {
            context.console.error("YOUTUBE_API_KEY is missing")
            return
        }
        let app = context.application
        var known = Set(try await WebcamModel.query(on: app.db).all().map { ImportService.urlKey($0.originalURL) })
        var created = 0, searches = 0

        let all = switch signature.set {
        case "traffic": YouTubeDiscovery.trafficSearches
        case "animals": YouTubeDiscovery.animalSearches
        default: YouTubeDiscovery.searches
        }
        let day = Int(Date().timeIntervalSince1970 / 86400)
        let plan = signature.batch.map { YouTubeDiscovery.slice(all, size: $0, day: day) } ?? all
        for search in plan {
            // Most likely the daily quota; everything found so far stays.
            guard let found = try? await YouTubeDiscovery.search(search, key: key, client: app.client) else {
                context.console.error("Stopped after \(searches) searches")
                break
            }
            searches += 1
            for cam in found where known.insert(ImportService.urlKey(cam.originalURL)).inserted {
                let model = WebcamModel()
                model.source = WebcamSource.youtube.rawValue
                model.apply(cam)
                model.lastChecked = Date()
                try await model.create(on: app.db)
                created += 1
            }
        }
        context.console.print("\(searches) searches, \(created) new YouTube cameras")
    }
}

enum YouTubeDiscovery {
    struct City: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
        /// Searching in the local language finds cameras whose titles never use English.
        var phrase = "live cam"
    }

    struct Search: Sendable {
        let query: String
        /// Set for a search about one city; its results must name that city.
        var city: City? = nil
        /// Places looked for in the titles before the cities, like the national parks and zoos of animal cameras.
        var places: [City] = []
    }

    static let searches: [Search] = (cities + countries).map { Search(query: "\($0.name) \($0.phrase)", city: $0) } + [
        "EarthCam live", "explore.org live cam", "harbor live webcam", "airport live webcam",
        "volcano live webcam", "beach live webcam", "ski resort live webcam", "Webcam live Deutschland",
        "volcano observatory live", "wildlife live cam", "zoo live cam", "aquarium live cam", "bird nest live cam",
        "eagle cam live", "railway live webcam", "port live cam ships", "mountain live webcam", "lake live webcam",
        "northern lights live cam", "Antarctica live cam", "safari live cam", "waterfall live cam",
        "lighthouse live cam", "surf cam live", "national park live cam",
    ].map { Search(query: $0) } + animalSearches

    /// A daily run takes the next `size` searches, so the whole plan is covered over a few days.
    static func slice(_ all: [Search], size: Int, day: Int) -> [Search] {
        guard !all.isEmpty, size > 0 else { return [] }
        let start = day * size % all.count
        return (0..<min(size, all.count)).map { all[(start + $0) % all.count] }
    }

    /// Nests, feeders, waterholes, zoos and aquariums. Their titles seldom name a city, so famous
    /// places of animal cameras are known by name; cameras without any known place are still left out.
    static let animalSearches: [Search] = [
        "bald eagle nest cam live", "eagle nest live cam", "osprey nest cam live", "peregrine falcon nest cam live",
        "kestrel nest cam live", "owl box cam live", "barn owl live cam", "stork nest live cam", "Storchennest live",
        "Adlerhorst live", "Seeadler live cam", "Fischadler live", "Turmfalken live", "Uhu live cam", "heron nest cam live",
        "swan nest cam live", "puffin cam live", "albatross cam live", "penguin cam live", "bird feeder cam live",
        "FeederWatch cam", "Vogelhaus live cam", "hummingbird feeder live cam", "brown bear cam live", "polar bear cam live",
        "africam live", "waterhole live cam", "safari live cam Africa", "elephant live cam", "giraffe cam live",
        "panda cam live", "gorilla cam live", "koala cam live", "otter cam live", "sea lion cam live", "seal cam live",
        "aquarium live cam", "underwater reef cam live", "shark cam live", "jellyfish cam live", "Tierpark live cam",
        "zoo live webcam", "wildlife camera live stream", "fox den cam live", "badger cam live",
    ].map { Search(query: $0, places: animalPlaces) }

    static let animalPlaces: [City] = [
        City(name: "Brooks Falls", latitude: 58.554, longitude: -155.779),
        City(name: "Katmai", latitude: 58.554, longitude: -155.779),
        City(name: "Anan Bear", latitude: 56.18, longitude: -131.88),
        City(name: "Churchill", latitude: 58.77, longitude: -94.17),
        City(name: "Decorah", latitude: 43.30, longitude: -91.79),
        City(name: "Big Bear", latitude: 34.24, longitude: -116.91),
        City(name: "Berry College", latitude: 34.29, longitude: -85.19),
        City(name: "Southwest Florida Eagle", latitude: 26.71, longitude: -81.79),
        City(name: "Fort Myers", latitude: 26.64, longitude: -81.87),
        City(name: "Captiva", latitude: 26.52, longitude: -82.19),
        City(name: "Channel Islands", latitude: 34.0, longitude: -119.7),
        City(name: "Dulles Greenway", latitude: 39.0, longitude: -77.5),
        City(name: "Hog Island", latitude: 43.98, longitude: -69.42),
        City(name: "Charlo", latitude: 47.44, longitude: -114.17),
        City(name: "Sapsucker Woods", latitude: 42.48, longitude: -76.45),
        City(name: "Ontario FeederWatch", latitude: 49.13, longitude: -85.84),
        City(name: "Yellowstone", latitude: 44.6, longitude: -110.5),
        City(name: "Smithsonian", latitude: 38.930, longitude: -77.050),
        City(name: "San Diego Zoo", latitude: 32.735, longitude: -117.149),
        City(name: "Pittsburgh Zoo", latitude: 40.484, longitude: -79.919),
        City(name: "Houston Zoo", latitude: 29.714, longitude: -95.390),
        City(name: "Monterey Bay Aquarium", latitude: 36.618, longitude: -121.902),
        City(name: "Georgia Aquarium", latitude: 33.763, longitude: -84.395),
        City(name: "Vancouver Aquarium", latitude: 49.300, longitude: -123.131),
        City(name: "Seattle Aquarium", latitude: 47.607, longitude: -122.343),
        City(name: "Royal Albatross", latitude: -45.77, longitude: 170.73),
        City(name: "Taiaroa", latitude: -45.77, longitude: 170.73),
        City(name: "Port Lincoln", latitude: -34.72, longitude: 135.86),
        City(name: "Tembe", latitude: -27.05, longitude: 32.42),
        City(name: "Olifants", latitude: -24.05, longitude: 31.73),
        City(name: "Djuma", latitude: -24.80, longitude: 31.55),
        City(name: "Kruger", latitude: -24.0, longitude: 31.5),
        City(name: "Etosha", latitude: -18.85, longitude: 16.33),
        City(name: "Okavango", latitude: -19.3, longitude: 22.9),
        City(name: "Mpala", latitude: 0.29, longitude: 36.90),
        City(name: "Masai Mara", latitude: -1.5, longitude: 35.15),
        City(name: "Serengeti", latitude: -2.33, longitude: 34.83),
        City(name: "Galapagos", latitude: -0.75, longitude: -90.31),
        City(name: "Wolong", latitude: 31.03, longitude: 103.20),
        City(name: "Farne Islands", latitude: 55.63, longitude: -1.63),
        City(name: "Skomer", latitude: 51.74, longitude: -5.30),
        City(name: "Loch Garten", latitude: 57.24, longitude: -3.69),
        City(name: "Dyfi", latitude: 52.57, longitude: -3.92),
        City(name: "Rutland Water", latitude: 52.65, longitude: -0.63),
        City(name: "Ouwehands", latitude: 51.96, longitude: 5.58),
        City(name: "Zoo Berlin", latitude: 52.508, longitude: 13.338),
        City(name: "Tierpark Berlin", latitude: 52.500, longitude: 13.531),
        City(name: "Svalbard", latitude: 78.22, longitude: 15.65),
        City(name: "Little Miami", latitude: 39.40, longitude: -84.20),
        City(name: "Port Washington", latitude: 43.39, longitude: -87.87),
        City(name: "Mendenhall", latitude: 58.42, longitude: -134.55),
        City(name: "Campi ya Kanzi", latitude: -2.85, longitude: 37.85),
        City(name: "Kilimanjaro", latitude: -3.07, longitude: 37.35),
        City(name: "Wapusk", latitude: 58.77, longitude: -94.17),
        City(name: "Naknek", latitude: 58.68, longitude: -156.65),
        City(name: "Canopy Tower", latitude: 9.08, longitude: -79.65),
        City(name: "Canopy Lodge", latitude: 8.61, longitude: -80.13),
        City(name: "Lola ya Bonobo", latitude: -4.43, longitude: 15.25),
    ]

    static let trafficSearches: [Search] = cities.map { Search(query: "\($0.name) traffic camera live", city: $0) }

    static func search(_ search: Search, key: String, client: any Client) async throws -> [ImportedWebcam] {
        let query = search.query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let searchURL = "https://www.googleapis.com/youtube/v3/search?part=id&type=video&eventType=live&maxResults=50&q=\(query)&key=\(key)"
        let ids = try await JSONDecoder().decode(SearchResponse.self, from: body(of: searchURL, client: client))
            .items.compactMap(\.id.videoId)
        guard !ids.isEmpty else { return [] }
        let videosURL = "https://www.googleapis.com/youtube/v3/videos?part=snippet,status,recordingDetails&id=\(ids.joined(separator: ","))&key=\(key)"
        return try await parseVideos(body(of: videosURL, client: client), city: search.city, places: search.places)
    }

    private static func body(of url: String, client: any Client) async throws -> Data {
        let response = try await client.get(URI(string: url), headers: ImportHTTP.headers)
        // The key is part of the URL, so it must not end up in an error message.
        guard response.status == .ok, let buffer = response.body else {
            throw ImportError.badResponse(url: "googleapis.com", status: response.status.code)
        }
        return Data(buffer.readableBytesView)
    }

    static func parseVideos(_ data: Data, city: City?, places: [City] = []) throws -> [ImportedWebcam] {
        try JSONDecoder().decode(VideosResponse.self, from: data).items.compactMap { video in
            guard video.snippet.liveBroadcastContent == "live", video.status.embeddable != false,
                  looksLikeCamera(video.snippet.title) else { return nil }
            let title = video.snippet.title
            let place = places.first { names(title, $0.name) } ?? placeInTitle(title)
            let position: (Double, Double, Bool)
            if let exact = video.recordingDetails?.location, let lat = exact.latitude, let lon = exact.longitude {
                position = (lat, lon, false)
            } else if let named = place ?? city.flatMap({ names(title, $0.name) ? $0 : nil }) {
                position = (named.latitude, named.longitude, true)
            } else {
                return nil
            }
            // Cameras placed by city name would sit on one point, which a cluster can never split.
            let offset = position.2 ? spread(for: video.id) : (0, 0)
            return ImportedWebcam(
                title: video.snippet.title,
                latitude: position.0 + offset.0,
                longitude: position.1 + offset.1,
                originalURL: "https://www.youtube.com/watch?v=\(video.id)",
                streamURL: "https://www.youtube-nocookie.com/embed/\(video.id)",
                streamType: .youtube
            )
        }
    }

    static func looksLikeCamera(_ title: String) -> Bool {
        let lower = title.lowercased()
        guard ["cam", "live view", "livestream view", "kamera"].contains(where: lower.contains) else { return false }
        let excluded = [
            "music", "lofi", "lo-fi", "radio", "gaming", "gameplay", "news", "sermon", "church service", "mass ",
            "trading", "bitcoin", "crypto", "podcast", "camp ", "cambodia", "cameroon", "camera roll", "asmr",
            "slot", "casino", "chat", "nachrichten",
        ]
        return !excluded.contains(where: lower.contains)
    }

    static func placeInTitle(_ title: String) -> City? {
        cities.first { names(title, $0.name) }
    }

    /// Whether the title names the place as a word of its own: "Rome" is not in "Promenade", "Lima" not in
    /// "Kilimanjaro", "Goa" not in "Goat". A capital starts a new word ("WebcamSydney"), and scripts without
    /// spaces, like Japanese, are matched anywhere.
    static func names(_ title: String, _ place: String) -> Bool {
        var search = title.startIndex..<title.endIndex
        while let range = title.range(of: place, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
            func isLatinLetter(_ c: Character) -> Bool { c.isLetter && c.unicodeScalars.allSatisfy { $0.value < 0x250 } }
            let before = range.lowerBound > title.startIndex ? title[title.index(before: range.lowerBound)] : nil
            let after = range.upperBound < title.endIndex ? title[range.upperBound] : nil
            let first = title[range.lowerBound]
            let startsWord = before.map { !isLatinLetter($0) || ($0.isLowercase && first.isUppercase) } ?? true
            let endsWord = after.map { !(isLatinLetter($0) && $0.isLowercase) } ?? true
            if startsWord && endsWord { return true }
            search = range.upperBound..<title.endIndex
        }
        return false
    }

    /// Same video, same small offset of up to about 2 km, so a camera doesn't jump between runs.
    static func spread(for id: String) -> (Double, Double) {
        let bytes = Array(id.utf8)
        func part(_ step: Int) -> Double {
            let sum = bytes.enumerated().reduce(0) { $0 + Int($1.element) * ($1.offset + step) }
            return Double(sum % 41 - 20) / 1000
        }
        return (part(1), part(3))
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            let id: ID
        }
        let items: [Item]
    }

    private struct VideosResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                let title: String
                let liveBroadcastContent: String
            }
            struct Status: Decodable { let embeddable: Bool? }
            struct Recording: Decodable { let location: Location? }
            struct Location: Decodable {
                let latitude: Double?
                let longitude: Double?
            }
            let id: String
            let snippet: Snippet
            let status: Status
            let recordingDetails: Recording?
        }
        let items: [Item]
    }

    /// Every country once, so none is left out. Only their own search uses them: names like Panama or Niger
    /// also appear in other places' titles.
    static let countries: [City] = [
        City(name: "Afghanistan", latitude: 34.53, longitude: 69.17),
        City(name: "Albania", latitude: 41.33, longitude: 19.82),
        City(name: "Algeria", latitude: 36.75, longitude: 3.06),
        City(name: "Andorra", latitude: 42.51, longitude: 1.52),
        City(name: "Angola", latitude: -8.84, longitude: 13.23),
        City(name: "Antigua", latitude: 17.12, longitude: -61.85),
        City(name: "Argentina", latitude: -34.6, longitude: -58.38),
        City(name: "Armenia", latitude: 40.18, longitude: 44.51),
        City(name: "Australia", latitude: -35.28, longitude: 149.13),
        City(name: "Austria", latitude: 48.21, longitude: 16.37),
        City(name: "Azerbaijan", latitude: 40.41, longitude: 49.87),
        City(name: "Bahamas", latitude: 25.05, longitude: -77.35),
        City(name: "Bahrain", latitude: 26.23, longitude: 50.59),
        City(name: "Bangladesh", latitude: 23.81, longitude: 90.41),
        City(name: "Belarus", latitude: 53.9, longitude: 27.57),
        City(name: "Belgium", latitude: 50.85, longitude: 4.35),
        City(name: "Belize", latitude: 17.25, longitude: -88.77),
        City(name: "Benin", latitude: 6.5, longitude: 2.6),
        City(name: "Bermuda", latitude: 32.29, longitude: -64.78),
        City(name: "Bhutan", latitude: 27.47, longitude: 89.64),
        City(name: "Bolivia", latitude: -16.5, longitude: -68.15),
        City(name: "Bosnia", latitude: 43.86, longitude: 18.41),
        City(name: "Botswana", latitude: -24.65, longitude: 25.91),
        City(name: "Brazil", latitude: -15.79, longitude: -47.88),
        City(name: "Brunei", latitude: 4.9, longitude: 114.94),
        City(name: "Bulgaria", latitude: 42.7, longitude: 23.32),
        City(name: "Burkina Faso", latitude: 12.37, longitude: -1.52),
        City(name: "Burundi", latitude: -3.38, longitude: 29.36),
        City(name: "Cambodia", latitude: 11.56, longitude: 104.92),
        City(name: "Cameroon", latitude: 3.85, longitude: 11.5),
        City(name: "Canada", latitude: 45.42, longitude: -75.7),
        City(name: "Cape Verde", latitude: 14.93, longitude: -23.51),
        City(name: "Cayman Islands", latitude: 19.29, longitude: -81.37),
        City(name: "Chile", latitude: -33.45, longitude: -70.67),
        City(name: "China", latitude: 39.9, longitude: 116.41),
        City(name: "Colombia", latitude: 4.71, longitude: -74.07),
        City(name: "Comoros", latitude: -11.7, longitude: 43.26),
        City(name: "Congo", latitude: -4.27, longitude: 15.28),
        City(name: "Cook Islands", latitude: -21.21, longitude: -159.78),
        City(name: "Croatia", latitude: 45.81, longitude: 15.98),
        City(name: "Cuba", latitude: 23.11, longitude: -82.37),
        City(name: "Curacao", latitude: 12.12, longitude: -68.93),
        City(name: "Czech Republic", latitude: 50.08, longitude: 14.44),
        City(name: "Denmark", latitude: 55.68, longitude: 12.57),
        City(name: "Djibouti", latitude: 11.59, longitude: 43.15),
        City(name: "Dominica", latitude: 15.3, longitude: -61.39),
        City(name: "Dominican Republic", latitude: 18.49, longitude: -69.93),
        City(name: "Ecuador", latitude: -0.18, longitude: -78.47),
        City(name: "Egypt", latitude: 30.04, longitude: 31.24),
        City(name: "El Salvador", latitude: 13.69, longitude: -89.22),
        City(name: "Estonia", latitude: 59.44, longitude: 24.75),
        City(name: "Eswatini", latitude: -26.31, longitude: 31.14),
        City(name: "Ethiopia", latitude: 9.03, longitude: 38.74),
        City(name: "Fiji", latitude: -18.14, longitude: 178.44),
        City(name: "Finland", latitude: 60.17, longitude: 24.94),
        City(name: "France", latitude: 48.86, longitude: 2.35),
        City(name: "French Polynesia", latitude: -17.54, longitude: -149.57),
        City(name: "Gabon", latitude: 0.42, longitude: 9.47),
        City(name: "Gambia", latitude: 13.45, longitude: -16.58),
        City(name: "Germany", latitude: 52.52, longitude: 13.41),
        City(name: "Ghana", latitude: 5.6, longitude: -0.19),
        City(name: "Gibraltar", latitude: 36.14, longitude: -5.35),
        City(name: "Greece", latitude: 37.98, longitude: 23.73),
        City(name: "Greenland", latitude: 64.18, longitude: -51.72),
        City(name: "Grenada", latitude: 12.05, longitude: -61.75),
        City(name: "Guadeloupe", latitude: 16.24, longitude: -61.53),
        City(name: "Guatemala", latitude: 14.63, longitude: -90.51),
        City(name: "Guinea", latitude: 9.64, longitude: -13.58),
        City(name: "Guyana", latitude: 6.8, longitude: -58.16),
        City(name: "Haiti", latitude: 18.59, longitude: -72.31),
        City(name: "Honduras", latitude: 14.07, longitude: -87.19),
        City(name: "Hungary", latitude: 47.5, longitude: 19.04),
        City(name: "Iceland", latitude: 64.15, longitude: -21.94),
        City(name: "India", latitude: 28.61, longitude: 77.21),
        City(name: "Indonesia", latitude: -6.21, longitude: 106.85),
        City(name: "Iran", latitude: 35.69, longitude: 51.39),
        City(name: "Iraq", latitude: 33.31, longitude: 44.36),
        City(name: "Ireland", latitude: 53.35, longitude: -6.26),
        City(name: "Isle of Man", latitude: 54.15, longitude: -4.48),
        City(name: "Israel", latitude: 31.77, longitude: 35.21),
        City(name: "Italy", latitude: 41.9, longitude: 12.5),
        City(name: "Ivory Coast", latitude: 5.36, longitude: -4.01),
        City(name: "Japan", latitude: 35.68, longitude: 139.65),
        City(name: "Kazakhstan", latitude: 51.17, longitude: 71.45),
        City(name: "Kenya", latitude: -1.29, longitude: 36.82),
        City(name: "Kiribati", latitude: 1.33, longitude: 172.98),
        City(name: "Kosovo", latitude: 42.66, longitude: 21.17),
        City(name: "Kuwait", latitude: 29.38, longitude: 47.99),
        City(name: "Kyrgyzstan", latitude: 42.87, longitude: 74.59),
        City(name: "Laos", latitude: 17.98, longitude: 102.63),
        City(name: "Latvia", latitude: 56.95, longitude: 24.11),
        City(name: "Lebanon", latitude: 33.89, longitude: 35.5),
        City(name: "Lesotho", latitude: -29.31, longitude: 27.48),
        City(name: "Liberia", latitude: 6.3, longitude: -10.8),
        City(name: "Libya", latitude: 32.89, longitude: 13.19),
        City(name: "Liechtenstein", latitude: 47.14, longitude: 9.52),
        City(name: "Lithuania", latitude: 54.69, longitude: 25.28),
        City(name: "Luxembourg", latitude: 49.61, longitude: 6.13),
        City(name: "Madagascar", latitude: -18.88, longitude: 47.51),
        City(name: "Malawi", latitude: -13.96, longitude: 33.79),
        City(name: "Malaysia", latitude: 3.14, longitude: 101.69),
        City(name: "Maldives", latitude: 4.18, longitude: 73.51),
        City(name: "Mali", latitude: 12.64, longitude: -8.0),
        City(name: "Malta", latitude: 35.9, longitude: 14.51),
        City(name: "Martinique", latitude: 14.62, longitude: -61.06),
        City(name: "Mauritania", latitude: 18.08, longitude: -15.98),
        City(name: "Mauritius", latitude: -20.16, longitude: 57.5),
        City(name: "Mexico", latitude: 19.43, longitude: -99.13),
        City(name: "Moldova", latitude: 47.01, longitude: 28.86),
        City(name: "Monaco", latitude: 43.74, longitude: 7.42),
        City(name: "Mongolia", latitude: 47.89, longitude: 106.91),
        City(name: "Montenegro", latitude: 42.44, longitude: 19.26),
        City(name: "Morocco", latitude: 34.02, longitude: -6.84),
        City(name: "Mozambique", latitude: -25.97, longitude: 32.57),
        City(name: "Myanmar", latitude: 16.87, longitude: 96.2),
        City(name: "Namibia", latitude: -22.56, longitude: 17.08),
        City(name: "Nepal", latitude: 27.72, longitude: 85.32),
        City(name: "Netherlands", latitude: 52.37, longitude: 4.9),
        City(name: "New Caledonia", latitude: -22.28, longitude: 166.46),
        City(name: "New Zealand", latitude: -41.29, longitude: 174.78),
        City(name: "Nicaragua", latitude: 12.11, longitude: -86.24),
        City(name: "Niger", latitude: 13.51, longitude: 2.13),
        City(name: "Nigeria", latitude: 9.08, longitude: 7.4),
        City(name: "North Macedonia", latitude: 42.0, longitude: 21.43),
        City(name: "Norway", latitude: 59.91, longitude: 10.75),
        City(name: "Oman", latitude: 23.59, longitude: 58.41),
        City(name: "Pakistan", latitude: 33.68, longitude: 73.05),
        City(name: "Palau", latitude: 7.5, longitude: 134.62),
        City(name: "Panama", latitude: 8.98, longitude: -79.52),
        City(name: "Papua New Guinea", latitude: -9.44, longitude: 147.18),
        City(name: "Paraguay", latitude: -25.26, longitude: -57.58),
        City(name: "Peru", latitude: -12.05, longitude: -77.04),
        City(name: "Philippines", latitude: 14.6, longitude: 120.98),
        City(name: "Poland", latitude: 52.23, longitude: 21.01),
        City(name: "Portugal", latitude: 38.72, longitude: -9.14),
        City(name: "Puerto Rico", latitude: 18.47, longitude: -66.11),
        City(name: "Qatar", latitude: 25.29, longitude: 51.53),
        City(name: "Reunion", latitude: -20.88, longitude: 55.45),
        City(name: "Romania", latitude: 44.43, longitude: 26.1),
        City(name: "Russia", latitude: 55.76, longitude: 37.62),
        City(name: "Rwanda", latitude: -1.95, longitude: 30.06),
        City(name: "Saint Lucia", latitude: 14.01, longitude: -60.99),
        City(name: "Samoa", latitude: -13.83, longitude: -171.76),
        City(name: "San Marino", latitude: 43.94, longitude: 12.45),
        City(name: "Saudi Arabia", latitude: 24.71, longitude: 46.68),
        City(name: "Senegal", latitude: 14.72, longitude: -17.47),
        City(name: "Serbia", latitude: 44.79, longitude: 20.45),
        City(name: "Seychelles", latitude: -4.62, longitude: 55.45),
        City(name: "Sierra Leone", latitude: 8.47, longitude: -13.23),
        City(name: "Singapore", latitude: 1.35, longitude: 103.82),
        City(name: "Slovakia", latitude: 48.15, longitude: 17.11),
        City(name: "Slovenia", latitude: 46.06, longitude: 14.51),
        City(name: "Solomon Islands", latitude: -9.43, longitude: 159.95),
        City(name: "Somalia", latitude: 2.05, longitude: 45.32),
        City(name: "South Africa", latitude: -25.75, longitude: 28.19),
        City(name: "South Korea", latitude: 37.57, longitude: 126.98),
        City(name: "Spain", latitude: 40.42, longitude: -3.7),
        City(name: "Sri Lanka", latitude: 6.93, longitude: 79.86),
        City(name: "Sudan", latitude: 15.5, longitude: 32.56),
        City(name: "Suriname", latitude: 5.85, longitude: -55.2),
        City(name: "Sweden", latitude: 59.33, longitude: 18.07),
        City(name: "Switzerland", latitude: 46.95, longitude: 7.45),
        City(name: "Taiwan", latitude: 25.03, longitude: 121.57),
        City(name: "Tajikistan", latitude: 38.56, longitude: 68.79),
        City(name: "Tanzania", latitude: -6.79, longitude: 39.21),
        City(name: "Thailand", latitude: 13.76, longitude: 100.5),
        City(name: "Togo", latitude: 6.13, longitude: 1.22),
        City(name: "Tonga", latitude: -21.14, longitude: -175.2),
        City(name: "Trinidad", latitude: 10.65, longitude: -61.51),
        City(name: "Tunisia", latitude: 36.81, longitude: 10.18),
        City(name: "Turkey", latitude: 39.93, longitude: 32.86),
        City(name: "Turkmenistan", latitude: 37.96, longitude: 58.33),
        City(name: "Turks and Caicos", latitude: 21.69, longitude: -71.8),
        City(name: "Uganda", latitude: 0.35, longitude: 32.58),
        City(name: "Ukraine", latitude: 50.45, longitude: 30.52),
        City(name: "United Arab Emirates", latitude: 24.45, longitude: 54.38),
        City(name: "United Kingdom", latitude: 51.51, longitude: -0.13),
        City(name: "United States", latitude: 38.9, longitude: -77.04),
        City(name: "Uruguay", latitude: -34.9, longitude: -56.16),
        City(name: "Uzbekistan", latitude: 41.3, longitude: 69.24),
        City(name: "Vanuatu", latitude: -17.73, longitude: 168.32),
        City(name: "Venezuela", latitude: 10.48, longitude: -66.9),
        City(name: "Vietnam", latitude: 21.03, longitude: 105.85),
        City(name: "Virgin Islands", latitude: 18.34, longitude: -64.93),
        City(name: "Yemen", latitude: 15.37, longitude: 44.19),
        City(name: "Zambia", latitude: -15.39, longitude: 28.32),
        City(name: "Zimbabwe", latitude: -17.83, longitude: 31.05),
    ]

    static let cities: [City] = [
        City(name: "Berlin", latitude: 52.52, longitude: 13.405), City(name: "Hamburg", latitude: 53.55, longitude: 9.99),
        City(name: "München", latitude: 48.137, longitude: 11.575), City(name: "Köln", latitude: 50.938, longitude: 6.96),
        City(name: "Frankfurt", latitude: 50.11, longitude: 8.68), City(name: "Dresden", latitude: 51.05, longitude: 13.74),
        City(name: "Wien", latitude: 48.208, longitude: 16.373), City(name: "Zürich", latitude: 47.377, longitude: 8.54),
        City(name: "London", latitude: 51.507, longitude: -0.128), City(name: "Paris", latitude: 48.857, longitude: 2.352),
        City(name: "Amsterdam", latitude: 52.37, longitude: 4.895), City(name: "Brussels", latitude: 50.85, longitude: 4.35),
        City(name: "Madrid", latitude: 40.417, longitude: -3.703), City(name: "Barcelona", latitude: 41.385, longitude: 2.173),
        City(name: "Lisbon", latitude: 38.722, longitude: -9.139), City(name: "Rome", latitude: 41.903, longitude: 12.496),
        City(name: "Venice", latitude: 45.44, longitude: 12.316), City(name: "Naples", latitude: 40.852, longitude: 14.268),
        City(name: "Athens", latitude: 37.984, longitude: 23.728), City(name: "Istanbul", latitude: 41.008, longitude: 28.978),
        City(name: "Prague", latitude: 50.075, longitude: 14.437), City(name: "Budapest", latitude: 47.498, longitude: 19.04),
        City(name: "Warsaw", latitude: 52.23, longitude: 21.012), City(name: "Stockholm", latitude: 59.329, longitude: 18.069),
        City(name: "Oslo", latitude: 59.914, longitude: 10.752), City(name: "Copenhagen", latitude: 55.676, longitude: 12.568),
        City(name: "Helsinki", latitude: 60.17, longitude: 24.938), City(name: "Reykjavik", latitude: 64.147, longitude: -21.942),
        City(name: "Dublin", latitude: 53.35, longitude: -6.26), City(name: "Edinburgh", latitude: 55.953, longitude: -3.188),
        City(name: "New York", latitude: 40.758, longitude: -73.985), City(name: "Las Vegas", latitude: 36.115, longitude: -115.173),
        City(name: "Miami", latitude: 25.79, longitude: -80.13), City(name: "Chicago", latitude: 41.878, longitude: -87.63),
        City(name: "Los Angeles", latitude: 34.052, longitude: -118.244), City(name: "San Francisco", latitude: 37.775, longitude: -122.419),
        City(name: "Seattle", latitude: 47.606, longitude: -122.332), City(name: "New Orleans", latitude: 29.958, longitude: -90.065),
        City(name: "Honolulu", latitude: 21.307, longitude: -157.858), City(name: "Toronto", latitude: 43.653, longitude: -79.383),
        City(name: "Vancouver", latitude: 49.283, longitude: -123.121), City(name: "Montreal", latitude: 45.502, longitude: -73.567),
        City(name: "Mexico City", latitude: 19.433, longitude: -99.133), City(name: "Cancun", latitude: 21.161, longitude: -86.851),
        City(name: "Havana", latitude: 23.114, longitude: -82.367), City(name: "Rio de Janeiro", latitude: -22.907, longitude: -43.173),
        City(name: "Sao Paulo", latitude: -23.551, longitude: -46.633), City(name: "Buenos Aires", latitude: -34.604, longitude: -58.382),
        City(name: "Santiago", latitude: -33.449, longitude: -70.669), City(name: "Lima", latitude: -12.046, longitude: -77.043),
        City(name: "Bogota", latitude: 4.711, longitude: -74.072), City(name: "Tokyo", latitude: 35.676, longitude: 139.65),
        City(name: "Osaka", latitude: 34.694, longitude: 135.502), City(name: "Kyoto", latitude: 35.012, longitude: 135.768),
        City(name: "Seoul", latitude: 37.567, longitude: 126.978), City(name: "Beijing", latitude: 39.904, longitude: 116.407),
        City(name: "Shanghai", latitude: 31.23, longitude: 121.474), City(name: "Hong Kong", latitude: 22.319, longitude: 114.169),
        City(name: "Taipei", latitude: 25.033, longitude: 121.565), City(name: "Bangkok", latitude: 13.756, longitude: 100.502),
        City(name: "Singapore", latitude: 1.352, longitude: 103.82), City(name: "Bali", latitude: -8.409, longitude: 115.189),
        City(name: "Manila", latitude: 14.6, longitude: 120.984), City(name: "Mumbai", latitude: 19.076, longitude: 72.878),
        City(name: "Delhi", latitude: 28.614, longitude: 77.209), City(name: "Dubai", latitude: 25.205, longitude: 55.271),
        City(name: "Jerusalem", latitude: 31.778, longitude: 35.235), City(name: "Mecca", latitude: 21.423, longitude: 39.826),
        City(name: "Cairo", latitude: 30.044, longitude: 31.236), City(name: "Cape Town", latitude: -33.925, longitude: 18.424),
        City(name: "Johannesburg", latitude: -26.204, longitude: 28.047), City(name: "Nairobi", latitude: -1.292, longitude: 36.822),
        City(name: "Sydney", latitude: -33.869, longitude: 151.209), City(name: "Melbourne", latitude: -37.814, longitude: 144.963),
        City(name: "Auckland", latitude: -36.849, longitude: 174.763),
        // Further places, so the whole world is covered and not only the big cities.
        City(name: "Lucerne", latitude: 47.05, longitude: 8.31), City(name: "Interlaken", latitude: 46.686, longitude: 7.863),
        City(name: "Zermatt", latitude: 46.02, longitude: 7.75), City(name: "Innsbruck", latitude: 47.27, longitude: 11.39),
        City(name: "Salzburg", latitude: 47.81, longitude: 13.05), City(name: "Hallstatt", latitude: 47.56, longitude: 13.65),
        City(name: "Nice", latitude: 43.70, longitude: 7.27), City(name: "Marseille", latitude: 43.30, longitude: 5.37),
        City(name: "Monaco", latitude: 43.74, longitude: 7.42), City(name: "Lyon", latitude: 45.76, longitude: 4.84),
        City(name: "Seville", latitude: 37.39, longitude: -5.98), City(name: "Valencia", latitude: 39.47, longitude: -0.38),
        City(name: "Malaga", latitude: 36.72, longitude: -4.42), City(name: "Mallorca", latitude: 39.57, longitude: 2.65),
        City(name: "Tenerife", latitude: 28.29, longitude: -16.63), City(name: "Gran Canaria", latitude: 27.92, longitude: -15.55),
        City(name: "Porto", latitude: 41.15, longitude: -8.61), City(name: "Madeira", latitude: 32.65, longitude: -16.91),
        City(name: "Milan", latitude: 45.46, longitude: 9.19), City(name: "Florence", latitude: 43.77, longitude: 11.26),
        City(name: "Lake Como", latitude: 45.99, longitude: 9.26), City(name: "Amalfi", latitude: 40.63, longitude: 14.60),
        City(name: "Sicily", latitude: 37.6, longitude: 14.0), City(name: "Malta", latitude: 35.90, longitude: 14.51),
        City(name: "Dubrovnik", latitude: 42.65, longitude: 18.09), City(name: "Split", latitude: 43.51, longitude: 16.44),
        City(name: "Santorini", latitude: 36.39, longitude: 25.46), City(name: "Mykonos", latitude: 37.45, longitude: 25.33),
        City(name: "Crete", latitude: 35.24, longitude: 24.8), City(name: "Cyprus", latitude: 35.1, longitude: 33.4),
        City(name: "Antalya", latitude: 36.89, longitude: 30.71), City(name: "Bucharest", latitude: 44.43, longitude: 26.10),
        City(name: "Sofia", latitude: 42.70, longitude: 23.32), City(name: "Belgrade", latitude: 44.79, longitude: 20.45),
        City(name: "Zagreb", latitude: 45.81, longitude: 15.98), City(name: "Ljubljana", latitude: 46.06, longitude: 14.51),
        City(name: "Bratislava", latitude: 48.15, longitude: 17.11), City(name: "Krakow", latitude: 50.06, longitude: 19.94),
        City(name: "Gdansk", latitude: 54.35, longitude: 18.65), City(name: "Vilnius", latitude: 54.69, longitude: 25.28),
        City(name: "Riga", latitude: 56.95, longitude: 24.11), City(name: "Tallinn", latitude: 59.44, longitude: 24.75),
        City(name: "Kyiv", latitude: 50.45, longitude: 30.52), City(name: "Tromso", latitude: 69.65, longitude: 18.96),
        City(name: "Lofoten", latitude: 68.2, longitude: 13.9), City(name: "Bergen", latitude: 60.39, longitude: 5.32),
        City(name: "Gothenburg", latitude: 57.71, longitude: 11.97), City(name: "Rovaniemi", latitude: 66.50, longitude: 25.73),
        City(name: "Faroe", latitude: 62.0, longitude: -6.8), City(name: "Cornwall", latitude: 50.3, longitude: -5.0),
        City(name: "Brighton", latitude: 50.82, longitude: -0.14), City(name: "Liverpool", latitude: 53.41, longitude: -2.98),
        City(name: "Belfast", latitude: 54.60, longitude: -5.93), City(name: "Rotterdam", latitude: 51.92, longitude: 4.48),
        City(name: "Antwerp", latitude: 51.22, longitude: 4.40), City(name: "Luxembourg", latitude: 49.61, longitude: 6.13),
        City(name: "Geneva", latitude: 46.20, longitude: 6.15), City(name: "Sylt", latitude: 54.90, longitude: 8.31),
        City(name: "Rügen", latitude: 54.42, longitude: 13.43), City(name: "Zugspitze", latitude: 47.42, longitude: 10.98),
        City(name: "Düsseldorf", latitude: 51.23, longitude: 6.78), City(name: "Stuttgart", latitude: 48.78, longitude: 9.18),
        City(name: "Leipzig", latitude: 51.34, longitude: 12.37), City(name: "Nürnberg", latitude: 49.45, longitude: 11.08),
        City(name: "Bremen", latitude: 53.08, longitude: 8.80), City(name: "Hannover", latitude: 52.37, longitude: 9.73),
        City(name: "Kiel", latitude: 54.32, longitude: 10.14), City(name: "Rostock", latitude: 54.09, longitude: 12.10),
        City(name: "Bodensee", latitude: 47.6, longitude: 9.4, phrase: "Webcam live"),
        City(name: "Nordsee", latitude: 54.1, longitude: 8.2, phrase: "Webcam live"),
        City(name: "Ostsee", latitude: 54.3, longitude: 11.5, phrase: "Webcam live"),
        City(name: "Washington", latitude: 38.90, longitude: -77.04), City(name: "Boston", latitude: 42.36, longitude: -71.06),
        City(name: "Philadelphia", latitude: 39.95, longitude: -75.17), City(name: "Atlanta", latitude: 33.75, longitude: -84.39),
        City(name: "Nashville", latitude: 36.16, longitude: -86.78), City(name: "Austin", latitude: 30.27, longitude: -97.74),
        City(name: "Dallas", latitude: 32.78, longitude: -96.80), City(name: "Houston", latitude: 29.76, longitude: -95.37),
        City(name: "Denver", latitude: 39.74, longitude: -104.99), City(name: "Phoenix", latitude: 33.45, longitude: -112.07),
        City(name: "San Diego", latitude: 32.72, longitude: -117.16), City(name: "Key West", latitude: 24.56, longitude: -81.78),
        City(name: "Orlando", latitude: 28.54, longitude: -81.38), City(name: "Myrtle Beach", latitude: 33.69, longitude: -78.89),
        City(name: "Niagara Falls", latitude: 43.08, longitude: -79.07), City(name: "Yellowstone", latitude: 44.43, longitude: -110.59),
        City(name: "Anchorage", latitude: 61.22, longitude: -149.90), City(name: "Banff", latitude: 51.18, longitude: -115.57),
        City(name: "Halifax", latitude: 44.65, longitude: -63.58), City(name: "Calgary", latitude: 51.05, longitude: -114.07),
        City(name: "San Juan", latitude: 18.47, longitude: -66.11), City(name: "Jamaica", latitude: 18.1, longitude: -77.3),
        City(name: "Nassau", latitude: 25.05, longitude: -77.35), City(name: "Aruba", latitude: 12.52, longitude: -69.97),
        City(name: "Barbados", latitude: 13.19, longitude: -59.54), City(name: "Punta Cana", latitude: 18.58, longitude: -68.40),
        City(name: "Panama", latitude: 8.98, longitude: -79.52), City(name: "Costa Rica", latitude: 9.93, longitude: -84.08),
        City(name: "Guatemala", latitude: 14.63, longitude: -90.51), City(name: "Cartagena", latitude: 10.39, longitude: -75.51),
        City(name: "Medellin", latitude: 6.24, longitude: -75.58), City(name: "Quito", latitude: -0.18, longitude: -78.47),
        City(name: "Cusco", latitude: -13.53, longitude: -71.97), City(name: "La Paz", latitude: -16.50, longitude: -68.15),
        City(name: "Montevideo", latitude: -34.90, longitude: -56.16), City(name: "Florianopolis", latitude: -27.59, longitude: -48.55),
        City(name: "Salvador", latitude: -12.97, longitude: -38.50), City(name: "Ushuaia", latitude: -54.80, longitude: -68.30),
        City(name: "Puerto Vallarta", latitude: 20.65, longitude: -105.23), City(name: "Guadalajara", latitude: 20.67, longitude: -103.35),
        City(name: "Sapporo", latitude: 43.06, longitude: 141.35), City(name: "Fukuoka", latitude: 33.59, longitude: 130.40),
        City(name: "Okinawa", latitude: 26.21, longitude: 127.68), City(name: "Hiroshima", latitude: 34.39, longitude: 132.46),
        City(name: "Mount Fuji", latitude: 35.36, longitude: 138.73), City(name: "Busan", latitude: 35.18, longitude: 129.08),
        City(name: "Jeju", latitude: 33.50, longitude: 126.53), City(name: "Ho Chi Minh", latitude: 10.82, longitude: 106.63),
        City(name: "Hanoi", latitude: 21.03, longitude: 105.85), City(name: "Phuket", latitude: 7.88, longitude: 98.39),
        City(name: "Pattaya", latitude: 12.93, longitude: 100.88), City(name: "Chiang Mai", latitude: 18.79, longitude: 98.99),
        City(name: "Kuala Lumpur", latitude: 3.14, longitude: 101.69), City(name: "Jakarta", latitude: -6.21, longitude: 106.85),
        City(name: "Kathmandu", latitude: 27.72, longitude: 85.32), City(name: "Colombo", latitude: 6.93, longitude: 79.86),
        City(name: "Maldives", latitude: 4.18, longitude: 73.51), City(name: "Bangalore", latitude: 12.97, longitude: 77.59),
        City(name: "Goa", latitude: 15.50, longitude: 73.83), City(name: "Doha", latitude: 25.29, longitude: 51.53),
        City(name: "Abu Dhabi", latitude: 24.45, longitude: 54.38), City(name: "Riyadh", latitude: 24.71, longitude: 46.68),
        City(name: "Tel Aviv", latitude: 32.09, longitude: 34.78), City(name: "Amman", latitude: 31.95, longitude: 35.93),
        City(name: "Tbilisi", latitude: 41.72, longitude: 44.79), City(name: "Baku", latitude: 40.41, longitude: 49.87),
        City(name: "Almaty", latitude: 43.24, longitude: 76.89), City(name: "Tashkent", latitude: 41.30, longitude: 69.24),
        City(name: "Ulaanbaatar", latitude: 47.89, longitude: 106.91), City(name: "Macau", latitude: 22.20, longitude: 113.54),
        City(name: "Marrakech", latitude: 31.63, longitude: -7.99), City(name: "Casablanca", latitude: 33.57, longitude: -7.59),
        City(name: "Tunis", latitude: 36.81, longitude: 10.18), City(name: "Lagos", latitude: 6.52, longitude: 3.38),
        City(name: "Accra", latitude: 5.60, longitude: -0.19), City(name: "Dakar", latitude: 14.72, longitude: -17.47),
        City(name: "Addis Ababa", latitude: 9.03, longitude: 38.74), City(name: "Zanzibar", latitude: -6.16, longitude: 39.20),
        City(name: "Kruger", latitude: -24.0, longitude: 31.5), City(name: "Durban", latitude: -29.86, longitude: 31.02),
        City(name: "Mauritius", latitude: -20.16, longitude: 57.50), City(name: "Victoria Falls", latitude: -17.92, longitude: 25.86),
        City(name: "Windhoek", latitude: -22.56, longitude: 17.08), City(name: "Kigali", latitude: -1.95, longitude: 30.06),
        City(name: "Brisbane", latitude: -27.47, longitude: 153.03), City(name: "Gold Coast", latitude: -28.02, longitude: 153.40),
        City(name: "Perth", latitude: -31.95, longitude: 115.86), City(name: "Adelaide", latitude: -34.93, longitude: 138.60),
        City(name: "Cairns", latitude: -16.92, longitude: 145.77), City(name: "Hobart", latitude: -42.88, longitude: 147.33),
        City(name: "Wellington", latitude: -41.29, longitude: 174.78), City(name: "Queenstown", latitude: -45.03, longitude: 168.66),
        City(name: "Fiji", latitude: -17.71, longitude: 178.07), City(name: "Tahiti", latitude: -17.65, longitude: -149.43),
        City(name: "Guam", latitude: 13.44, longitude: 144.79), City(name: "Svalbard", latitude: 78.22, longitude: 15.65),
        City(name: "McMurdo", latitude: -77.85, longitude: 166.67),
        // Germany in depth: German titles say "Webcam" or "Livecam".
        City(name: "Aachen", latitude: 50.776, longitude: 6.084, phrase: "Webcam live"),
        City(name: "Augsburg", latitude: 48.371, longitude: 10.898, phrase: "Webcam live"),
        City(name: "Bamberg", latitude: 49.892, longitude: 10.887, phrase: "Webcam live"),
        City(name: "Bielefeld", latitude: 52.03, longitude: 8.53, phrase: "Webcam live"),
        City(name: "Bochum", latitude: 51.48, longitude: 7.22, phrase: "Webcam live"),
        City(name: "Bonn", latitude: 50.737, longitude: 7.098, phrase: "Webcam live"),
        City(name: "Braunschweig", latitude: 52.27, longitude: 10.52, phrase: "Webcam live"),
        City(name: "Chemnitz", latitude: 50.83, longitude: 12.92, phrase: "Webcam live"),
        City(name: "Dortmund", latitude: 51.514, longitude: 7.468, phrase: "Webcam live"),
        City(name: "Duisburg", latitude: 51.43, longitude: 6.76, phrase: "Webcam live"),
        City(name: "Erfurt", latitude: 50.98, longitude: 11.03, phrase: "Webcam live"),
        City(name: "Essen", latitude: 51.456, longitude: 7.012, phrase: "Webcam live"),
        City(name: "Freiburg", latitude: 47.999, longitude: 7.842, phrase: "Webcam live"),
        City(name: "Göttingen", latitude: 51.54, longitude: 9.93, phrase: "Webcam live"),
        City(name: "Halle", latitude: 51.48, longitude: 11.97, phrase: "Webcam live"),
        City(name: "Heidelberg", latitude: 49.40, longitude: 8.69, phrase: "Webcam live"),
        City(name: "Heilbronn", latitude: 49.14, longitude: 9.22, phrase: "Webcam live"),
        City(name: "Ingolstadt", latitude: 48.76, longitude: 11.43, phrase: "Webcam live"),
        City(name: "Jena", latitude: 50.93, longitude: 11.59, phrase: "Webcam live"),
        City(name: "Karlsruhe", latitude: 49.007, longitude: 8.40, phrase: "Webcam live"),
        City(name: "Kassel", latitude: 51.31, longitude: 9.48, phrase: "Webcam live"),
        City(name: "Koblenz", latitude: 50.36, longitude: 7.59, phrase: "Webcam live"),
        City(name: "Lübeck", latitude: 53.87, longitude: 10.69, phrase: "Webcam live"),
        City(name: "Magdeburg", latitude: 52.13, longitude: 11.63, phrase: "Webcam live"),
        City(name: "Mainz", latitude: 50.0, longitude: 8.27, phrase: "Webcam live"),
        City(name: "Mannheim", latitude: 49.49, longitude: 8.47, phrase: "Webcam live"),
        City(name: "Münster", latitude: 51.96, longitude: 7.63, phrase: "Webcam live"),
        City(name: "Oldenburg", latitude: 53.14, longitude: 8.21, phrase: "Webcam live"),
        City(name: "Osnabrück", latitude: 52.28, longitude: 8.05, phrase: "Webcam live"),
        City(name: "Passau", latitude: 48.57, longitude: 13.43, phrase: "Webcam live"),
        City(name: "Potsdam", latitude: 52.39, longitude: 13.06, phrase: "Webcam live"),
        City(name: "Regensburg", latitude: 49.01, longitude: 12.10, phrase: "Webcam live"),
        City(name: "Saarbrücken", latitude: 49.24, longitude: 6.99, phrase: "Webcam live"),
        City(name: "Schwerin", latitude: 53.63, longitude: 11.41, phrase: "Webcam live"),
        City(name: "Trier", latitude: 49.75, longitude: 6.64, phrase: "Webcam live"),
        City(name: "Ulm", latitude: 48.40, longitude: 9.99, phrase: "Webcam live"),
        City(name: "Wiesbaden", latitude: 50.08, longitude: 8.24, phrase: "Webcam live"),
        City(name: "Würzburg", latitude: 49.79, longitude: 9.95, phrase: "Webcam live"),
        City(name: "Wuppertal", latitude: 51.26, longitude: 7.15, phrase: "Webcam live"),
        City(name: "Flensburg", latitude: 54.78, longitude: 9.44, phrase: "Webcam live"),
        City(name: "Stralsund", latitude: 54.31, longitude: 13.09, phrase: "Webcam live"),
        City(name: "Wismar", latitude: 53.89, longitude: 11.46, phrase: "Webcam live"),
        City(name: "Warnemünde", latitude: 54.18, longitude: 12.08, phrase: "Webcam live"),
        City(name: "Travemünde", latitude: 53.96, longitude: 10.87, phrase: "Webcam live"),
        City(name: "Cuxhaven", latitude: 53.86, longitude: 8.69, phrase: "Webcam live"),
        City(name: "Wilhelmshaven", latitude: 53.53, longitude: 8.11, phrase: "Webcam live"),
        City(name: "Bremerhaven", latitude: 53.54, longitude: 8.58, phrase: "Webcam live"),
        City(name: "Emden", latitude: 53.37, longitude: 7.21, phrase: "Webcam live"),
        City(name: "Norderney", latitude: 53.71, longitude: 7.15, phrase: "Webcam live"),
        City(name: "Borkum", latitude: 53.59, longitude: 6.67, phrase: "Webcam live"),
        City(name: "Juist", latitude: 53.68, longitude: 7.0, phrase: "Webcam live"),
        City(name: "Langeoog", latitude: 53.75, longitude: 7.48, phrase: "Webcam live"),
        City(name: "Helgoland", latitude: 54.18, longitude: 7.89, phrase: "Webcam live"),
        City(name: "Föhr", latitude: 54.71, longitude: 8.50, phrase: "Webcam live"),
        City(name: "Amrum", latitude: 54.64, longitude: 8.36, phrase: "Webcam live"),
        City(name: "St. Peter-Ording", latitude: 54.31, longitude: 8.63, phrase: "Webcam live"),
        City(name: "Büsum", latitude: 54.13, longitude: 8.86, phrase: "Webcam live"),
        City(name: "Fehmarn", latitude: 54.44, longitude: 11.19, phrase: "Webcam live"),
        City(name: "Usedom", latitude: 53.95, longitude: 14.0, phrase: "Webcam live"),
        City(name: "Binz", latitude: 54.40, longitude: 13.61, phrase: "Webcam live"),
        City(name: "Zingst", latitude: 54.44, longitude: 12.69, phrase: "Webcam live"),
        City(name: "Kühlungsborn", latitude: 54.15, longitude: 11.75, phrase: "Webcam live"),
        City(name: "Timmendorfer Strand", latitude: 53.99, longitude: 10.78, phrase: "Webcam live"),
        City(name: "Scharbeutz", latitude: 54.02, longitude: 10.75, phrase: "Webcam live"),
        City(name: "Hiddensee", latitude: 54.55, longitude: 13.10, phrase: "Webcam live"),
        City(name: "Sankt Peter Ording", latitude: 54.31, longitude: 8.63, phrase: "Webcam live"),
        City(name: "Garmisch-Partenkirchen", latitude: 47.49, longitude: 11.10, phrase: "Webcam live"),
        City(name: "Berchtesgaden", latitude: 47.63, longitude: 13.0, phrase: "Webcam live"),
        City(name: "Königssee", latitude: 47.55, longitude: 12.98, phrase: "Webcam live"),
        City(name: "Oberstdorf", latitude: 47.41, longitude: 10.28, phrase: "Webcam live"),
        City(name: "Mittenwald", latitude: 47.44, longitude: 11.26, phrase: "Webcam live"),
        City(name: "Füssen", latitude: 47.57, longitude: 10.70, phrase: "Webcam live"),
        City(name: "Neuschwanstein", latitude: 47.557, longitude: 10.75, phrase: "Webcam live"),
        City(name: "Tegernsee", latitude: 47.71, longitude: 11.76, phrase: "Webcam live"),
        City(name: "Chiemsee", latitude: 47.87, longitude: 12.43, phrase: "Webcam live"),
        City(name: "Starnberger See", latitude: 47.90, longitude: 11.31, phrase: "Webcam live"),
        City(name: "Ammersee", latitude: 48.0, longitude: 11.12, phrase: "Webcam live"),
        City(name: "Schliersee", latitude: 47.73, longitude: 11.86, phrase: "Webcam live"),
        City(name: "Wendelstein", latitude: 47.70, longitude: 12.01, phrase: "Webcam live"),
        City(name: "Feldberg", latitude: 47.87, longitude: 8.0, phrase: "Webcam live"),
        City(name: "Titisee", latitude: 47.90, longitude: 8.15, phrase: "Webcam live"),
        City(name: "Schwarzwald", latitude: 48.3, longitude: 8.2, phrase: "Webcam live"),
        City(name: "Brocken", latitude: 51.80, longitude: 10.62, phrase: "Webcam live"),
        City(name: "Harz", latitude: 51.75, longitude: 10.6, phrase: "Webcam live"),
        City(name: "Wernigerode", latitude: 51.83, longitude: 10.79, phrase: "Webcam live"),
        City(name: "Fichtelberg", latitude: 50.43, longitude: 12.95, phrase: "Webcam live"),
        City(name: "Oberwiesenthal", latitude: 50.42, longitude: 12.97, phrase: "Webcam live"),
        City(name: "Winterberg", latitude: 51.19, longitude: 8.53, phrase: "Webcam live"),
        City(name: "Willingen", latitude: 51.29, longitude: 8.61, phrase: "Webcam live"),
        City(name: "Sächsische Schweiz", latitude: 50.95, longitude: 14.07, phrase: "Webcam live"),
        City(name: "Bastei", latitude: 50.96, longitude: 14.07, phrase: "Webcam live"),
        City(name: "Rhein", latitude: 50.15, longitude: 7.7, phrase: "Webcam live"),
        City(name: "Loreley", latitude: 50.14, longitude: 7.73, phrase: "Webcam live"),
        City(name: "Rüdesheim", latitude: 49.98, longitude: 7.92, phrase: "Webcam live"),
        City(name: "Mosel", latitude: 49.95, longitude: 7.1, phrase: "Webcam live"),
        City(name: "Cochem", latitude: 50.15, longitude: 7.17, phrase: "Webcam live"),
        City(name: "Elbe", latitude: 53.54, longitude: 9.97, phrase: "Webcam live"),
        City(name: "Hamburger Hafen", latitude: 53.54, longitude: 9.97, phrase: "Webcam live"),
        City(name: "Landungsbrücken", latitude: 53.546, longitude: 9.97, phrase: "Webcam live"),
        City(name: "Kiel Kanal", latitude: 54.33, longitude: 9.95, phrase: "Webcam live"),
        City(name: "Müritz", latitude: 53.43, longitude: 12.70, phrase: "Webcam live"),
        City(name: "Spreewald", latitude: 51.85, longitude: 13.97, phrase: "Webcam live"),
        City(name: "Bayerischer Wald", latitude: 48.95, longitude: 13.4, phrase: "Webcam live"),
        City(name: "Allgäu", latitude: 47.6, longitude: 10.4, phrase: "Webcam live"),
        City(name: "Watzmann", latitude: 47.55, longitude: 12.92, phrase: "Webcam live"),
        City(name: "Großglockner", latitude: 47.07, longitude: 12.69, phrase: "Webcam live"),
        // Local names and words; results have to name the place in that spelling.
        City(name: "東京", latitude: 35.676, longitude: 139.65, phrase: "ライブカメラ"),
        City(name: "渋谷", latitude: 35.66, longitude: 139.70, phrase: "ライブカメラ"),
        City(name: "横浜", latitude: 35.44, longitude: 139.64, phrase: "ライブカメラ"),
        City(name: "大阪", latitude: 34.694, longitude: 135.502, phrase: "ライブカメラ"),
        City(name: "京都", latitude: 35.012, longitude: 135.768, phrase: "ライブカメラ"),
        City(name: "名古屋", latitude: 35.18, longitude: 136.91, phrase: "ライブカメラ"),
        City(name: "札幌", latitude: 43.06, longitude: 141.35, phrase: "ライブカメラ"),
        City(name: "北海道", latitude: 43.2, longitude: 142.8, phrase: "ライブカメラ"),
        City(name: "福岡", latitude: 33.59, longitude: 130.40, phrase: "ライブカメラ"),
        City(name: "沖縄", latitude: 26.21, longitude: 127.68, phrase: "ライブカメラ"),
        City(name: "富士山", latitude: 35.36, longitude: 138.73, phrase: "ライブカメラ"),
        City(name: "箱根", latitude: 35.23, longitude: 139.02, phrase: "ライブカメラ"),
        City(name: "서울", latitude: 37.567, longitude: 126.978, phrase: "라이브 캠"),
        City(name: "부산", latitude: 35.18, longitude: 129.08, phrase: "라이브 캠"),
        City(name: "台北", latitude: 25.033, longitude: 121.565, phrase: "即時影像"),
        City(name: "香港", latitude: 22.319, longitude: 114.169, phrase: "直播"),
        City(name: "Ciudad de México", latitude: 19.433, longitude: -99.133, phrase: "cámara en vivo"),
        City(name: "Acapulco", latitude: 16.85, longitude: -99.88, phrase: "cámara en vivo"),
        City(name: "Mar del Plata", latitude: -38.0, longitude: -57.55, phrase: "cámara en vivo"),
        City(name: "Valparaíso", latitude: -33.05, longitude: -71.62, phrase: "cámara en vivo"),
        City(name: "Benidorm", latitude: 38.54, longitude: -0.13, phrase: "webcam en directo"),
        City(name: "Copacabana", latitude: -22.97, longitude: -43.18, phrase: "câmera ao vivo"),
        City(name: "Balneário Camboriú", latitude: -26.99, longitude: -48.63, phrase: "câmera ao vivo"),
        City(name: "Fortaleza", latitude: -3.73, longitude: -38.52, phrase: "câmera ao vivo"),
        City(name: "Recife", latitude: -8.05, longitude: -34.9, phrase: "câmera ao vivo"),
        City(name: "Nazaré", latitude: 39.60, longitude: -9.07, phrase: "câmara ao vivo"),
        City(name: "İstanbul", latitude: 41.008, longitude: 28.978, phrase: "canlı kamera"),
        City(name: "Bodrum", latitude: 37.03, longitude: 27.43, phrase: "canlı kamera"),
        City(name: "İzmir", latitude: 38.42, longitude: 27.14, phrase: "canlı kamera"),
        City(name: "Москва", latitude: 55.756, longitude: 37.617, phrase: "веб камера онлайн"),
        City(name: "Санкт-Петербург", latitude: 59.94, longitude: 30.31, phrase: "веб камера онлайн"),
        City(name: "Сочи", latitude: 43.60, longitude: 39.73, phrase: "веб камера онлайн"),
        City(name: "Владивосток", latitude: 43.12, longitude: 131.89, phrase: "веб камера онлайн"),
        City(name: "Zakopane", latitude: 49.30, longitude: 19.95, phrase: "kamera na żywo"),
        City(name: "Sopot", latitude: 54.44, longitude: 18.56, phrase: "kamera na żywo"),
        City(name: "Praha", latitude: 50.075, longitude: 14.437, phrase: "webkamera živě"),
        City(name: "Venezia", latitude: 45.44, longitude: 12.316, phrase: "webcam in diretta"),
        City(name: "Cortina", latitude: 46.54, longitude: 12.14, phrase: "webcam in diretta"),
        City(name: "Lago di Garda", latitude: 45.6, longitude: 10.65, phrase: "webcam in diretta"),
        City(name: "Chamonix", latitude: 45.92, longitude: 6.87, phrase: "webcam en direct"),
        City(name: "Biarritz", latitude: 43.48, longitude: -1.56, phrase: "webcam en direct"),
        City(name: "Québec", latitude: 46.81, longitude: -71.21, phrase: "webcam en direct"),
    ]
}
