import AppKit
import SwiftUI

/// Öffnet die Fenster der App. Als Menüleisten-App ohne Dock-Symbol werden
/// Fenster direkt über AppKit verwaltet.
@MainActor
final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    weak var app: AppState?

    /// Auswahl im Hauptfenster (Notiz-Schlüssel).
    @Published var selection: String?
    /// Termin, über dem gerade etwas gezogen wird (zur Hervorhebung).
    @Published var dropTargetID: String?
    /// Position der sichtbaren Termine in Fensterkoordinaten, für Drops.
    var dropFrames: [String: (frame: CGRect, meeting: Meeting)] = [:]

    /// Termin unter dem Punkt; sonst der gerade geöffnete Termin.
    func dropTarget(at point: CGPoint) -> Meeting? {
        let hits = dropFrames.values.filter { $0.frame.contains(point) }
        if let hit = hits.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            return hit.meeting
        }
        guard let id = selection, let app else { return nil }
        return app.calendar.cachedMeeting(id)
            ?? app.calendar.upcoming.first { $0.id == id }
            ?? app.store.note(for: id).map(Meeting.init(note:))
    }

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var briefings: [String: NSPanel] = [:]

    // MARK: Hauptfenster

    func showMain(select id: String? = nil) {
        guard let app else { return }
        if let id { selection = id }
        if mainWindow == nil {
            let view = MainView().environmentObjects(app)
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1320, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "note4meet"
            // SwiftUI-Inhalt in einer Hülle, die alle Drops (Dateien, Links, Mails) annimmt
            let hosting = NSHostingView(rootView: view)
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let container = DropContainerView(content: hosting)
            container.windows = self
            w.contentView = container
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                DebugLog.write("Fenster offen. Toolbar: \(w.toolbar != nil), SwiftUI-Drag-Typen: \(hosting.registeredDraggedTypes.map(\.rawValue)), Hülle: \(container.registeredDraggedTypes.count) Typen")
            }
            w.setContentSize(NSSize(width: 1320, height: 820))
            w.minSize = NSSize(width: 860, height: 520)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("note4meetMainWindow")
            if !w.setFrameUsingName("note4meetMainWindow") { w.center() }
            w.delegate = self
            mainWindow = w
        }
        bringToFront(mainWindow!)
    }

    private var welcomeWindow: NSWindow?

    func showWelcome() {
        guard let app else { return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "note4meet"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: WelcomeView { [weak self] in
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
            self?.showMain()
        }.environmentObjects(app))
        w.center()
        welcomeWindow = w
        bringToFront(w)
    }

    func showSettings() {
        guard let app else { return }
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = L("note4meet – Einstellungen")
            w.contentViewController = NSHostingController(rootView: SettingsView().environmentObjects(app))
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            settingsWindow = w
        }
        bringToFront(settingsWindow!)
    }

    // MARK: Briefing-Meldung

    func showBriefing(meeting: Meeting) {
        guard let app else { return }
        if let existing = briefings[meeting.id] {
            if existing.isVisible && existing.frame.height > 50 {
                bringToFront(existing)
                return
            }
            existing.close()
            briefings[meeting.id] = nil
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = L("Meeting-Briefing")
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let id = meeting.id
        let view = BriefingView(meeting: meeting) { [weak self] action in
            self?.closeBriefing(id)
            if action == .edit { self?.showMain(select: id) }
        }
        .environmentObjects(app)
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        // Beim Zuweisen übernimmt das Panel die Anfangsgröße des Views (0 × 0),
        // daher die Größe ausdrücklich aus dem Inhalt berechnen.
        let probe = NSHostingView(rootView: BriefingView(meeting: meeting, measuring: true) { _ in }.environmentObjects(app))
        let natural = probe.fittingSize.height
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 80
        panel.setContentSize(NSSize(width: 520, height: min(max(natural, 240), maxHeight)))
        panel.minSize = NSSize(width: 420, height: 240)

        // Oben rechts auf dem aktiven Bildschirm, versetzt bei mehreren Meldungen
        if let screen = NSScreen.main?.visibleFrame {
            let size = panel.frame.size
            let offset = CGFloat(briefings.count) * 28
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24 - offset,
                                         y: screen.maxY - size.height - 24 - offset))
        }
        briefings[id] = panel
        NSSound(named: "Glass")?.play()
        bringToFront(panel)
    }

    func closeBriefing(_ id: String) {
        briefings[id]?.close()
        briefings[id] = nil
    }

    // MARK: Helfer

    private func bringToFront(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if let key = briefings.first(where: { $0.value === w })?.key {
            briefings[key] = nil
        }
    }
}

extension View {
    @MainActor
    func environmentObjects(_ app: AppState) -> some View {
        self
            .environmentObject(app)
            .environmentObject(app.calendar)
            .environmentObject(app.store)
            .environmentObject(app.windows)
    }
}
