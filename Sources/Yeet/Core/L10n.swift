import Foundation

/// UI language. English is the default; Vietnamese is selectable in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, vi

    var id: String { rawValue }

    /// Always shown in its own language so users can find it.
    var displayName: String {
        switch self {
        case .en: "English"
        case .vi: "Tiếng Việt"
        }
    }

    static let key = "appLanguage"

    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .en
    }

    var locale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .vi: Locale(identifier: "vi_VN")
        }
    }
}

/// Picks the string for the current UI language: `L("Rescan", "Quét lại")`.
/// Both strings live side by side so contributors can edit them together.
/// Views re-render on a language change because the root views read
/// `@AppStorage(AppLanguage.key)` and key their content with `.id(language)`.
func L(_ en: String, _ vi: String) -> String {
    AppLanguage.current == .vi ? vi : en
}
