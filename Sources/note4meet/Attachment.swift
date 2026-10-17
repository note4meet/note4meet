import AppKit
import UniformTypeIdentifiers

/// Verweis auf eine Datei, eine E-Mail in Apple Mail oder eine Webseite.
/// Dateien werden nicht kopiert, sondern nur verlinkt.
struct Attachment: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable { case file, mail, web }

    var id = UUID()
    var kind: Kind
    var title: String
    /// Datei: absoluter Pfad · Mail: message:-URL · Web: http(s)-URL
    var link: String
    /// Datei: Pfad relativ zu iCloud Drive, damit auch andere Macs sie finden
    var iCloudPath: String?
    /// Datei: macOS-Lesezeichen, findet die Datei auch nach Umbenennen/Verschieben
    var bookmark: Data?
    var addedAt = Date()

    static let iCloudRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)

    static func file(_ url: URL) -> Attachment {
        let path = url.standardizedFileURL.path
        let root = iCloudRoot.path + "/"
        return Attachment(
            kind: .file,
            title: url.lastPathComponent,
            link: path,
            iCloudPath: path.hasPrefix(root) ? String(path.dropFirst(root.count)) : nil,
            bookmark: try? url.bookmarkData()
        )
    }

    /// Die Datei auf diesem Mac: erst über das Lesezeichen, dann über iCloud Drive, dann über den Pfad.
    var resolvedFileURL: URL? {
        guard kind == .file else { return nil }
        let fm = FileManager.default
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale),
               fm.fileExists(atPath: url.path) {
                return url
            }
        }
        if let iCloudPath {
            let url = Self.iCloudRoot.appendingPathComponent(iCloudPath)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return fm.fileExists(atPath: link) ? URL(fileURLWithPath: link) : nil
    }

    var openURL: URL? {
        switch kind {
        case .file: return resolvedFileURL
        case .mail, .web: return URL(string: link)
        }
    }

    var isAvailable: Bool { openURL != nil }

    var subtitle: String {
        switch kind {
        case .file:
            guard let url = resolvedFileURL else { return L("Nicht auf diesem Mac verfügbar") }
            return url.deletingLastPathComponent().path
                .replacingOccurrences(of: Self.iCloudRoot.path, with: "iCloud Drive")
                .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        case .mail: return L("E-Mail in Apple Mail")
        case .web: return URL(string: link)?.host ?? link
        }
    }

    var symbol: String {
        switch kind {
        case .file: return "doc"
        case .mail: return "envelope"
        case .web: return "globe"
        }
    }

    /// Für Datei-Anhänge das echte Finder-Symbol der Datei.
    var fileIcon: NSImage? {
        resolvedFileURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func open() {
        guard let url = openURL else { NSSound.beep(); return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder() {
        guard let url = resolvedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Für den Export: anklickbarer Link.
    var exportLink: String {
        switch kind {
        case .file: return (resolvedFileURL ?? URL(fileURLWithPath: link)).absoluteString
        case .mail, .web: return link
        }
    }
}

// MARK: - Links aus Drops

enum AttachmentDrop {
    /// Macht aus einer URL einen Anhang: Datei, E-Mail (message:) oder Webseite.
    static func fromURL(_ url: URL, name: String?) -> Attachment? {
        switch url.scheme?.lowercased() {
        case "file":
            return .file(url)
        case "message":
            return Attachment(kind: .mail, title: name ?? L("E-Mail"), link: url.absoluteString)
        case "http", "https":
            return Attachment(kind: .web, title: name ?? url.host ?? url.absoluteString, link: url.absoluteString)
        default:
            return nil
        }
    }
}

/// Minimaler Parser für die Kopfzeilen einer E-Mail (RFC 5322).
struct MailHeaders {
    var messageID: String?
    var subject: String?

    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let headerPart = text.components(separatedBy: "\r\n\r\n").first.flatMap {
            $0.contains("\n\n") ? $0.components(separatedBy: "\n\n").first : $0
        } ?? text
        // Gefaltete Zeilen (beginnen mit Leerraum) zusammenführen
        var lines: [String] = []
        for raw in headerPart.components(separatedBy: .newlines) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += " " + raw.trimmingCharacters(in: .whitespaces)
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "message-id", messageID == nil {
                messageID = value.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            } else if name == "subject", subject == nil {
                subject = Self.decodeEncodedWords(value)
            }
        }
    }

    static func messageURL(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~!$&'()*+,;=:@"))
        return "message:%3C" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id) + "%3E"
    }

    /// Dekodiert MIME-Wörter wie =?UTF-8?B?...?= und =?ISO-8859-1?Q?...?=
    static func decodeEncodedWords(_ s: String) -> String {
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = s
        // Leerraum zwischen zwei kodierten Wörtern entfällt
        result = result.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        let ns = result as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let charset = ns.substring(with: m.range(at: 1))
            let mode = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))
            let enc = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding(charset as CFString))
            )
            var bytes: Data?
            if mode == "B" {
                bytes = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            } else {
                var d = Data()
                var chars = Array(payload.replacingOccurrences(of: "_", with: " ").utf8)[...]
                while let c = chars.popFirst() {
                    if c == UInt8(ascii: "="), chars.count >= 2,
                       let b = UInt8(String(bytes: chars.prefix(2), encoding: .ascii) ?? "", radix: 16) {
                        d.append(b)
                        chars = chars.dropFirst(2)
                    } else {
                        d.append(c)
                    }
                }
                bytes = d
            }
            out += bytes.flatMap { String(data: $0, encoding: enc) } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
