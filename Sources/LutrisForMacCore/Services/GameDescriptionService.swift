import Foundation

// ================================================================
// GameDescriptionService.swift
// ================================================================
// Holt Spielbeschreibungen aus Quellen:
// 1. Steam API (wenn steamAppID gesetzt)
// 2. Wikipedia API (fuzzy match via Spielname)
// Unterstützt sprachspezifisches Fetching.
// ================================================================

@MainActor
public enum GameDescriptionService {

    /// Holt die Beschreibung asynchron in der angegebenen Sprache.
    public static func fetchDescription(gameName: String, steamAppID: String?, language: String = "en") async -> String? {
        if let sid = steamAppID, !sid.isEmpty {
            if let desc = await fetchFromSteam(appID: sid, language: language) {
                return desc
            }
        }
        return await fetchFromWikipedia(gameName: gameName, language: language)
    }

    // MARK: - Steam API

    private static func fetchFromSteam(appID: String, language: String) async -> String? {
        let steamLang = steamLanguageCode(language)
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=\(steamLang)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appData = json[appID] as? [String: Any],
                  let success = appData["success"] as? Bool, success,
                  let gameData = appData["data"] as? [String: Any]
            else { return nil }

            let candidates: [String?] = [
                gameData["short_description"] as? String,
                gameData["about_the_game"] as? String,
                gameData["detailed_description"] as? String
            ]
            for candidate in candidates {
                guard let raw = candidate, !raw.isEmpty else { continue }
                let cleaned = cleanHTML(raw)
                let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isValidDescription(trimmed) else { continue }
                return cleanupHeading(trimmed)
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func isValidDescription(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Reject update/patch notices
        let skipPatterns = [
            "update available", "update is available", "new update",
            "patch notes", "patch note", "update notes", "what's new",
            "version ", "changelog", "known issues", "how to update",
            "release notes"
        ]
        for pattern in skipPatterns {
            if lower.hasPrefix(pattern) || lower.contains("\n" + pattern) {
                return false
            }
        }
        // Reject very short texts (likely not a real description)
        return text.count > 10
    }

    private static func cleanupHeading(_ text: String) -> String {
        var result = text
        let headings = [
            "Game Information", "About the Game", "About This Game",
            "Spielinformationen", "Über das Spiel", "Über dieses Spiel",
            "Informations sur le jeu", "À propos du jeu",
            "Informazioni sul gioco", "Información del juego",
            "Informações do jogo", "Over het spel",
            "Informacje o grze", "Om spelet", "O hře",
            "ゲーム情報", "게임 정보", "游戏信息", "遊戲資訊",
            "Informace o hře", "情報"
        ]
        for heading in headings {
            if result.hasPrefix(heading) {
                result = String(result.dropFirst(heading.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return result
    }

    // MARK: - Wikipedia API

    private static func fetchFromWikipedia(gameName: String, language: String) async -> String? {
        let wikiLang = wikipediaLanguageCode(language)
        let searches = searchQueries(for: gameName)

        for query in searches {
            if let desc = try? await searchWikipediaPage(wikiLang: wikiLang, query: query) {
                return desc
            }
        }
        return nil
    }

    private static func searchWikipediaPage(wikiLang: String, query: String) async throws -> String? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let searchURL = URL(string: "https://\(wikiLang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=3&srwhat=text") else { return nil }

        let (searchData, _) = try await URLSession.shared.data(from: searchURL)
        guard let searchJSON = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let queryResult = searchJSON["query"] as? [String: Any],
              let searchResults = queryResult["search"] as? [[String: Any]],
              let first = searchResults.first,
              let pageTitle = first["title"] as? String
        else { return nil }

        return try await fetchWikipediaExtract(wikiLang: wikiLang, pageTitle: pageTitle)
    }

    private static func fetchWikipediaExtract(wikiLang: String, pageTitle: String) async throws -> String? {
        let titleEncoded = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageTitle
        guard let extractURL = URL(string: "https://\(wikiLang).wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext&titles=\(titleEncoded)&format=json") else { return nil }

        let (extractData, _) = try await URLSession.shared.data(from: extractURL)
        guard let extractJSON = try JSONSerialization.jsonObject(with: extractData) as? [String: Any],
              let extractQuery = extractJSON["query"] as? [String: Any],
              let pages = extractQuery["pages"] as? [String: Any]
        else { return nil }

        for (_, page) in pages {
            if let pageData = page as? [String: Any],
               let extract = pageData["extract"] as? String,
               !extract.isEmpty {
                return extract
            }
        }
        return nil
    }

    /// Returns an ordered array of search queries to try, from most specific to most generic.
    private static func searchQueries(for gameName: String) -> [String] {
        var queries: [String] = []
        let trimmed = gameName.trimmingCharacters(in: .whitespaces)

        // 1. Exact name
        queries.append(trimmed)

        // 2. Without subtitle after colon or dash
        if let stripped = stripSubtitle(trimmed), stripped != trimmed {
            queries.append(stripped)
        }

        // 3. Exact name + " (video game)"
        queries.append("\(trimmed) (video game)")

        // 4. Without subtitle + " (video game)"
        if let stripped = stripSubtitle(trimmed), stripped != trimmed {
            queries.append("\(stripped) (video game)")
        }

        return queries
    }

    /// Strips subtitle after `:`, ` –`, ` —`, ` -` (but keeps simple hyphenated names).
    private static func stripSubtitle(_ name: String) -> String? {
        let patterns = [": ", " – ", " — ", " - "]
        for pattern in patterns {
            if let range = name.range(of: pattern) {
                return String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Batch Backfill

    /// Lädt Beschreibungen für alle Spiele ohne `gameDescription` nach.
    /// - Parameters:
    ///   - games: Liste aller Spiele (wird als Kopie übergeben)
    ///   - language: Gewünschte Sprache
    ///   - progressHandler: Wird nach jedem Spiel mit (fortschritt, gesamt) aufgerufen
    ///   - saveHandler: Wird nach jedem erfolgreichen Fetch aufgerufen (zum Persistieren)
    public static func backfillAll(
        games: [Game],
        language: String = "en",
        progressHandler: @MainActor @escaping (Int, Int) -> Void,
        saveHandler: @escaping ([Game]) -> Void
    ) async {
        let candidates = games.filter { $0.gameDescription.isEmpty }
        let total = candidates.count
        guard total > 0 else { return }

        var updatedGames = games
        var completed = 0

        for candidate in candidates {
            let desc = await fetchDescription(
                gameName: candidate.name,
                steamAppID: candidate.steamAppID,
                language: language
            )
            if let desc = desc, !desc.isEmpty {
                if let idx = updatedGames.firstIndex(where: { $0.id == candidate.id }) {
                    updatedGames[idx].gameDescription = desc
                }
            }
            completed += 1
            progressHandler(completed, total)
        }

        saveHandler(updatedGames)
    }

    // MARK: - Language Mapping

    private static func steamLanguageCode(_ appLanguage: String) -> String {
        let map: [String: String] = [
            "de": "german", "en": "english", "fr": "french", "es": "spanish",
            "it": "italian", "pt-BR": "portuguese", "ru": "russian", "zh-Hans": "schinese",
            "ja": "japanese", "ko": "korean", "ar": "arabic", "hi": "hindi",
            "tr": "turkish", "pl": "polish", "nl": "dutch", "sv": "swedish",
            "vi": "vietnamese", "cs": "czech"
        ]
        let lang = appLanguage.components(separatedBy: "-").first ?? appLanguage
        return map[appLanguage] ?? map[lang] ?? "english"
    }

    private static func wikipediaLanguageCode(_ appLanguage: String) -> String {
        let map: [String: String] = [
            "de": "de", "en": "en", "fr": "fr", "es": "es",
            "it": "it", "pt-BR": "pt", "ru": "ru", "zh-Hans": "zh",
            "ja": "ja", "ko": "ko", "ar": "ar",
            "tr": "tr", "pl": "pl", "nl": "nl", "sv": "sv",
            "vi": "vi", "cs": "cs"
        ]
        let lang = appLanguage.components(separatedBy: "-").first ?? appLanguage
        return map[appLanguage] ?? map[lang] ?? "en"
    }

    // MARK: - Helpers

    private static func cleanHTML(_ html: String) -> String {
        let wrapped = "<html><meta charset=\"UTF-8\"><body>\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8) else { return decodeHTMLEntities(html) }
        if let plain = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ).string {
            let cleaned = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? decodeHTMLEntities(html) : cleaned
        }
        return decodeHTMLEntities(html)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Manual HTML entity decoding for common entities that NSAttributedString might miss.
    private static func decodeHTMLEntities(_ string: String) -> String {
        let entities: [String: String] = [
            "&auml;": "ä", "&Auml;": "Ä", "&ouml;": "ö", "&Ouml;": "Ö",
            "&uuml;": "ü", "&Uuml;": "Ü", "&szlig;": "ß",
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&nbsp;": " ", "&#39;": "'",
            "&eacute;": "é", "&Eacute;": "É", "&egrave;": "è", "&Egrave;": "È",
            "&ecirc;": "ê", "&Ecirc;": "Ê", "&euml;": "ë", "&Euml;": "Ë",
            "&agrave;": "à", "&Agrave;": "À", "&acirc;": "â", "&Acirc;": "Â",
            "&ccedil;": "ç", "&Ccedil;": "Ç",
            "&iacute;": "í", "&Iacute;": "Í", "&oacute;": "ó", "&Oacute;": "Ó",
            "&uacute;": "ú", "&Uacute;": "Ú", "&ntilde;": "ñ", "&Ntilde;": "Ñ",
        ]
        var result = string
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#xxx; and &#xhhhh;
        let numericPattern = try? NSRegularExpression(pattern: "&#(\\d+|x[0-9a-fA-F]+);")
        if let regex = numericPattern {
            var mutated = result
            var offset = 0
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
                let full = (mutated as NSString).substring(with: fullRange)
                let numStr = String(full.dropFirst(2).dropLast())
                let scalar: UInt32?
                if numStr.hasPrefix("x") {
                    scalar = UInt32(String(numStr.dropFirst()), radix: 16)
                } else {
                    scalar = UInt32(numStr)
                }
                if let s = scalar, let us = UnicodeScalar(s) {
                    let replacement = String(us)
                    mutated = (mutated as NSString).replacingCharacters(in: fullRange, with: replacement)
                    offset += replacement.utf16.count - full.utf16.count
                }
            }
            result = mutated
        }
        return result
    }
}
