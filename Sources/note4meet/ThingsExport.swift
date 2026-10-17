import AppKit

/// Überträgt Nächste Schritte (als Aufgaben für „Heute“) und Projekte
/// (als eigene Things-Projekte) über das offizielle Things-URL-Schema.
/// https://culturedcode.com/things/support/articles/2803573/
enum ThingsExport {
    static var isInstalled: Bool {
        URL(string: "things:///show").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
    }

    /// „Aus Meeting: Demo/Trainingsplanung, 16.10.2026“
    static func noteText(for note: MeetingNote) -> String {
        let date = note.start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Fmt.locale))
        return L("Aus Meeting: %@, %@", note.title, date)
    }

    /// Baut den things:///json-Aufruf. Neue Objekte anlegen braucht kein Auth-Token.
    static func url(steps: [AgendaItem], projects: [AgendaItem], note: MeetingNote) -> URL? {
        let notes = noteText(for: note)
        var items: [[String: Any]] = []
        for s in steps {
            items.append(["type": "to-do", "attributes": ["title": s.text, "notes": notes, "when": "today"]])
        }
        for p in projects {
            items.append(["type": "project", "attributes": ["title": p.text, "notes": notes]])
        }
        guard !items.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        var c = URLComponents()
        c.scheme = "things"
        c.host = ""
        c.path = "/json"
        c.queryItems = [URLQueryItem(name: "data", value: json), URLQueryItem(name: "reveal", value: "true")]
        // URLComponents lässt „+“ und „&“ in Werten teilweise stehen; Things erwartet strikte Kodierung
        c.percentEncodedQuery = c.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    /// Sendet die offenen Punkte; gibt true zurück, wenn Things den Aufruf erhalten hat.
    @MainActor
    static func send(_ note: MeetingNote) -> Bool {
        let pending = note.pendingForThings
        guard isInstalled else {
            let alert = NSAlert()
            alert.messageText = L("Things ist nicht installiert")
            alert.informativeText = L("Things 3 wurde auf diesem Mac nicht gefunden.")
            alert.runModal()
            return false
        }
        guard let url = url(steps: pending.steps, projects: pending.projects, note: note) else { return false }
        DebugLog.write("Things: \(pending.steps.count) Aufgabe(n), \(pending.projects.count) Projekt(e)")
        return NSWorkspace.shared.open(url)
    }
}
