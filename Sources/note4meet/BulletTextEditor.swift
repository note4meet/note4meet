import AppKit
import SwiftUI

/// Aufzählungslogik auf reinem Text: Ein Punkt ist eine Zeile der Form
/// „<Tabs>• Text“. Die Anzahl der Tabs ist die Ebene (• ◦ ▪).
enum Bullets {
    static let symbols: [Character] = ["•", "◦", "▪"]

    static func symbol(level: Int) -> Character { symbols[level % symbols.count] }

    /// Ebene und Länge des Präfixes, falls die Zeile ein Aufzählungspunkt ist.
    static func parse(_ line: Substring) -> (level: Int, prefixLength: Int)? {
        var tabs = 0
        var i = line.startIndex
        while i < line.endIndex, line[i] == "\t" { tabs += 1; i = line.index(after: i) }
        guard i < line.endIndex, symbols.contains(line[i]) else { return nil }
        let afterSymbol = line.index(after: i)
        guard afterSymbol < line.endIndex, line[afterSymbol] == " " else {
            // „•“ am Zeilenende ohne Leerzeichen zählt auch
            return afterSymbol == line.endIndex ? (tabs, tabs + 1) : nil
        }
        return (tabs, tabs + 2)
    }

    static func prefix(level: Int) -> String {
        String(repeating: "\t", count: level) + String(symbol(level: level)) + " "
    }

    /// Für die Anzeige im Briefing: Tabs als Leerzeichen.
    static func display(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let b = parse(Substring(line)) else { return line }
            return String(repeating: "    ", count: b.level) + line.drop(while: { $0 == "\t" })
        }.joined(separator: "\n")
    }

    /// Für den Markdown-Export: echte Markdown-Listen.
    static func markdown(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard let b = parse(Substring(line)) else { return line }
            return String(repeating: "  ", count: b.level) + "- " + line.dropFirst(b.prefixLength)
        }.joined(separator: "\n")
    }
}

/// Steuert einen BulletTextEditor von außen (Knopf „Aufzählung“).
@MainActor
final class BulletEditorController: ObservableObject {
    weak var textView: BulletTextView?
    func toggleBullets() {
        textView?.window?.makeFirstResponder(textView)
        textView?.toggleBullets()
    }
}

/// Mehrzeiliges Textfeld mit Aufzählungen wie in TextEdit/Pages.
/// Wächst mit dem Inhalt, gespeichert wird reiner Text.
struct BulletTextEditor: NSViewRepresentable {
    @Binding var text: String
    var controller: BulletEditorController?

    func makeNSView(context: Context) -> BulletTextView {
        let tv = BulletTextView()
        tv.delegate = context.coordinator
        tv.string = text
        tv.restyle()
        controller?.textView = tv
        return tv
    }

    func updateNSView(_ tv: BulletTextView, context: Context) {
        context.coordinator.parent = self
        controller?.textView = tv
        if tv.string != text {
            tv.string = text
            tv.restyle()
            tv.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: BulletTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        return CGSize(width: width, height: tv.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BulletTextEditor
        init(_ parent: BulletTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? BulletTextView else { return }
            tv.restyle()
            tv.invalidateIntrinsicContentSize()
            parent.text = tv.string
        }
    }
}

final class BulletTextView: NSTextView {
    private let indentStep: CGFloat = 18

    convenience init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        clipsToBounds = true
        textContainerInset = NSSize(width: 0, height: 2)
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .labelColor
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        typingAttributes = baseAttributes(level: nil)
    }

    /// Höhe für eine Breite, gemessen an einer Kopie des Textes. SwiftUI fragt beim
    /// Layout mehrere Probebreiten ab; das echte Textfeld darf davon nichts merken.
    func height(forWidth width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: textStorage ?? NSAttributedString())
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: max(width, 50), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var used = layout.usedRect(for: container).height
        // Leere letzte Zeile nach einem Zeilenumbruch mitzählen
        if layout.extraLineFragmentRect.height > 0 {
            used = max(used, layout.extraLineFragmentRect.maxY)
        }
        let line = (font ?? .systemFont(ofSize: 13)).boundingRectForFont.height
        return ceil(max(used, line)) + textContainerInset.height * 2
    }

    // Der Textbereich folgt immer der tatsächlichen Breite des Feldes
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.size = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
    }

    // MARK: Darstellung (hängender Einzug)

    private func baseAttributes(level: Int?) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 2
        if let level {
            let bulletWidth = ("• " as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 13)]).width
            p.tabStops = (1...8).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * indentStep) }
            p.defaultTabInterval = indentStep
            p.firstLineHeadIndent = 0
            p.headIndent = CGFloat(level) * indentStep + bulletWidth
        }
        return [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: p]
    }

    func restyle() {
        guard let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        (storage.string as NSString).enumerateSubstrings(in: full, options: .byParagraphs) { para, _, enclosing, _ in
            let level = para.flatMap { Bullets.parse(Substring($0))?.level }
            storage.setAttributes(self.baseAttributes(level: level), range: enclosing)
        }
        storage.endEditing()
        typingAttributes = baseAttributes(level: Bullets.parse(currentLine().text)?.level)
    }

    // MARK: Zeilenhelfer

    private func currentLine() -> (range: NSRange, text: Substring) {
        let ns = string as NSString
        let range = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var text = ns.substring(with: range)
        if text.hasSuffix("\n") { text.removeLast() }
        return (NSRange(location: range.location, length: (text as NSString).length), Substring(text))
    }

    private func replace(_ range: NSRange, with s: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: s) else { return }
        textStorage?.replaceCharacters(in: range, with: s)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    // MARK: Tastatur

    override func insertNewline(_ sender: Any?) {
        let line = currentLine()
        guard let b = Bullets.parse(line.text) else { return super.insertNewline(sender) }
        let content = line.text.dropFirst(b.prefixLength).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            // Leerer Punkt: Aufzählung beenden (bzw. eine Ebene ausrücken)
            if b.level > 0 {
                setLevel(b.level - 1, line: line)
            } else {
                replace(line.range, with: "", select: NSRange(location: line.range.location, length: 0))
            }
            return
        }
        insertText("\n" + Bullets.prefix(level: b.level), replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        let line = currentLine()
        if let b = Bullets.parse(line.text) { setLevel(min(b.level + 1, 6), line: line) }
        else { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        let line = currentLine()
        if let b = Bullets.parse(line.text) {
            if b.level > 0 { setLevel(b.level - 1, line: line) }
        } else {
            super.insertBacktab(sender)
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        // „- “ oder „* “ am Zeilenanfang wird zu „• “
        guard (string as? String) == " " else { return }
        let line = currentLine()
        let caret = selectedRange().location - line.range.location
        let typed = String(line.text.prefix(caret))
        let tabs = typed.prefix(while: { $0 == "\t" }).count
        let rest = typed.dropFirst(tabs)
        if rest == "- " || rest == "* " {
            let r = NSRange(location: line.range.location, length: (typed as NSString).length)
            let p = Bullets.prefix(level: tabs)
            replace(r, with: p, select: NSRange(location: line.range.location + (p as NSString).length, length: 0))
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "l" {
            toggleBullets()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func setLevel(_ level: Int, line: (range: NSRange, text: Substring)) {
        guard let b = Bullets.parse(line.text) else { return }
        let caretOffset = selectedRange().location - line.range.location - b.prefixLength
        let newPrefix = Bullets.prefix(level: level)
        let newLine = newPrefix + line.text.dropFirst(b.prefixLength)
        let caret = line.range.location + (newPrefix as NSString).length + max(caretOffset, 0)
        replace(line.range, with: newLine, select: NSRange(location: caret, length: 0))
    }

    /// Macht die markierten Zeilen zu Aufzählungspunkten oder entfernt die Punkte wieder.
    func toggleBullets() {
        let ns = string as NSString
        let sel = selectedRange()
        let block = ns.lineRange(for: sel)
        var text = ns.substring(with: block)
        let trailingNewline = text.hasSuffix("\n")
        if trailingNewline { text.removeLast() }
        let lines = text.components(separatedBy: "\n")
        let allBullets = lines.allSatisfy { Bullets.parse(Substring($0)) != nil || $0.isEmpty }
            && lines.contains { Bullets.parse(Substring($0)) != nil }
        let converted = lines.map { line -> String in
            if allBullets {
                guard let b = Bullets.parse(Substring(line)) else { return line }
                return String(line.dropFirst(b.prefixLength))
            }
            if Bullets.parse(Substring(line)) != nil { return line }
            return Bullets.prefix(level: 0) + line
        }
        let result = converted.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let endOfBlock = block.location + (result as NSString).length - (trailingNewline ? 1 : 0)
        replace(block, with: result, select: NSRange(location: endOfBlock, length: 0))
    }
}
