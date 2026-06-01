import SwiftUI

/// A localized text view that automatically updates when the language changes.
/// Usage: LText("key") instead of Text("key")
struct LText: View {
    @StateObject private var lang = LanguageManager.shared
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(verbatim: lang.localized(key))
            .id(lang.refreshID)
    }
}
