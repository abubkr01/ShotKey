import AppKit
import Carbon
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import ServiceManagement

private enum DefaultsKey {
    static let captureKey = "captureKey"
    static let captureModifiers = "captureModifiers"
    static let regionKey = "regionKey"
    static let regionModifiers = "regionModifiers"
    static let saveFolder = "saveFolder"
    static let imageFormat = "imageFormat"
    static let outputMode = "outputMode"
    static let hasLaunched = "hasLaunched"
}

enum OutputMode: String {
    case both, clipboardOnly, fileOnly

    var title: String {
        switch self {
        case .both: return "Save + Copy to Clipboard"
        case .clipboardOnly: return "Copy to Clipboard Only"
        case .fileOnly: return "Save to Folder Only"
        }
    }
}

struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var readable: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"
        ]
        if let name = names[code] { return name }
        let chars: [UInt32: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",50:"`"
        ]
        return chars[code] ?? "Key \(code)"
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

final class Preferences {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    var captureShortcut: Shortcut {
        get {
            let key = defaults.object(forKey: DefaultsKey.captureKey) == nil ? 97 : UInt32(defaults.integer(forKey: DefaultsKey.captureKey))
            return Shortcut(keyCode: key, modifiers: UInt32(defaults.integer(forKey: DefaultsKey.captureModifiers)))
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: DefaultsKey.captureKey)
            defaults.set(Int(newValue.modifiers), forKey: DefaultsKey.captureModifiers)
        }
    }

    var regionShortcut: Shortcut {
        get {
            let key = defaults.object(forKey: DefaultsKey.regionKey) == nil ? 98 : UInt32(defaults.integer(forKey: DefaultsKey.regionKey))
            return Shortcut(keyCode: key, modifiers: UInt32(defaults.integer(forKey: DefaultsKey.regionModifiers)))
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: DefaultsKey.regionKey)
            defaults.set(Int(newValue.modifiers), forKey: DefaultsKey.regionModifiers)
        }
    }

    var clipboardShortcut: Shortcut {
        get { Shortcut(keyCode: UInt32(defaults.object(forKey: "clipboardKey") as? Int ?? 20),
                       modifiers: UInt32(defaults.object(forKey: "clipboardModifiers") as? Int ?? 2048)) }
        set { defaults.set(Int(newValue.keyCode), forKey: "clipboardKey"); defaults.set(Int(newValue.modifiers), forKey: "clipboardModifiers") }
    }
    var clipboardOutputMode: OutputMode {
        get { OutputMode(rawValue: defaults.string(forKey: "clipboardOutputMode") ?? "clipboardOnly") ?? .clipboardOnly }
        set { defaults.set(newValue.rawValue, forKey: "clipboardOutputMode") }
    }
    var saveFolder: URL {
        get {
            if let path = defaults.string(forKey: DefaultsKey.saveFolder) { return URL(fileURLWithPath: path, isDirectory: true) }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        set { defaults.set(newValue.path, forKey: DefaultsKey.saveFolder) }
    }

    var imageFormat: String {
        get { defaults.string(forKey: DefaultsKey.imageFormat) ?? "png" }
        set { defaults.set(newValue, forKey: DefaultsKey.imageFormat) }
    }

    var outputMode: OutputMode {
        get { OutputMode(rawValue: defaults.string(forKey: DefaultsKey.outputMode) ?? "both") ?? .both }
        set { defaults.set(newValue.rawValue, forKey: DefaultsKey.outputMode) }
    }
}

private enum CaptureError: LocalizedError {
    case permissionDenied, noDisplay, captureFailed, saveFailed
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Screen Recording permission is required."
        case .noDisplay: return "No display was found under the pointer."
        case .captureFailed: return "macOS could not capture the screen."
        case .saveFailed: return "The screenshot could not be saved."
        }
    }
}

final class CaptureService {
    static let shared = CaptureService()

    func ensurePermission(prompt: Bool = true) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return prompt ? CGRequestScreenCaptureAccess() : false
    }

    func displayUnderPointer() -> CGDirectDisplayID? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.first { CGDisplayBounds($0).contains(point) }
    }

    func captureDisplayUnderPointer() {
        guard !EditorSession.shared.isActive else { return }
        guard let displayID = displayUnderPointer() else { AppDelegate.shared?.showError(CaptureError.noDisplay); return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.noDisplay }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                configuration.showsCursor = false
                configuration.capturesAudio = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                deliver(image)
            } catch { handleCaptureFailure(error) }
        }
    }


    private func handleCaptureFailure(_ error: Error) {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            AppDelegate.shared?.showError(CaptureError.permissionDenied)
        } else {
            AppDelegate.shared?.showError(error)
        }
    }

    func deliver(_ image: CGImage) {
        DispatchQueue.main.async { [self] in deliverOnMain(image) }
    }

    @discardableResult func deliverOnMain(_ image: CGImage, mode override: OutputMode? = nil) -> Bool {
        let prefs = Preferences.shared
        let mode = override ?? prefs.outputMode
        var copied = false
        if mode != .fileOnly {
            let representation = NSBitmapImageRep(cgImage: image)
            if let png = representation.representation(using: .png, properties: [:]) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                copied = pasteboard.setData(png, forType: .png)
            }
        }

        if mode == .clipboardOnly {
            if copied { AppDelegate.shared?.captureDidCopy() }
            else { AppDelegate.shared?.showErrorMessage("The screenshot could not be copied to the clipboard.") }
            return copied
        }

        let folder = prefs.saveFolder
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { AppDelegate.shared?.showError(error); return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let ext = prefs.imageFormat == "jpg" ? "jpg" : "png"
        let url = folder.appendingPathComponent("Screenshot \(formatter.string(from: Date())).\(ext)")
        let type = ext == "jpg" ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            AppDelegate.shared?.showError(CaptureError.saveFailed); return false
        }
        let properties: CFDictionary = ext == "jpg" ? [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary : [:] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { AppDelegate.shared?.showError(CaptureError.saveFailed); return false }
        AppDelegate.shared?.captureDidSave(url, copied: copied)
        return true
    }
}

private final class HotKeyManager {
    static let shared = HotKeyManager()
    private var captureRef: EventHotKeyRef?
    private var regionRef: EventHotKeyRef?
    private var clipboardRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func install() {
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                DispatchQueue.main.async {
                    if hotKeyID.id == 1 { CaptureService.shared.captureDisplayUnderPointer() }
                    if hotKeyID.id == 2 { SelectionCoordinator.shared.begin() }
                    if hotKeyID.id == 3 { EditorSession.shared.openClipboard() }
                }
                return noErr
            }, 1, &type, nil, &handler)
        }
        reload()
    }

    func reload() {
        if let captureRef { UnregisterEventHotKey(captureRef) }
        if let regionRef { UnregisterEventHotKey(regionRef) }
        if let clipboardRef { UnregisterEventHotKey(clipboardRef) }
        let signature: OSType = 0x53484B59 // SHKY
        let captureID = EventHotKeyID(signature: signature, id: 1)
        let regionID = EventHotKeyID(signature: signature, id: 2)
        let capture = Preferences.shared.captureShortcut
        let region = Preferences.shared.regionShortcut
        let captureStatus = RegisterEventHotKey(capture.keyCode, capture.modifiers, captureID, GetApplicationEventTarget(), 0, &captureRef)
        let regionStatus = RegisterEventHotKey(region.keyCode, region.modifiers, regionID, GetApplicationEventTarget(), 0, &regionRef)
        let clipboard = Preferences.shared.clipboardShortcut
        let clipboardStatus = RegisterEventHotKey(clipboard.keyCode, clipboard.modifiers,
            EventHotKeyID(signature: signature, id: 3), GetApplicationEventTarget(), 0, &clipboardRef)
        if captureStatus != noErr || regionStatus != noErr || clipboardStatus != noErr {
            AppDelegate.shared?.showErrorMessage("One shortcut is already used by macOS or another app. Choose a different shortcut in Settings.")
        }
        AppDelegate.shared?.refreshMenu()
    }
}

private final class ShortcutRecorderButton: NSButton {
    var shortcut: Shortcut { didSet { updateTitle() } }
    var onChange: ((Shortcut) -> Void)?
    private var recording = false

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleRecording() {
        recording.toggle()
        title = recording ? "Press shortcut…" : shortcut.readable
        window?.makeFirstResponder(recording ? self : nil)
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { recording = false; updateTitle(); return }
        let modifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
        let functionKey = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80].contains(Int(event.keyCode))
        if modifiers == 0 && !functionKey {
            NSSound.beep()
            title = "Add ⌘, ⌥, ⌃ or ⇧"
            return
        }
        shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        recording = false
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }
    override func resignFirstResponder() -> Bool { recording = false; updateTitle(); return super.resignFirstResponder() }
    private func updateTitle() { title = shortcut.readable }
}

private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let folderLabel = NSTextField(labelWithString: "")
    private let captureButton = ShortcutRecorderButton(shortcut: Preferences.shared.captureShortcut)
    private let clipboardButton = ShortcutRecorderButton(shortcut: Preferences.shared.clipboardShortcut)
    private let clipboardOutputPopup = NSPopUpButton()
    private let regionButton = ShortcutRecorderButton(shortcut: Preferences.shared.regionShortcut)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let outputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch ShotKey when I log in", target: nil, action: nil)

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ShotKey Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        updateFolderLabel()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let title = NSTextField(labelWithString: "ShotKey")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: "Instant screenshots from the display under your pointer.")
        subtitle.textColor = .secondaryLabelColor

        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 3
        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        captureButton.onChange = { shortcut in
            Preferences.shared.captureShortcut = shortcut
            HotKeyManager.shared.reload()
        }
        regionButton.onChange = { shortcut in
            Preferences.shared.regionShortcut = shortcut
            HotKeyManager.shared.reload()
        }

        clipboardButton.onChange = { shortcut in
            Preferences.shared.clipboardShortcut = shortcut
            HotKeyManager.shared.reload()
        }
        let shortcutGrid = NSGridView(views: [
            [NSTextField(labelWithString: "Display under pointer"), captureButton, NSButton(title: "Try", target: self, action: #selector(tryDisplayCapture))],
            [NSTextField(labelWithString: "Freeze & edit"), regionButton, NSButton(title: "Try", target: self, action: #selector(tryRegionCapture))],
            [NSTextField(labelWithString: "Edit clipboard image"), clipboardButton, NSButton(title: "Try", target: self, action: #selector(tryClipboard))]
        ])
        shortcutGrid.rowSpacing = 12
        shortcutGrid.columnSpacing = 20
        shortcutGrid.column(at: 0).xPlacement = .leading
        shortcutGrid.column(at: 1).width = 170
        shortcutGrid.column(at: 2).width = 52

        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        let chooseButton = NSButton(title: "Choose Folder…", target: self, action: #selector(chooseFolder))
        let folderRow = NSStackView(views: [folderLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 12
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        formatPopup.addItems(withTitles: ["PNG", "JPEG"])
        formatPopup.selectItem(withTitle: Preferences.shared.imageFormat == "jpg" ? "JPEG" : "PNG")
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        let formatRow = NSStackView(views: [NSTextField(labelWithString: "Image format"), formatPopup, NSView()])
        formatRow.orientation = .horizontal
        formatRow.spacing = 18

        outputPopup.addItems(withTitles: [OutputMode.both.title, OutputMode.clipboardOnly.title, OutputMode.fileOnly.title])
        outputPopup.selectItem(withTitle: Preferences.shared.outputMode.title)
        outputPopup.target = self
        outputPopup.action = #selector(outputModeChanged)
        let outputRow = NSStackView(views: [NSTextField(labelWithString: "After capture"), outputPopup, NSView()])
        outputRow.orientation = .horizontal
        outputRow.spacing = 18

        clipboardOutputPopup.addItems(withTitles: [OutputMode.both.title, OutputMode.clipboardOnly.title, OutputMode.fileOnly.title])
        clipboardOutputPopup.selectItem(withTitle: Preferences.shared.clipboardOutputMode.title)
        clipboardOutputPopup.target = self; clipboardOutputPopup.action = #selector(clipboardOutputChanged)
        let clipboardOutputRow = NSStackView(views: [NSTextField(labelWithString: "Clipboard edits"), clipboardOutputPopup])
        clipboardOutputRow.spacing = 18
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)

        let note = NSTextField(wrappingLabelWithString: "The first shortcut captures immediately. The second freezes the screen for cropping and annotation; press it again to finish. Press Escape twice to close. Clipboard edits open in a separate window.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)

        let shortcutsLabel = sectionLabel("SHORTCUTS")
        let destinationLabel = sectionLabel("SAVE LOCATION")
        let stack = NSStackView(views: [header, shortcutsLabel, shortcutGrid, destinationLabel, folderRow, formatRow, outputRow, clipboardOutputRow, loginCheckbox, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(26, after: header)
        stack.setCustomSpacing(8, after: shortcutsLabel)
        stack.setCustomSpacing(26, after: shortcutGrid)
        stack.setCustomSpacing(8, after: destinationLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            folderRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        updateFolderLabel()
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func updateFolderLabel() { folderLabel.stringValue = Preferences.shared.saveFolder.path }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where screenshots are saved"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Preferences.shared.saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            Preferences.shared.saveFolder = url
            updateFolderLabel()
        }
    }

    @objc private func formatChanged() { Preferences.shared.imageFormat = formatPopup.titleOfSelectedItem == "JPEG" ? "jpg" : "png" }

    @objc private func tryClipboard() { EditorSession.shared.openClipboard() }
    @objc private func clipboardOutputChanged() {
        Preferences.shared.clipboardOutputMode = OutputMode.allCasesForMenu.first { $0.title == clipboardOutputPopup.titleOfSelectedItem } ?? .clipboardOnly
    }
    @objc private func outputModeChanged() {
        let title = outputPopup.titleOfSelectedItem
        Preferences.shared.outputMode = OutputMode.allCasesForMenu.first(where: { $0.title == title }) ?? .both
    }

    @objc private func tryDisplayCapture() { CaptureService.shared.captureDisplayUnderPointer() }
    @objc private func tryRegionCapture() { SelectionCoordinator.shared.begin() }

    @objc private func loginChanged() {
        do {
            if loginCheckbox.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            AppDelegate.shared?.showErrorMessage("Launch at Login could not be changed: \(error.localizedDescription)")
        }
    }
}


private extension OutputMode {
    static let allCasesForMenu: [OutputMode] = [.both, .clipboardOnly, .fileOnly]
}

private final class SelectionCoordinator {
    static let shared = SelectionCoordinator()
    func begin() { EditorSession.shared.toggle() }
}
private final class ToastPanel: NSPanel {
    init(message: String, screen: NSScreen?) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 330, height: 58), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView(frame: contentView!.bounds)
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 13
        effect.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = effect.bounds.insetBy(dx: 14, dy: 18)
        effect.addSubview(label)
        contentView = effect
        let target = screen ?? NSScreen.main
        if let frame = target?.visibleFrame {
            setFrameOrigin(CGPoint(x: frame.midX - 165, y: frame.maxY - 90))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController!
    private var toast: ToastPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        settings = SettingsWindowController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder.circle.fill", accessibilityDescription: "ShotKey")
            button.toolTip = "ShotKey"
        }
        refreshMenu()
        HotKeyManager.shared.install()
        if !UserDefaults.standard.bool(forKey: DefaultsKey.hasLaunched) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasLaunched)
            settings.show()
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit ShotKey", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func refreshMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture Display Under Pointer", action: #selector(captureDisplay), keyEquivalent: "")
        capture.toolTip = Preferences.shared.captureShortcut.readable
        let region = NSMenuItem(title: "Freeze Screen & Edit", action: #selector(captureRegion), keyEquivalent: "")
        region.toolTip = Preferences.shared.regionShortcut.readable
        menu.addItem(capture)
        menu.addItem(region)
        menu.addItem(NSMenuItem(title: "Edit Clipboard Image", action: #selector(editClipboard), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ShotKey", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func captureDisplay() { CaptureService.shared.captureDisplayUnderPointer() }
    @objc private func captureRegion() { SelectionCoordinator.shared.begin() }
    @objc private func editClipboard() { EditorSession.shared.openClipboard() }
    @objc private func showSettings() { settings.show() }
    @objc private func openFolder() { NSWorkspace.shared.open(Preferences.shared.saveFolder) }
    @objc private func quit() { NSApp.terminate(nil) }

    func captureDidSave(_ url: URL, copied: Bool) {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        let message = copied ? "✓  Saved + copied to clipboard" : "✓  Saved \(url.lastPathComponent)"
        showToast(message, screen: screen)
    }

    func captureDidCopy() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        showToast("✓  Copied to clipboard", screen: screen)
    }

    private func showToast(_ message: String, screen: NSScreen?) {
        let panel = ToastPanel(message: message, screen: screen)
        toast?.orderOut(nil)
        toast = panel
        panel.orderFrontRegardless()
        NSSound(named: "Tink")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.toast === panel { self?.toast = nil }
        }
    }

    func showError(_ error: Error) { showErrorMessage(error.localizedDescription) }
    func showErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "ShotKey"
            alert.informativeText = message
            if message.contains("permission") {
                alert.addButton(withTitle: "Open Screen Recording Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            } else { alert.runModal() }
        }
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
