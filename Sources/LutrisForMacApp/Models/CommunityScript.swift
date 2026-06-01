import Foundation

struct CommunityScript: Identifiable, Codable, Hashable {
    let id: String
    let gameName: String
    let runner: String
    let platform: String
    let description: String
    let version: String
    let author: String?
    let scriptURL: String
    let coverURL: String?
    let requires: [String]
}
