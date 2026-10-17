import AppKit
import SwiftUI

/// Schreibt Diagnosezeilen ins Systemprotokoll und – wenn eingeschaltet
/// (`defaults write io.github.note4meet debugLog -bool true`) – nach ~/Library/Logs/note4meet.log.
enum DebugLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/note4meet.log")

    static func write(_ message: String) {
        NSLog("note4meet \(message)")
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// Hülle um den gesamten Inhalt des Hauptfensters, die alle Drops annimmt:
/// Dateien aus dem Finder, Links und E-Mails aus Apple Mail (Datei-Zusage .eml).
/// Ziel ist der Termin unter der Maus, sonst der gerade geöffnete Termin.
final class DropContainerView: NSView {
    weak var windows: WindowManager?

    static let mailTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeMessageTransfer"),
        NSPasteboard.PasteboardType("com.apple.mail.PasteboardTypeAutomator"),
    ]

    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string] + mailTypes
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    init(content: NSView) {
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Gleiche Koordinaten wie SwiftUIs .global (Ursprung oben links)
    override var isFlipped: Bool { true }

    private func point(_ info: NSDraggingInfo) -> CGPoint {
        convert(info.draggingLocation, from: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DebugLog.write("Drag hinein, Typen: \(sender.draggingPasteboard.types?.map(\.rawValue) ?? [])")
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let windows else { return [] }
        let target = windows.dropTarget(at: point(sender))
        if windows.dropTargetID != target?.id { windows.dropTargetID = target?.id }
        return target == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        windows?.dropTargetID = nil
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        windows?.dropTargetID = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let windows, let meeting = windows.dropTarget(at: point(sender)) else {
            DebugLog.write("Drop ohne Ziel (kein Termin unter der Maus, keiner geöffnet)")
            return false
        }
        windows.dropTargetID = nil
        let pb = sender.draggingPasteboard
        let types = pb.types ?? []
        DebugLog.write("Drop auf „\(meeting.title)“, Typen: \(types.map(\.rawValue))")

        let deliver: @MainActor ([Attachment]) -> Void = { items in
            DebugLog.write("Erkannt: \(items.map { "\($0.kind.rawValue): \($0.title)" })")
            guard !items.isEmpty else { NSSound.beep(); return }
            windows.app?.store.addAttachments(items, to: meeting)
            windows.selection = meeting.id
        }

        // 1. E-Mails aus Apple Mail
        if types.contains(where: Self.mailTypes.contains) {
            for t in Self.mailTypes {
                if let plist = pb.propertyList(forType: t) {
                    DebugLog.write("\(t.rawValue): \(String(describing: plist).prefix(1200))")
                }
            }
            // Mail liefert einen message:-Link; Betreffzeilen stehen in den Mail-Daten
            if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
                let subjects = (pb.propertyList(forType: Self.mailTypes[1]) as? [[String: Any]])?
                    .compactMap { $0["subject"] as? String } ?? []
                let urlName = pb.string(forType: NSPasteboard.PasteboardType("public.url-name"))
                let links = urls.enumerated().compactMap { i, url -> Attachment? in
                    let name = subjects.count == urls.count ? subjects[i] : (urls.count == 1 ? urlName ?? subjects.first : nil)
                    return AttachmentDrop.fromURL(url, name: name?.isEmpty == false ? name : nil)
                }.filter { $0.kind == .mail }
                if !links.isEmpty { deliver(links); return true }
            }
            let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
            guard !receivers.isEmpty else {
                DebugLog.write("Mail-Drop ohne Datei-Zusage")
                return false
            }
            MailPromise.receive(receivers, completion: deliver)
            return true
        }

        // 2. Dateien aus dem Finder
        if let files = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            deliver(files.map(Attachment.file))
            return true
        }

        // 3. Links (Safari-Adressleiste, Links aus anderen Apps)
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            let name = pb.string(forType: NSPasteboard.PasteboardType("public.url-name"))
            deliver(urls.compactMap { AttachmentDrop.fromURL($0, name: urls.count == 1 ? name : nil) })
            return true
        }

        // 4. Text, der eine Adresse ist
        if let s = pb.string(forType: .string),
           let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            deliver([AttachmentDrop.fromURL(url, name: nil)].compactMap { $0 })
            return true
        }

        DebugLog.write("Nichts Verwertbares gefunden")
        return false
    }
}

/// Lässt Mail die zugesagten .eml-Dateien in einen temporären Ordner schreiben
/// und macht daraus message:-Links.
enum MailPromise {
    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    static func receive(_ receivers: [NSFilePromiseReceiver], completion: @escaping @MainActor ([Attachment]) -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("note4meet-Mail-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let group = DispatchGroup()
        let lock = NSLock()
        var results: [Attachment] = []

        for r in receivers {
            DebugLog.write("Datei-Zusage: Typen \(r.fileTypes), Namen \(r.fileNames)")
            // Der Block wird pro Datei aufgerufen; die Anzahl ist vorab nicht sicher bekannt
            let expected = max(r.fileNames.count, 1)
            for _ in 0..<expected { group.enter() }
            var calls = 0
            r.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: queue) { url, error in
                defer {
                    lock.lock(); calls += 1; let c = calls; lock.unlock()
                    if c <= expected { group.leave() }
                }
                if let error { DebugLog.write("Datei-Zusage Fehler: \(error)"); return }
                if let a = attachment(fromFile: url) {
                    lock.lock(); results.append(a); lock.unlock()
                }
            }
        }
        // Genau einmal abschließen: wenn alle Dateien da sind oder spätestens nach 20 Sekunden
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            lock.lock(); let found = results; lock.unlock()
            try? FileManager.default.removeItem(at: dir)
            MainActor.assumeIsolated { completion(found) }
        }
        group.notify(queue: .main, execute: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: finish)
    }

    private static func attachment(fromFile url: URL) -> Attachment? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 128 * 1024)) ?? Data()
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        guard let headers = MailHeaders(head), let id = headers.messageID else {
            DebugLog.write("Keine Message-ID in \(url.lastPathComponent)")
            return nil
        }
        return Attachment(kind: .mail, title: headers.subject ?? fallbackTitle, link: MailHeaders.messageURL(for: id))
    }
}

/// Merkt sich die Position eines Termins im Fenster, damit Drops dem richtigen
/// Termin zugeordnet werden. Löst kein Neuzeichnen aus.
struct DropFrameReporter: View {
    let meeting: Meeting
    @EnvironmentObject private var windows: WindowManager

    var body: some View {
        GeometryReader { g in
            let frame = g.frame(in: .global)
            Color.clear
                .onAppear { windows.dropFrames[meeting.id] = (frame, meeting) }
                .onChange(of: frame) { _, f in windows.dropFrames[meeting.id] = (f, meeting) }
                .onDisappear { windows.dropFrames[meeting.id] = nil }
        }
    }
}
