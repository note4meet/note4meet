import Foundation

/// Gleicht Ausblende-Begriffe, Vorlaufzeit und „Sa & So ausblenden“ über
/// Einstellungen.json im Sync-Ordner ab. Die Kalenderauswahl bleibt pro Mac,
/// weil die Kalender-IDs auf jedem Gerät anders sind.
@MainActor
final class SettingsSync {
    struct Snapshot: Codable, Equatable {
        var hiddenTitles: [String]
        var leadMinutes: Int
        var hideWeekends: Bool
    }

    private let calendar: CalendarService
    private let fileURL: URL
    private var lastKnown: Snapshot?
    private var fileDate: Date?
    private var applying = false
    private var timer: Timer?

    init(calendar: CalendarService, folder: URL) {
        self.calendar = calendar
        fileURL = folder.appendingPathComponent("Settings.json")
    }

    func start() {
        if let remote = read() {
            applyRemote(remote)
        } else {
            writeIfChanged()
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.writeIfChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollRemote() }
        }
    }

    private var local: Snapshot {
        let d = UserDefaults.standard
        return Snapshot(
            hiddenTitles: calendar.hiddenTitles,
            leadMinutes: d.object(forKey: AlertScheduler.leadMinutesKey) as? Int ?? 2,
            hideWeekends: d.bool(forKey: WeekView.hideWeekendsKey)
        )
    }

    private func writeIfChanged() {
        guard !applying else { return }
        let snap = local
        guard snap != lastKnown else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(snap) else { return }
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: nil) { u in
            try? data.write(to: u, options: .atomic)
        }
        lastKnown = snap
        fileDate = modDate()
    }

    private func pollRemote() {
        let date = modDate()
        guard date != fileDate, let remote = read() else { return }
        applyRemote(remote)
    }

    private func read() -> Snapshot? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: nil) { u in
            data = try? Data(contentsOf: u)
        }
        fileDate = modDate()
        return data.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    private func applyRemote(_ remote: Snapshot) {
        lastKnown = remote
        guard remote != local else { return }
        applying = true
        let d = UserDefaults.standard
        d.set(remote.leadMinutes, forKey: AlertScheduler.leadMinutesKey)
        d.set(remote.hideWeekends, forKey: WeekView.hideWeekendsKey)
        if calendar.hiddenTitles != remote.hiddenTitles { calendar.hiddenTitles = remote.hiddenTitles }
        applying = false
    }

    private func modDate() -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
