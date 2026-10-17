import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let calendar = CalendarService()
    let store = NotesStore()
    let windows = WindowManager()
    private(set) lazy var scheduler = AlertScheduler(calendar: calendar, store: store, windows: windows)
    private(set) lazy var settingsSync = SettingsSync(calendar: calendar, folder: store.folderURL)

    init() {
        windows.app = self
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.settingsSync.start()
        Task {
            let firstLaunch = !UserDefaults.standard.bool(forKey: "didLaunchBefore")
            UserDefaults.standard.set(true, forKey: "didLaunchBefore")
            if firstLaunch {
                // Willkommensfenster fragt selbst nach dem Kalenderzugriff
                state.windows.showWelcome()
            } else {
                // z. B. nach dem Umstieg von „MeetingNotes“: neue App-Kennung, Zugriff noch offen
                if state.calendar.status == .notDetermined {
                    await state.calendar.requestAccess()
                }
                if !state.calendar.hasAccess || CommandLine.arguments.contains("--show-main") {
                    state.windows.showMain()
                }
            }
            state.scheduler.start()
            // Nur für Tests: `--test-briefing` zeigt das Briefing der zuletzt bearbeiteten Notiz
            if CommandLine.arguments.contains("--test-briefing"),
               let n = state.store.notes.values.max(by: { $0.updatedAt < $1.updatedAt }) {
                state.windows.showBriefing(meeting: state.calendar.cachedMeeting(n.id) ?? Meeting(note: n))
            }
        }
        // Alle 5 Minuten die Übersicht auffrischen
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state.calendar.reloadUpcoming() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct Note4MeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObjects(delegate.state)
        } label: {
            Image(systemName: "calendar.badge.clock")
        }
        .menuBarExtraStyle(.window)
    }
}
