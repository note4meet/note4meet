import Foundation

/// Übersetzt einen Text aus dem Code (Schlüssel = deutscher Originaltext).
/// Für Texte, die SwiftUI nicht automatisch übersetzt: Variablen, zusammengesetzte
/// Texte, Exporte, Systemdialoge. Übersetzungen: Support/en.lproj/Localizable.strings
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Übersetzt eine Formatvorlage und setzt die Werte ein, z. B. L("Beginnt in %d Min.", 5).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: args)
}
