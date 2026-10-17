import Foundation
import SwiftUI

/// Ein Termin aus dem macOS-Kalender (also aus den verbundenen Google-Konten).
struct Meeting: Identifiable, Hashable {
    /// Stabiler Schlüssel, unter dem die Notiz gespeichert wird.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    let accountTitle: String
    let calendarColor: Color
    let location: String?
    let eventNotes: String?
    let eventURL: URL?

    var joinURL: URL? {
        MeetingLink.find(in: [eventURL?.absoluteString, location, eventNotes])
    }

    var isNow: Bool {
        let now = Date()
        return start <= now && now < end
    }
}

extension Meeting {
    /// Ersatz aus der gespeicherten Notiz, falls der Termin nicht (mehr) geladen ist.
    init(note n: MeetingNote) {
        self.init(id: n.id, title: n.title, start: n.start, end: n.end, isAllDay: false,
                  calendarTitle: n.calendarTitle, accountTitle: n.calendarTitle, calendarColor: .accentColor,
                  location: nil, eventNotes: nil, eventURL: nil)
    }
}

/// Deine Notizen zu einem konkreten Meeting. Titel, Zeit und Kalender werden
/// mitgespeichert, damit die Notiz auch nach dem Termin noch auffindbar ist.
struct MeetingNote: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarTitle: String

    var goal: String = ""
    var agenda: [AgendaItem] = []
    var attachments: [Attachment] = []
    var nextSteps: [AgendaItem] = []
    var projects: [AgendaItem] = []
    var people: String = ""
    var links: String = ""
    var notes: String = ""

    var updatedAt: Date = Date()

    init(meeting: Meeting) {
        id = meeting.id
        title = meeting.title
        start = meeting.start
        end = meeting.end
        calendarTitle = meeting.calendarTitle
    }

    /// Agendapunkte mit Inhalt (leere Zeilen werden ignoriert).
    var filledAgenda: [AgendaItem] {
        agenda.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var filledNextSteps: [AgendaItem] { nextSteps.filter(\.hasText) }
    var filledProjects: [AgendaItem] { projects.filter(\.hasText) }

    /// Offene, noch nicht an Things übertragene Punkte.
    var pendingForThings: (steps: [AgendaItem], projects: [AgendaItem]) {
        (filledNextSteps.filter { !$0.done && !$0.sentToThings },
         filledProjects.filter { !$0.done && !$0.sentToThings })
    }

    var isEmpty: Bool {
        filledAgenda.isEmpty && filledNextSteps.isEmpty && filledProjects.isEmpty && attachments.isEmpty
            && [goal, people, links, notes].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Nicht-leere Textfelder in Anzeigereihenfolge (die Agenda wird separat als Checkliste gezeigt).
    var filledSections: [(label: String, icon: String, text: String)] {
        let all: [(String, String, String)] = [
            ("Ziel", "target", goal),
            ("Teilnehmer & Kontext", "person.2", people),
            ("Links", "link", links),
            ("Notizen", "note.text", notes),
        ]
        return all.compactMap { label, icon, text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (label, icon, trimmed)
        }
    }

    // Eigenes Decoding: ältere Notizen speicherten die Agenda als Freitext.
    // Jede Zeile davon wird zu einem Checklistenpunkt.
    enum CodingKeys: String, CodingKey {
        case id, title, start, end, calendarTitle, goal, agenda, attachments, nextSteps, projects, people, links, notes, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        calendarTitle = try c.decodeIfPresent(String.self, forKey: .calendarTitle) ?? ""
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        people = try c.decodeIfPresent(String.self, forKey: .people) ?? ""
        links = try c.decodeIfPresent(String.self, forKey: .links) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        attachments = (try? c.decodeIfPresent([Attachment].self, forKey: .attachments)) ?? []
        nextSteps = (try? c.decodeIfPresent([AgendaItem].self, forKey: .nextSteps)) ?? []
        projects = (try? c.decodeIfPresent([AgendaItem].self, forKey: .projects)) ?? []
        if let items = try? c.decode([AgendaItem].self, forKey: .agenda) {
            agenda = items
        } else if let text = try? c.decode(String.self, forKey: .agenda) {
            agenda = AgendaItem.fromLegacy(text)
        }
    }
}

/// Ein Punkt einer abhakbaren Liste (Agenda, Nächste Schritte, Projekte).
struct AgendaItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String = ""
    var done: Bool = false
    /// Bereits an Things übertragen (nur bei Nächsten Schritten und Projekten).
    var sentToThings: Bool = false

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init(id: UUID = UUID(), text: String = "", done: Bool = false, sentToThings: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
        self.sentToThings = sentToThings
    }

    // Ältere Dateien kennen sentToThings noch nicht
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        sentToThings = try c.decodeIfPresent(Bool.self, forKey: .sentToThings) ?? false
    }

    static func fromLegacy(_ text: String) -> [AgendaItem] {
        text.components(separatedBy: .newlines)
            .map { line in
                // Gängige Aufzählungszeichen am Zeilenanfang entfernen
                var t = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "• ", "– "] where t.hasPrefix(prefix) {
                    t = String(t.dropFirst(prefix.count))
                    break
                }
                return AgendaItem(text: t, done: line.contains("[x]"))
            }
            .filter { !$0.text.isEmpty }
    }
}

extension MeetingNote {
    /// Gleicher Inhalt, unabhängig vom Änderungszeitpunkt.
    func sameContent(as other: MeetingNote) -> Bool {
        var a = self
        a.updatedAt = other.updatedAt
        return a == other
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let texts: [String] = [title, calendarTitle, goal, people, links, notes]
        let listTexts: [String] = (agenda + nextSteps + projects).map(\.text)
        let fileTitles: [String] = attachments.map(\.title)
        return (texts + listTexts + fileTitles)
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

enum MeetingLink {
    private static let hosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "gotomeeting.com", "meet.jit.si", "around.co",
    ]

    static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}

enum Fmt {
    /// Datumsformate folgen der Sprache und Region des Macs.
    static var locale: Locale { .autoupdatingCurrent }

    static func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Heute") }
        if cal.isDateInTomorrow(d) { return L("Morgen") }
        if cal.isDateInYesterday(d) { return L("Gestern") }
        return d.formatted(Date.FormatStyle().weekday(.wide).day().month(.wide).locale(locale))
    }

    static func dayShort(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
    }

    static func range(_ m: Meeting) -> String {
        m.isAllDay ? L("Ganztägig") : "\(time(m.start)) – \(time(m.end))"
    }
}
