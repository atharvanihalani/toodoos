import AppKit
import Carbon

// MARK: - Config

struct Config {
    static let todoFile = NSHomeDirectory() + "/.toodoos.md"
    static let configFile = NSHomeDirectory() + "/.toodoos.conf"
    static let logFile = NSHomeDirectory() + "/.toodoos.log"

    static var discordWebhookURL: String? {
        guard let data = try? String(contentsOfFile: configFile, encoding: .utf8) else { return nil }
        for line in data.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("webhook=") {
                let url = String(trimmed.dropFirst("webhook=".count))
                return url.isEmpty ? nil : url
            }
        }
        return nil
    }
}

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: Config.logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: Config.logFile, contents: line.data(using: .utf8))
    }
}

// MARK: - TodoStorage

enum TodoStorage {
    static func save(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "- [\(timestamp)] \(text)\n"

        if !FileManager.default.fileExists(atPath: Config.todoFile) {
            FileManager.default.createFile(atPath: Config.todoFile, contents: nil)
            try? "# Toodoos\n\n".write(toFile: Config.todoFile, atomically: true, encoding: .utf8)
        }

        if let handle = FileHandle(forWritingAtPath: Config.todoFile) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        }
    }
}

// MARK: - Discord

enum Discord {
    static func send(_ text: String) {
        guard let urlString = Config.discordWebhookURL,
              let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "content": "**\(timestamp)**\n\(text)"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request).resume()
    }
}

// MARK: - Floating Input Window

class FloatingInputWindow: NSWindow {
    private let inputField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private var onSubmit: ((String) -> Void)?

    init() {
        let width: CGFloat = 480
        let height: CGFloat = 44

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 12

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        setupUI()
    }

    private func setupUI() {
        let container = NSVisualEffectView(frame: contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        contentView?.addSubview(container)

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        inputField.textColor = .white
        inputField.focusRingType = .none
        inputField.placeholderString = "what's on your mind?"
        inputField.cell?.sendsActionOnEndEditing = false
        inputField.target = self
        inputField.action = #selector(handleSubmit)
        container.addSubview(inputField)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        statusLabel.stringValue = "⏎"
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            inputField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            inputField.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    func show(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        inputField.stringValue = ""

        let width: CGFloat = 480
        let height: CGFloat = 44
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 12
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        // Temporarily become a regular app to guarantee activation, then hide from dock again
        NSApp.setActivationPolicy(.regular)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        makeFirstResponder(inputField)

        // Switch back to accessory (no dock icon) after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }

        log("Input window shown")
    }

    func showSuccess() {
        statusLabel.stringValue = "✓"
        statusLabel.textColor = NSColor.systemGreen.withAlphaComponent(0.8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        orderOut(nil)
        statusLabel.stringValue = "⏎"
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        inputField.stringValue = ""
    }

    @objc private func handleSubmit() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            dismiss()
            return
        }
        onSubmit?(text)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Global Hotkey via CGEvent Tap

class HotKeyManager {
    static var callback: (() -> Void)?
    private static var eventTap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?

    static func register(callback: @escaping () -> Void) {
        self.callback = callback

        // Check accessibility
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        log("Accessibility trusted: \(trusted)")

        if !trusted {
            log("WARNING: Not trusted for accessibility. Hotkey will not work.")
            // Poll for accessibility permission
            pollForAccessibility()
            return
        }

        installEventTap()
    }

    private static func pollForAccessibility() {
        // Check every 2 seconds if we've been granted permission
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            let trusted = AXIsProcessTrusted()
            if trusted {
                log("Accessibility now granted! Installing event tap.")
                timer.invalidate()
                installEventTap()
            }
        }
    }

    static func ensureTapAlive() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("Re-enabled disabled event tap")
            }
        } else {
            log("Event tap was nil, reinstalling...")
            installEventTap()
        }
    }

    private static func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags

                    // Cmd+Ctrl+B: keyCode 11 = B
                    let hasCmd = flags.contains(.maskCommand)
                    let hasCtrl = flags.contains(.maskControl)
                    let noOpt = !flags.contains(.maskAlternate)
                    let noShift = !flags.contains(.maskShift)

                    if keyCode == 11 && hasCmd && hasCtrl && noOpt && noShift {
                        log("Hotkey detected!")
                        DispatchQueue.main.async {
                            HotKeyManager.callback?()
                        }
                    }
                }

                // If the tap gets disabled (system can do this), re-enable it
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = HotKeyManager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        log("Re-enabled event tap")
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        ) else {
            log("ERROR: Failed to create CGEvent tap. Accessibility permission may not be granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("CGEvent tap installed successfully")
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var inputWindow: FloatingInputWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        log("Toodoos starting up")

        inputWindow = FloatingInputWindow()

        setupMenuBar()

        HotKeyManager.register { [weak self] in
            self?.showInput()
        }

        if !FileManager.default.fileExists(atPath: Config.configFile) {
            try? "# Toodoos config\n# webhook=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL\n"
                .write(toFile: Config.configFile, atomically: true, encoding: .utf8)
        }

        log("Toodoos ready")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "T"
            button.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "New Todo  ⌃⌘B", action: #selector(showInput), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Toodoos File", action: #selector(openFile), keyEquivalent: "")
        menu.addItem(withTitle: "Edit Config", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showInput() {
        inputWindow.show { [weak self] text in
            TodoStorage.save(text)
            Discord.send(text)
            self?.inputWindow.showSuccess()
        }
    }

    @objc private func openFile() {
        if !FileManager.default.fileExists(atPath: Config.todoFile) {
            TodoStorage.save("first todo!")
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: Config.todoFile))
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Config.configFile))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
