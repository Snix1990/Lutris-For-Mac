import SwiftUI

public final class LanguageStore: @unchecked Sendable {
    public var translations: [String: [String: String]] = [:]
    public static let shared = LanguageStore()
    private init() {}
}

@MainActor
public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    @AppStorage("appLanguage") public var language: String = "" {
        didSet { applyLanguage() }
    }

    @Published public var refreshID = UUID()

    public var currentLanguage: String {
        language.isEmpty ? "en" : language
    }

    public var locale: Locale {
        Locale(identifier: currentLanguage)
    }

    public var displayName: String {
        Self.availableLanguages.first(where: { $0.code == currentLanguage })?.name ?? currentLanguage
    }

    public static let availableLanguages: [(code: String, name: String)] = [
        ("de", "Deutsch"),
        ("en", "English"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt-BR", "Português (Brasil)"),
        ("ru", "Русский"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("ar", "العربية"),
        ("hi", "हिन्दी"),
        ("tr", "Türkçe"),
        ("pl", "Polski"),
        ("nl", "Nederlands"),
        ("sv", "Svenska"),
        ("vi", "Tiếng Việt"),
        ("cs", "Čeština"),
    ]

    private let store = LanguageStore.shared

    private init() {
        loadTranslations()
        applyLanguage()
    }

    private func loadTranslations() {
        let bundle = Bundle.main
        var allKeys = Set<String>()

        for code in Self.availableLanguages.map({ $0.code }) where code != "de" {
            let lookupCode = code.lowercased()
            guard let lprojPath = bundle.path(forResource: lookupCode, ofType: "lproj", inDirectory: "Locals"),
                  let lprojBundle = Bundle(path: lprojPath),
                  let stringsPath = lprojBundle.path(forResource: "Localizable", ofType: "strings"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: stringsPath)),
                  let dict = Self.parseStrings(data) else {
                continue
            }
            store.translations[code] = dict
            allKeys.formUnion(dict.keys)
        }

        store.translations["de"] = Dictionary(uniqueKeysWithValues: allKeys.map { ($0, $0) })
    }

    private static func parseStrings(_ data: Data) -> [String: String]? {
        if let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] {
            return dict
        }
        guard let content = String(data: data, encoding: .utf8) else { return nil }
        return parseStringsManual(content)
    }

    private static func parseStringsManual(_ content: String) -> [String: String]? {
        var result: [String: String] = [:]
        var remaining = content[...]

        while !remaining.isEmpty {
            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            guard remaining.first == "\"" else { break }
            remaining = remaining.dropFirst()
            var key = ""
            while let c = remaining.first {
                if c == "\"" { remaining = remaining.dropFirst(); break }
                if c == "\\" { remaining = remaining.dropFirst(); key.append(remaining.first ?? "\\"); remaining = remaining.dropFirst() }
                else { key.append(c); remaining = remaining.dropFirst() }
            }
            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            guard remaining.first == "=" else { break }
            remaining = remaining.dropFirst()
            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            guard remaining.first == "\"" else { break }
            remaining = remaining.dropFirst()
            var value = ""
            while let c = remaining.first {
                if c == "\"" { remaining = remaining.dropFirst(); break }
                if c == "\\" { remaining = remaining.dropFirst(); value.append(remaining.first ?? "\\"); remaining = remaining.dropFirst() }
                else { value.append(c); remaining = remaining.dropFirst() }
            }
            remaining = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            if remaining.first == ";" { remaining = remaining.dropFirst() }
            result[key] = value
        }
        return result.isEmpty ? nil : result
    }

    public nonisolated func localized(_ key: String) -> String {
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        let lang = savedLang.isEmpty ? "en" : savedLang
        return LanguageStore.shared.translations[lang]?[key] ?? key
    }

    private func applyLanguage() {
        UserDefaults.standard.set([currentLanguage], forKey: "AppleLanguages")
        refreshID = UUID()
    }
}

public func tr(_ key: String) -> String {
    let savedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    let lang = savedLang.isEmpty ? "en" : savedLang
    return LanguageStore.shared.translations[lang]?[key] ?? key
}

public func trf(_ key: String, _ args: CVarArg...) -> String {
    return String(format: tr(key), arguments: args)
}

extension View {
    public func helpLText(_ key: String) -> some View {
        self.help(Text(verbatim: tr(key)))
    }
}
