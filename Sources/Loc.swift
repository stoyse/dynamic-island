import Foundation

/// Tiny localization helper: English by default, follows the Mac's UI language.
/// English is the base; German is provided where the app shipped German text.
/// Any other system language falls back to English.
func L(_ en: String, _ de: String) -> String {
    let pref = Locale.preferredLanguages.first?.lowercased() ?? "en"
    return pref.hasPrefix("de") ? de : en
}
