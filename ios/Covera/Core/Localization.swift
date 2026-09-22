import Foundation
import SwiftUI

/// The app's own language setting, independent of the phone's.
///
/// English unless the reader picks otherwise in Account. Every
/// `String(localized:)` in the app resolves through `Bundle.covera`, so a change
/// takes effect as soon as the screens redraw — no relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, fr, es, pt, de, he, ar, hi, th, ja

    static let storageKey = "covera.language"

    var id: String { rawValue }

    /// Each language names itself, so anyone can find their own.
    var name: String {
        switch self {
        case .en: "English"
        case .fr: "Français"
        case .es: "Español"
        case .pt: "Português"
        case .de: "Deutsch"
        case .he: "עברית"
        case .ar: "العربية"
        case .hi: "हिन्दी"
        case .th: "ไทย"
        case .ja: "日本語"
        }
    }

    /// Letter-spacing is a Latin-script effect. In Arabic, Hebrew, Hindi and
    /// Thai it breaks letters apart (Arabic cursive visibly disconnects), so
    /// tracking is applied only for these.
    var isLatinScript: Bool { [.en, .fr, .es, .pt, .de].contains(self) }

    /// Hebrew and Arabic read right to left; the whole layout mirrors.
    var isRightToLeft: Bool { self == .he || self == .ar }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .en
    }
}

extension Bundle {
    /// The `.lproj` for the chosen language. `en.lproj` holds no string table,
    /// so lookups there fall back to the English source text — which is what
    /// makes English stick even on a phone set to French.
    static var covera: Bundle {
        guard let path = Bundle.main.path(forResource: AppLanguage.current.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

extension String {
    /// Preferred over Foundation's overload (it needs no defaulted arguments),
    /// so every existing `String(localized:)` call follows the in-app setting.
    init(localized key: String.LocalizationValue) {
        self.init(localized: key, bundle: .covera)
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Dates in the app's chosen language rather than the phone's —
    /// `.formatted(.dateTime)` alone ignores the in-app setting.
    static var coveraDate: Date.FormatStyle {
        .dateTime.locale(Locale(identifier: AppLanguage.current.rawValue))
    }
}

extension View {
    /// Sheets and full-screen covers begin a new presentation and do not carry
    /// the app's layout direction with them, so presented content sets it again —
    /// otherwise a Hebrew or Arabic flow opens laid out left to right.
    func coveraLayoutDirection() -> some View {
        environment(\.layoutDirection, AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
