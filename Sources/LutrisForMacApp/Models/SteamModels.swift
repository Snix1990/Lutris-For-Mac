import Foundation

struct SteamGetOwnedGamesResponse: Codable {
    let response: SteamOwnedGames?
}

struct SteamOwnedGames: Codable {
    let gameCount: Int
    let games: [SteamGameInfo]?

    enum CodingKeys: String, CodingKey {
        case gameCount = "game_count"
        case games
    }
}

struct SteamGameInfo: Codable, Identifiable {
    let appid: Int
    let name: String?
    let playtimeForever: Int
    let playtime2Weeks: Int?
    let imgIconUrl: String?
    let imgLogoUrl: String?

    var id: Int { appid }

    enum CodingKeys: String, CodingKey {
        case appid, name
        case playtimeForever = "playtime_forever"
        case playtime2Weeks = "playtime_2weeks"
        case imgIconUrl = "img_icon_url"
        case imgLogoUrl = "img_logo_url"
    }
}

struct SteamPlayerSummariesResponse: Codable {
    let response: SteamPlayerSummaries?
}

struct SteamPlayerSummaries: Codable {
    let players: [SteamPlayerSummary]?
}

struct SteamPlayerSummary: Codable {
    let steamid: String
    let personaname: String?
    let avatarfull: String?
}

struct SteamAppDetailsResponse: Codable {
    let steamAppid: String?
    let success: Bool?
    let data: SteamAppDetailsData?

    enum CodingKeys: String, CodingKey {
        case steamAppid = "steam_appid"
        case success, data
    }
}

struct SteamAppDetailsData: Codable {
    let type: String?
    let name: String?
    let shortDescription: String?
    let genres: [SteamGenre]?

    enum CodingKeys: String, CodingKey {
        case type, name, genres
        case shortDescription = "short_description"
    }
}

struct SteamGenre: Codable, Hashable {
    let id: Int
    let description: String
}
