import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Speichert jede Notiz als eigene JSON-Datei im Sync-Ordner
/// (iCloud Drive/note4meet/Notes). So können mehrere Macs dieselben Notizen nutzen:
/// Die App prüft den Ordner alle paar Sekunden und übernimmt Änderungen der anderen Geräte.
/// Ist iCloud Drive nicht verfügbar, liegt der Ordner lokal in Application Support.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [String: MeetingNote] = [:]
    @Published private(set) var lastSync: Date?

    /// Wurzel des Sync-Ordners (enthält „Notizen“ und „Einstellungen.json“).
    let folderURL: URL
    let notesDir: URL
    let isICloud: Bool

    /// Dateiname → Änderungsdatum beim letzten Lesen/Schreiben; erkennt fremde Änderungen.
    private var known: [String: Date] = [:]
    private var timer: Timer?
    private var scanning = false

    init() {
        let fm = FileManager.default
        let icloud = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let local = support.appendingPathComponent("note4meet", isDirectory: true)
        isICloud = fm.fileExists(atPath: icloud.path)
        folderURL = isICloud ? icloud.appendingPathComponent("note4meet", isDirectory: true) : local
        notesDir = folderURL.appendingPathComponent("Notes", isDirectory: true)

        // Umzug vom früheren Namen „MeetingNotes“
        Self.migrateFolder(from: (isICloud ? icloud : support).appendingPathComponent("MeetingNotes", isDirectory: true),
                           to: folderURL)
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)

        apply(Self.scan(notesDir))
        migrateLegacyFile(in: support.appendingPathComponent("MeetingNotes", isDirectory: true))

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncFromDisk() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncFromDisk() }
        }
    }

    func note(for id: String) -> MeetingNote? { notes[id] }

    func hasNote(_ id: String) -> Bool { notes[id].map { !$0.isEmpty } ?? false }

    /// Speichert die Notiz; leere Notizen werden entfernt.
    func save(_ note: MeetingNote) {
        var n = note
        if n.isEmpty {
            guard notes[n.id] != nil else { return }
            notes[n.id] = nil
            removeFile(for: n.id)
        } else {
            if let existing = notes[n.id] {
                n.updatedAt = existing.updatedAt
                guard existing != n else { return }
            }
            n.updatedAt = Date()
            notes[n.id] = n
            write(n)
        }
    }

    func toggleAgendaItem(note id: String, item: UUID) {
        guard var n = notes[id], let i = n.agenda.firstIndex(where: { $0.id == item }) else { return }
        n.agenda[i].done.toggle()
        save(n)
    }

    /// Hängt Dateien/E-Mails/Links an ein Meeting an (legt die Notiz bei Bedarf an).
    func addAttachments(_ items: [Attachment], to meeting: Meeting) {
        guard !items.isEmpty else { return }
        var n = notes[meeting.id] ?? MeetingNote(meeting: meeting)
        let existing = Set(n.attachments.map(\.link))
        n.attachments += items.filter { !existing.contains($0.link) }
        save(n)
    }

    func delete(_ id: String) {
        notes[id] = nil
        removeFile(for: id)
    }

    /// Hält Titel und Zeit aktuell, falls das Meeting im Kalender geändert wurde.
    func refreshSnapshots(from meetings: [Meeting]) {
        for m in meetings {
            guard var n = notes[m.id] else { continue }
            if n.title != m.title || n.start != m.start || n.end != m.end || n.calendarTitle != m.calendarTitle {
                n.title = m.title
                n.start = m.start
                n.end = m.end
                n.calendarTitle = m.calendarTitle
                notes[m.id] = n
                write(n)
            }
        }
    }

    func search(_ query: String) -> [MeetingNote] {
        notes.values.filter { $0.matches(query) }.sorted { $0.start > $1.start }
    }

    // MARK: Persistenz & Sync

    nonisolated static func fileName(for id: String) -> String {
        let hash = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(32)) + ".json"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func write(_ n: MeetingNote) {
        let url = notesDir.appendingPathComponent(Self.fileName(for: n.id))
        do {
            let data = try Self.encoder.encode(n)
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
                do { try data.write(to: u, options: .atomic) } catch { writeError = error }
            }
            if let e = coordError ?? writeError { throw e }
            known[url.lastPathComponent] = Self.modDate(url)
        } catch {
            NSLog("Notiz konnte nicht gespeichert werden: \(error)")
        }
    }

    private func removeFile(for id: String) {
        let url = notesDir.appendingPathComponent(Self.fileName(for: id))
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: nil) { u in
            try? FileManager.default.removeItem(at: u)
        }
        known[url.lastPathComponent] = nil
    }

    /// Prüft den Ordner auf Änderungen anderer Geräte (Lesen im Hintergrund,
    /// weil iCloud Dateien dabei erst herunterladen kann).
    func syncFromDisk() {
        guard !scanning else { return }
        let dir = notesDir
        let current = Self.listing(dir)
        guard current != known else {
            // Anzeige höchstens minütlich auffrischen, sonst zeichnen alle Ansichten ständig neu
            if (lastSync ?? .distantPast).timeIntervalSinceNow < -60 { lastSync = Date() }
            return
        }
        scanning = true
        Task.detached(priority: .utility) {
            let result = Self.scan(dir)
            await MainActor.run {
                self.apply(result)
                self.scanning = false
            }
        }
    }

    struct ScanResult: Sendable {
        var files: [String: Date]
        var notes: [(file: String, note: MeetingNote)]
    }

    nonisolated private static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    nonisolated private static func listing(_ dir: URL) -> [String: Date] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        var result: [String: Date] = [:]
        for u in urls where u.pathExtension == "json" { result[u.lastPathComponent] = modDate(u) }
        return result
    }

    nonisolated private static func scan(_ dir: URL) -> ScanResult {
        let files = listing(dir)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var notes: [(String, MeetingNote)] = []
        for name in files.keys {
            let url = dir.appendingPathComponent(name)
            var data: Data?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in
                data = try? Data(contentsOf: u)
            }
            if let data, let n = try? decoder.decode(MeetingNote.self, from: data) {
                notes.append((name, n))
            }
        }
        return ScanResult(files: files, notes: notes.map { (file: $0.0, note: $0.1) })
    }

    private func apply(_ result: ScanResult) {
        known = result.files
        // Pro Notiz gewinnt die zuletzt geänderte Fassung
        var merged: [String: MeetingNote] = [:]
        for (_, n) in result.notes where (merged[n.id]?.updatedAt ?? .distantPast) < n.updatedAt {
            merged[n.id] = n
        }
        // Konfliktkopien von iCloud („… 2.json“) zusammenführen und entfernen
        for (file, n) in result.notes where file != Self.fileName(for: n.id) {
            let canonical = result.notes.first { $0.file == Self.fileName(for: n.id) }?.note
            if let winner = merged[n.id], canonical != winner { write(winner) }
            try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(file))
            known[file] = nil
        }
        if merged != notes { notes = merged }
        lastSync = Date()
    }

    /// Verschiebt den Datenordner der Vorgängerversion „MeetingNotes“ einmalig an den neuen Ort
    /// und übersetzt die Ordner- und Dateinamen.
    private static func migrateFolder(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            let renames = [("Notizen", "Notes"), ("Einstellungen.json", "Settings.json")]
            for (a, b) in renames where fm.fileExists(atPath: new.appendingPathComponent(a).path) {
                try fm.moveItem(at: new.appendingPathComponent(a), to: new.appendingPathComponent(b))
            }
            NSLog("note4meet: Daten von \(old.path) übernommen")
        } catch {
            NSLog("note4meet: Datenumzug fehlgeschlagen: \(error)")
        }
    }

    /// Übernimmt die frühere Einzeldatei notes.json (vor dem Sync) in den Sync-Ordner.
    private func migrateLegacyFile(in localDir: URL) {
        let legacy = localDir.appendingPathComponent("notes.json")
        guard let data = try? Data(contentsOf: legacy) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([MeetingNote].self, from: data) else { return }
        for n in list where (notes[n.id]?.updatedAt ?? .distantPast) < n.updatedAt {
            notes[n.id] = n
            write(n)
        }
        try? FileManager.default.moveItem(at: legacy, to: localDir.appendingPathComponent("notes.json.migriert"))
    }

    private func jsonData() throws -> Data {
        try Self.encoder.encode(notes.values.sorted { $0.start < $1.start })
    }

    // MARK: Export

    func markdown() -> String {
        var out = "# " + L("Meeting-Notizen") + "\n\n" + L("Exportiert am %@, %@", Fmt.dayShort(Date()), Fmt.time(Date())) + "\n"
        for n in notes.values.sorted(by: { $0.start > $1.start }) {
            out += "\n---\n\n" + Self.markdown(n, level: 2)
        }
        return out
    }

    /// Eine Notiz als Markdown; `level` ist die Überschriftenebene des Titels.
    static func markdown(_ n: MeetingNote, level: Int = 1) -> String {
        let h = String(repeating: "#", count: level)
        var out = "\(h) \(n.title)\n\n"
        out += "*\(Fmt.dayShort(n.start)), \(Fmt.time(n.start))–\(Fmt.time(n.end)) · \(n.calendarTitle)*\n"
        for s in orderedBlocks(n) {
            out += "\n\(h)# \(L(s.label))\n\n"
            out += s.agenda.map { items in
                items.map { "- [\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n")
            } ?? Bullets.markdown(s.text)
            out += "\n"
        }
        if !n.attachments.isEmpty {
            out += "\n\(h)# \(L("Dateien & E-Mails"))\n\n"
            out += n.attachments.map { a in
                let link = a.exportLink.replacingOccurrences(of: " ", with: "%20")
                return "- [\(a.title)](\(link))"
            }.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// Eine Notiz als schlichter Text.
    static func plainText(_ n: MeetingNote) -> String {
        var out = "\(n.title)\n" + String(repeating: "=", count: max(n.title.count, 3)) + "\n"
        out += "\(Fmt.dayShort(n.start)), \(Fmt.time(n.start))–\(Fmt.time(n.end)) · \(n.calendarTitle)\n"
        for s in orderedBlocks(n) {
            out += "\n\(L(s.label).uppercased())\n"
            out += s.agenda.map { items in
                items.map { "[\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n")
            } ?? Bullets.display(s.text)
            out += "\n"
        }
        if !n.attachments.isEmpty {
            out += "\n\(L("Dateien & E-Mails").uppercased())\n"
            out += n.attachments.map { "\($0.title): \($0.exportLink)" }.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// Ziel, Agenda, dann die übrigen Felder – dieselbe Reihenfolge wie im Briefing.
    private static func orderedBlocks(_ n: MeetingNote) -> [(label: String, text: String, agenda: [AgendaItem]?)] {
        let sections = n.filledSections
        var blocks = sections.filter { $0.label == "Ziel" }.map { ($0.label, $0.text, nil as [AgendaItem]?) }
        if !n.filledAgenda.isEmpty { blocks.append(("Agenda", "", n.filledAgenda)) }
        blocks += sections.filter { $0.label != "Ziel" }.map { ($0.label, $0.text, nil as [AgendaItem]?) }
        if !n.filledNextSteps.isEmpty { blocks.append(("Nächste Schritte", "", n.filledNextSteps)) }
        if !n.filledProjects.isEmpty { blocks.append(("Projekte", "", n.filledProjects)) }
        return blocks.map { (label: $0.0, text: $0.1, agenda: $0.2) }
    }

    /// Exportiert eine einzelne Notiz als .md oder .txt.
    func export(_ n: MeetingNote, asMarkdown: Bool) {
        let ext = asMarkdown ? "md" : "txt"
        let date = n.start.formatted(.iso8601.year().month().day())
        let safeTitle = n.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|").union(.newlines))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let content = asMarkdown ? Self.markdown(n) : Self.plainText(n)
        save(Data(content.utf8), name: "\(date) \(safeTitle).\(ext)",
             type: UTType(filenameExtension: ext) ?? .plainText)
    }

    private func save(_ data: Data, name: String, type: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func export(asJSON: Bool) {
        let stamp = Date().formatted(.iso8601.year().month().day())
        do {
            let data = asJSON ? try jsonData() : Data(markdown().utf8)
            save(data, name: "note4meet-\(stamp).\(asJSON ? "json" : "md")",
                 type: asJSON ? .json : UTType(filenameExtension: "md") ?? .plainText)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
