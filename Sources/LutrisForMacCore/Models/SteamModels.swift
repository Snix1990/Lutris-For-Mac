import Foundation

public struct SteamGetOwnedGamesResponse: Codable {
    public let response: SteamOwnedGames?
}

public struct SteamOwnedGames: Codable {
    public let gameCount: Int
    public let games: [SteamGameInfo]?

    public enum CodingKeys: String, CodingKey {
        case gameCount = "game_count"
        case games
    }
}

public struct SteamGameInfo: Codable, Identifiable {
    public let appid: Int
    public let name: String?
    public let playtimeForever: Int
    public let playtime2Weeks: Int?
    public let imgIconUrl: String?
    public let imgLogoUrl: String?

    public var id: Int { appid }

    public enum CodingKeys: String, CodingKey {
        case appid, name
        case playtimeForever = "playtime_forever"
        case playtime2Weeks = "playtime_2weeks"
        case imgIconUrl = "img_icon_url"
        case imgLogoUrl = "img_logo_url"
    }
}

public struct SteamPlayerSummariesResponse: Codable {
    public let response: SteamPlayerSummaries?
}

public struct SteamPlayerSummaries: Codable {
    public let players: [SteamPlayerSummary]?
}

public struct SteamPlayerSummary: Codable {
    public let steamid: String
    public let personaname: String?
    public let avatarfull: String?
}

public struct SteamAppDetailsResponse: Codable {
    public let steamAppid: String?
    public let success: Bool?
    public let data: SteamAppDetailsData?

    public enum CodingKeys: String, CodingKey {
        case steamAppid = "steam_appid"
        case success, data
    }
}

public struct SteamAppDetailsData: Codable {
    public let type: String?
    public let name: String?
    public let shortDescription: String?
    public let genres: [SteamGenre]?

    public enum CodingKeys: String, CodingKey {
        case type, name, genres
        case shortDescription = "short_description"
    }
}

public struct SteamGenre: Codable, Hashable {
    public let id: Int
    public let description: String
}
