// SnapText — copy text from anything on your screen.
// Press ⇧⌘2, drag over some text (a slide, a video, a photo, a PDF that won't let you copy),
// and the words are on your clipboard. Uses the Mac's built-in text recognition — works offline.

import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import Vision
import ServiceManagement

// MARK: - Color helpers

extension Color {
    /// "RRGGBB" or "RRGGBBAA" (with or without #)
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0x000000FF
        self.init(.sRGB,
                  red: Double((v >> 24) & 0xFF) / 255,
                  green: Double((v >> 16) & 0xFF) / 255,
                  blue: Double((v >> 8) & 0xFF) / 255,
                  opacity: Double(v & 0xFF) / 255)
    }

    var hex: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        let a = Int((ns.alphaComponent * 255).rounded())
        return String(format: "%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - Settings

enum HotkeyChoice: String, CaseIterable {
    case shiftCmd2, ctrlShiftCmd2, optShiftCmd2, optShiftT, off

    var label: String {
        switch self {
        case .shiftCmd2: return "⇧⌘2"
        case .ctrlShiftCmd2: return "⌃⇧⌘2"
        case .optShiftCmd2: return "⌥⇧⌘2"
        case .optShiftT: return "⌥⇧T"
        case .off: return "Off"
        }
    }

    /// (Carbon key code, Carbon modifiers)
    var key: (UInt32, UInt32)? {
        switch self {
        case .shiftCmd2: return (UInt32(kVK_ANSI_2), UInt32(shiftKey | cmdKey))
        case .ctrlShiftCmd2: return (UInt32(kVK_ANSI_2), UInt32(controlKey | shiftKey | cmdKey))
        case .optShiftCmd2: return (UInt32(kVK_ANSI_2), UInt32(optionKey | shiftKey | cmdKey))
        case .optShiftT: return (UInt32(kVK_ANSI_T), UInt32(optionKey | shiftKey))
        case .off: return nil
        }
    }
}

enum LanguageChoice: String, CaseIterable {
    case auto, zhHant, zhHans, english, japanese, korean

    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .zhHant: return "Traditional Chinese + English"
        case .zhHans: return "Simplified Chinese + English"
        case .english: return "English"
        case .japanese: return "Japanese + English"
        case .korean: return "Korean + English"
        }
    }

    var codes: [String] {
        switch self {
        case .auto: return ["zh-Hant", "zh-Hans", "en-US", "ja-JP", "ko-KR"]
        case .zhHant: return ["zh-Hant", "en-US"]
        case .zhHans: return ["zh-Hans", "en-US"]
        case .english: return ["en-US"]
        case .japanese: return ["ja-JP", "en-US"]
        case .korean: return ["ko-KR", "en-US"]
        }
    }
}

enum LineMode: String, CaseIterable {
    case keep, join
    var label: String { self == .keep ? "Keep line breaks" : "Join into paragraphs" }
}

enum PopupTheme: String, CaseIterable {
    case glass, light, dark
    var label: String { rawValue.capitalized }
}

enum PopupPosition: String, CaseIterable {
    case top, cursor, bottom
    var label: String {
        switch self {
        case .top: return "Top"
        case .cursor: return "Near selection"
        case .bottom: return "Bottom"
        }
    }
}

enum FontChoice: String, CaseIterable {
    case system, rounded, mono, serif
    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .mono: return "Monospaced"
        case .serif: return "Serif"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .mono: return .monospaced
        case .serif: return .serif
        }
    }
}

final class AppSettings: ObservableObject {
    private static let d = UserDefaults.standard

    enum Default {
        static let hotkey = HotkeyChoice.shiftCmd2
        static let language = LanguageChoice.auto
        static let lineMode = LineMode.keep
        static let detectQR = true
        static let playSound = true
        static let showPopup = true
        static let popupSeconds = 3.5
        static let position = PopupPosition.top
        static let theme = PopupTheme.glass
        static let accentHex = "FF6FAEFF"
        static let font = FontChoice.rounded
        static let fontSize = 13.0
        static let historyCount = 10
    }

    @Published var hotkey: HotkeyChoice { didSet { save() } }
    @Published var language: LanguageChoice { didSet { save() } }
    @Published var lineMode: LineMode { didSet { save() } }
    @Published var detectQR: Bool { didSet { save() } }
    @Published var playSound: Bool { didSet { save() } }
    @Published var showPopup: Bool { didSet { save() } }
    @Published var popupSeconds: Double { didSet { save() } }
    @Published var position: PopupPosition { didSet { save() } }
    @Published var theme: PopupTheme { didSet { save() } }
    @Published var accentHex: String { didSet { save() } }
    @Published var font: FontChoice { didSet { save() } }
    @Published var fontSize: Double { didSet { save() } }
    @Published var historyCount: Int { didSet { save() } }

    init() {
        let d = AppSettings.d
        hotkey = HotkeyChoice(rawValue: d.string(forKey: "hotkey") ?? "") ?? Default.hotkey
        language = LanguageChoice(rawValue: d.string(forKey: "language") ?? "") ?? Default.language
        lineMode = LineMode(rawValue: d.string(forKey: "lineMode") ?? "") ?? Default.lineMode
        detectQR = d.object(forKey: "detectQR") as? Bool ?? Default.detectQR
        playSound = d.object(forKey: "playSound") as? Bool ?? Default.playSound
        showPopup = d.object(forKey: "showPopup") as? Bool ?? Default.showPopup
        popupSeconds = d.object(forKey: "popupSeconds") as? Double ?? Default.popupSeconds
        position = PopupPosition(rawValue: d.string(forKey: "position") ?? "") ?? Default.position
        theme = PopupTheme(rawValue: d.string(forKey: "theme") ?? "") ?? Default.theme
        accentHex = d.string(forKey: "accentHex") ?? Default.accentHex
        font = FontChoice(rawValue: d.string(forKey: "font") ?? "") ?? Default.font
        fontSize = d.object(forKey: "fontSize") as? Double ?? Default.fontSize
        historyCount = d.object(forKey: "historyCount") as? Int ?? Default.historyCount
    }

    private func save() {
        let d = AppSettings.d
        d.set(hotkey.rawValue, forKey: "hotkey")
        d.set(language.rawValue, forKey: "language")
        d.set(lineMode.rawValue, forKey: "lineMode")
        d.set(detectQR, forKey: "detectQR")
        d.set(playSound, forKey: "playSound")
        d.set(showPopup, forKey: "showPopup")
        d.set(popupSeconds, forKey: "popupSeconds")
        d.set(position.rawValue, forKey: "position")
        d.set(theme.rawValue, forKey: "theme")
        d.set(accentHex, forKey: "accentHex")
        d.set(font.rawValue, forKey: "font")
        d.set(fontSize, forKey: "fontSize")
        d.set(historyCount, forKey: "historyCount")
    }

    func reset() {
        hotkey = Default.hotkey
        language = Default.language
        lineMode = Default.lineMode
        detectQR = Default.detectQR
        playSound = Default.playSound
        showPopup = Default.showPopup
        popupSeconds = Default.popupSeconds
        position = Default.position
        theme = Default.theme
        accentHex = Default.accentHex
        font = Default.font
        fontSize = Default.fontSize
        historyCount = Default.historyCount
    }
}

// MARK: - Text recognition (runs off the main thread)

struct OCRLine: Sendable {
    var text: String
    var rect: CGRect      // Vision coordinates: 0…1, origin bottom-left
}

struct OCRResult: Sendable {
    var lines: [String]   // reading order, top to bottom
    var codes: [String]   // QR / barcode contents
    var isEmpty: Bool { lines.isEmpty && codes.isEmpty }
}

func isCJK(_ c: Character) -> Bool {
    guard let s = c.unicodeScalars.first?.value else { return false }
    return (0x3000...0x30FF).contains(s) || (0x3400...0x9FFF).contains(s) ||
           (0xAC00...0xD7AF).contains(s) || (0xFF00...0xFFEF).contains(s)
}

/// Joins two pieces of text with a space — or none between Chinese/Japanese/Korean characters.
func smartJoin(_ a: String, _ b: String) -> String {
    guard let last = a.last, let first = b.first else { return a + b }
    if last == "-" && first.isLetter && !isCJK(first) { return String(a.dropLast()) + b }   // re-join hyphenated words
    if isCJK(last) || isCJK(first) { return a + b }
    return a + " " + b
}

/// Vision gives text pieces in no guaranteed order; rebuild lines top-to-bottom, left-to-right.
func orderLines(_ pieces: [OCRLine]) -> [String] {
    var rows: [[OCRLine]] = []
    for p in pieces.sorted(by: { $0.rect.midY > $1.rect.midY }) {
        if let i = rows.firstIndex(where: { row in
            let r = row[0].rect
            return abs(r.midY - p.rect.midY) < min(r.height, p.rect.height) * 0.5
        }) {
            rows[i].append(p)
        } else {
            rows.append([p])
        }
    }
    return rows.map { row in
        row.sorted { $0.rect.minX < $1.rect.minX }.map(\.text).reduce("") { $0.isEmpty ? $1 : smartJoin($0, $1) }
    }
}

func recognizeText(in image: CGImage, languages: [String], automatic: Bool, detectCodes: Bool) -> OCRResult {
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    textRequest.usesLanguageCorrection = true
    let supported = (try? textRequest.supportedRecognitionLanguages()) ?? []
    let langs = languages.filter { supported.isEmpty || supported.contains($0) }
    if !langs.isEmpty { textRequest.recognitionLanguages = langs }
    if #available(macOS 13.0, *) { textRequest.automaticallyDetectsLanguage = automatic }

    let codeRequest = VNDetectBarcodesRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform(detectCodes ? [textRequest, codeRequest] : [textRequest])

    let pieces = (textRequest.results ?? []).compactMap { obs -> OCRLine? in
        guard let s = obs.topCandidates(1).first?.string, !s.isEmpty else { return nil }
        return OCRLine(text: s, rect: obs.boundingBox)
    }
    var codes: [String] = []
    if detectCodes {
        for c in codeRequest.results ?? [] {
            if let p = c.payloadStringValue, !codes.contains(p) { codes.append(p) }
        }
    }
    return OCRResult(lines: orderLines(pieces), codes: codes)
}

/// Final text to copy, following the line-break setting.
func composeText(_ r: OCRResult, mode: LineMode) -> String {
    let body: String
    switch mode {
    case .keep:
        body = r.lines.joined(separator: "\n")
    case .join:
        body = r.lines.reduce("") { $0.isEmpty ? $1 : smartJoin($0, $1) }
    }
    let codes = r.codes.joined(separator: "\n")
    if codes.isEmpty { return body }
    if body.isEmpty { return codes }
    return codes + "\n\n" + body
}

// MARK: - Popup state & view

final class PopupModel: ObservableObject {
    @Published var text = ""
    @Published var result = OCRResult(lines: [], codes: [])
    @Published var message: String?          // e.g. permission help instead of a result
    @Published var copiedFlash = false
    var onCopy: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenPermission: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    @ObservedObject var settings: AppSettings

    private var accent: Color { Color(hex: settings.accentHex) }
    private var dark: Bool { settings.theme == .dark }
    private var primary: Color { dark ? .white : Color(hex: "1C1C1E") }
    private var secondary: Color { primary.opacity(0.6) }
    private func font(_ scale: CGFloat = 1, _ w: Font.Weight = .regular) -> Font {
        .system(size: CGFloat(settings.fontSize) * scale, weight: w, design: settings.font.design)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let msg = model.message {
                messageBody(msg)
            } else {
                resultBody
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(primary.opacity(0.08), lineWidth: 1))
        .onHover { model.onHoverChange?($0) }
    }

    @ViewBuilder
    private var background: some View {
        switch settings.theme {
        case .glass: Rectangle().fill(.ultraThinMaterial)
        case .light: Color(hex: "FFFFFFF5")
        case .dark: Color(hex: "1E1E22F2")
        }
    }

    private func messageBody(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SnapText").font(font(1, .bold)).foregroundColor(primary)
                Spacer()
                closeButton
            }
            Text(msg).font(font(0.95)).foregroundColor(primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                pill("Open System Settings", filled: true) { model.onOpenPermission?() }
            }
        }
    }

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.copiedFlash ? "checkmark.circle.fill" : "text.viewfinder")
                    .foregroundColor(accent)
                Text(model.text.isEmpty ? "No text found" : "Copied")
                    .font(font(1, .bold)).foregroundColor(primary)
                if !model.text.isEmpty {
                    Text("\(model.text.count) characters").font(font(0.85)).foregroundColor(secondary)
                }
                if !model.result.codes.isEmpty {
                    Text("QR").font(font(0.75, .bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }
                Spacer()
                closeButton
            }

            if model.text.isEmpty {
                Text("Try a bigger area, or pick the right language in Settings.")
                    .font(font(0.9)).foregroundColor(secondary)
            } else {
                // Editable — fix a word, then press Copy
                TextEditor(text: $model.text)
                    .font(font())
                    .foregroundColor(primary)
                    .frame(height: editorHeight)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(primary.opacity(0.06)))
                    .modifier(HideEditorBackground())

                HStack(spacing: 8) {
                    pill("Copy", filled: true) { model.onCopy?(model.text) }
                    if model.result.lines.count > 1 {
                        pill("One paragraph") {
                            model.text = composeText(model.result, mode: .join)
                            model.onCopy?(model.text)
                        }
                        pill("Keep lines") {
                            model.text = composeText(model.result, mode: .keep)
                            model.onCopy?(model.text)
                        }
                    }
                    if let link = model.result.codes.first, let url = URL(string: link), url.scheme != nil {
                        pill("Open link") { NSWorkspace.shared.open(url) }
                    }
                    Spacer()
                }
            }
        }
    }

    /// Roughly fits the text: 60–220 pt.
    private var editorHeight: CGFloat {
        let explicit = model.text.split(separator: "\n", omittingEmptySubsequences: false)
        let wrapped = explicit.reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 38))) }
        return min(220, max(60, CGFloat(wrapped) * CGFloat(settings.fontSize) * 1.45 + 16))
    }

    private var closeButton: some View {
        Button { model.onClose?() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font(0.9, .semibold))
                .foregroundColor(filled ? .white : primary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(filled ? accent : primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// TextEditor paints its own white background before macOS 13; hide it where we can.
struct HideEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var s: AppSettings
    var onClearHistory: () -> Void
    var onTest: () -> Void
    var onPermission: () -> Void

    private func color(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
    }

    private let accents = ["FF6FAEFF", "AF52DEFF", "007AFFFF", "34C759FF", "FF9500FF", "E8553EFF", "1C1C1EFF"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Shortcut", selection: $s.hotkey) {
                            ForEach(HotkeyChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Language", selection: $s.language) {
                            ForEach(LanguageChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Picker("Line breaks", selection: $s.lineMode) {
                            ForEach(LineMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Read QR codes and barcodes too", isOn: $s.detectQR)
                        Toggle("Play a sound when text is copied", isOn: $s.playSound)
                    }
                    .padding(8)
                } label: {
                    Label("Capture", systemImage: "text.viewfinder")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show a popup with the text", isOn: $s.showPopup)
                        HStack {
                            Text("Hide after").frame(width: 100, alignment: .leading)
                            Slider(value: $s.popupSeconds, in: 1.5...10, step: 0.5)
                            Text(String(format: "%.1f s", s.popupSeconds)).monospacedDigit()
                                .foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
                        }
                        Text("The popup stays while your mouse is over it.").font(.caption).foregroundColor(.secondary)
                        Picker("Position", selection: $s.position) {
                            ForEach(PopupPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Look", selection: $s.theme) {
                            ForEach(PopupTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: 8) {
                            Text("Accent").frame(width: 100, alignment: .leading)
                            ForEach(accents, id: \.self) { hex in
                                Button { s.accentHex = hex } label: {
                                    Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.primary.opacity(s.accentHex == hex ? 0.8 : 0), lineWidth: 2).padding(-3))
                                }
                                .buttonStyle(.plain)
                            }
                            ColorPicker("", selection: color($s.accentHex), supportsOpacity: false).labelsHidden()
                        }
                        Picker("Font", selection: $s.font) {
                            ForEach(FontChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Text size").frame(width: 100, alignment: .leading)
                            Slider(value: $s.fontSize, in: 11...20, step: 0.5)
                            Text(String(format: "%.1f", s.fontSize)).monospacedDigit()
                                .foregroundColor(.secondary).frame(width: 50, alignment: .trailing)
                        }
                        HStack {
                            Spacer()
                            Button("Preview popup", action: onTest)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Popup", systemImage: "rectangle.on.rectangle")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Remember the last").frame(width: 140, alignment: .leading)
                            Stepper(value: $s.historyCount, in: 0...50) {
                                Text(s.historyCount == 0 ? "nothing" : "\(s.historyCount) captures").foregroundColor(.secondary)
                            }
                        }
                        Text("Recent captures appear in the menu bar menu. They stay on this Mac only.")
                            .font(.caption).foregroundColor(.secondary)
                        HStack { Spacer(); Button("Clear history", action: onClearHistory) }
                    }
                    .padding(8)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SnapText needs **Screen Recording** permission to see what's on your screen. Turn it on in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen SnapText.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack { Spacer(); Button("Open System Settings", action: onPermission) }
                    }
                    .padding(8)
                } label: {
                    Label("Permission", systemImage: "lock.shield")
                }

                HStack { Spacer(); Button("Reset to Defaults") { s.reset() } }
            }
            .padding(20)
        }
        .frame(width: 480, height: 680)
    }
}

// MARK: - Global hotkey (Carbon — needs no extra permission)

final class HotKey {
    nonisolated(unsafe) static var action: (@MainActor () -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKey.action?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x534E5458), id: 1)   // "SNTX"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r) }
        ref = nil
    }
}

// MARK: - Windows

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }      // so the text can be edited
    override var canBecomeMain: Bool { false }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = AppSettings()
    let popup = PopupModel()
    let hotKey = HotKey()
    var panel: PopupPanel!
    var statusItem: NSStatusItem!
    var recentMenu = NSMenu()
    var settingsWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()
    var lastHotkey: HotkeyChoice?
    var capturing = false
    var hideTask: Task<Void, Never>?
    var hovering = false
    var lastMouse = NSPoint.zero

    var history: [String] {
        get { UserDefaults.standard.stringArray(forKey: "history") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "history") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        let host = ClickThroughHostingView(rootView: PopupView(model: popup, settings: settings))
        panel.contentView = host

        popup.onCopy = { [weak self] text in self?.copy(text, flash: true) }
        popup.onClose = { [weak self] in self?.hidePopup() }
        popup.onOpenPermission = { [weak self] in self?.openPermissionSettings() }
        popup.onHoverChange = { [weak self] inside in
            self?.hovering = inside
            if !inside { self?.scheduleHide() }
        }
        HotKey.action = { [weak self] in self?.capture() }

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        setupStatusItem()
        applySettings()

        // First launch: ask for Screen Recording right away so the first capture works.
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
    }

    func applySettings() {
        if settings.hotkey != lastHotkey {
            lastHotkey = settings.hotkey
            if let k = settings.hotkey.key {
                hotKey.register(keyCode: k.0, modifiers: k.1)
            } else {
                hotKey.unregister()
            }
            updateMenuShortcutLabel()
        }
        trimHistory()
    }

    // MARK: Capture

    @objc func capture() {
        guard !capturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            showMessage("SnapText needs Screen Recording permission. Turn on SnapText in Privacy & Security → Screen & System Audio Recording, then quit and reopen SnapText.")
            return
        }
        capturing = true
        hidePopup()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snaptext-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", "-o", url.path]   // drag to select · no shutter sound · no window shadow
        p.terminationHandler = { _ in
            Task { @MainActor in self.finishCapture(url) }
        }
        do { try p.run() } catch { capturing = false; NSSound.beep() }
    }

    func finishCapture(_ url: URL) {
        lastMouse = NSEvent.mouseLocation
        guard FileManager.default.fileExists(atPath: url.path),
              let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            capturing = false          // pressed Esc — nothing selected
            return
        }
        try? FileManager.default.removeItem(at: url)

        let langs = settings.language.codes
        let auto = settings.language == .auto
        let codes = settings.detectQR
        let mode = settings.lineMode
        Task.detached(priority: .userInitiated) {
            let result = recognizeText(in: cg, languages: langs, automatic: auto, detectCodes: codes)
            let text = composeText(result, mode: mode)
            await self.showResult(result, text: text)
        }
    }

    func showResult(_ result: OCRResult, text: String) {
        capturing = false
        if !text.isEmpty {
            copy(text, flash: false)
            remember(text)
            if settings.playSound { NSSound(named: "Tink")?.play() }
        } else {
            NSSound.beep()
        }
        popup.message = nil
        popup.result = result
        popup.text = text
        popup.copiedFlash = !text.isEmpty
        if settings.showPopup || text.isEmpty { presentPopup() }
    }

    func copy(_ text: String, flash: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if flash {
            popup.copiedFlash = true
            if settings.playSound { NSSound(named: "Tink")?.play() }
        }
    }

    // MARK: Popup

    func showMessage(_ text: String) {
        popup.message = text
        presentPopup(autoHide: false)
    }

    func presentPopup(autoHide: Bool = true) {
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        let screen = NSScreen.screens.first(where: { $0.frame.contains(lastMouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        var origin: NSPoint
        switch settings.position {
        case .top:
            origin = NSPoint(x: v.midX - size.width / 2, y: v.maxY - size.height - 12)
        case .bottom:
            origin = NSPoint(x: v.midX - size.width / 2, y: v.minY + 24)
        case .cursor:
            origin = NSPoint(x: lastMouse.x - size.width / 2, y: lastMouse.y - size.height - 16)
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let p = panel!
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        if autoHide { scheduleHide() } else { hideTask?.cancel() }
    }

    func scheduleHide() {
        hideTask?.cancel()
        guard popup.message == nil else { return }
        let seconds = settings.popupSeconds
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // keep it while you're pointing at it or editing the text
            if self.hovering || self.panel.isKeyWindow { return }
            self.hidePopup()
        }
    }

    func hidePopup() {
        hideTask?.cancel()
        guard panel.isVisible else { return }
        let p = panel!
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in self.panel.orderOut(nil) }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel { scheduleHide() }
    }

    @objc func testPopup() {
        lastMouse = NSEvent.mouseLocation
        let sample = OCRResult(lines: ["SnapText ✿", "Copy text from anything on your screen.", "從螢幕上任何地方複製文字。"], codes: [])
        popup.message = nil
        popup.result = sample
        popup.text = composeText(sample, mode: settings.lineMode)
        popup.copiedFlash = true
        presentPopup()
    }

    // MARK: History

    func remember(_ text: String) {
        guard settings.historyCount > 0 else { return }
        var h = history.filter { $0 != text }
        h.insert(text, at: 0)
        history = Array(h.prefix(settings.historyCount))
        rebuildRecentMenu()
    }

    func trimHistory() {
        history = Array(history.prefix(settings.historyCount))
        rebuildRecentMenu()
    }

    @objc func clearHistory() {
        history = []
        rebuildRecentMenu()
    }

    func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let h = history
        if h.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        for (i, text) in h.enumerated() {
            let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            let title = oneLine.count > 48 ? String(oneLine.prefix(48)) + "…" : oneLine
            let item = NSMenuItem(title: title, action: #selector(copyRecent(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.toolTip = text
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        recentMenu.addItem(clear)
    }

    @objc func copyRecent(_ sender: NSMenuItem) {
        let h = history
        guard h.indices.contains(sender.tag) else { return }
        copy(h[sender.tag], flash: false)
        if settings.playSound { NSSound(named: "Tink")?.play() }
    }

    // MARK: Menu bar

    var captureItem: NSMenuItem!

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "SnapText")

        let menu = NSMenu()
        captureItem = NSMenuItem(title: "Capture Text", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        if #available(macOS 13.0, *) {
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            login.isHidden = true
        }
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SnapText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
        rebuildRecentMenu()
        updateMenuShortcutLabel()
    }

    func updateMenuShortcutLabel() {
        guard let item = captureItem else { return }
        item.title = settings.hotkey == .off ? "Capture Text" : "Capture Text   \(settings.hotkey.label)"
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "SnapText Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(
                s: settings,
                onClearHistory: { [weak self] in self?.clearHistory() },
                onTest: { [weak self] in self?.testPopup() },
                onPermission: { [weak self] in self?.openPermissionSettings() }))
            w.center()
            w.delegate = self
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openPermissionSettings() {
        hidePopup()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSSound.beep()
            }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}

@main
struct SnapTextMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
