import Foundation

// User-facing text is looked up in <language>.lproj/Localizable.strings
// (German, French and Italian). The key is the English text, which is also
// what is shown when a translation is missing or the system language is English.

/// The text for `key` in the user's language.
func tr(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// A translated format string, filled in with the user's number formatting.
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: tr(key), locale: .current, arguments: args)
}
