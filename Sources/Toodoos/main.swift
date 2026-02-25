import AppKit
import Carbon

// MARK: - Config

struct Config {
    static let todoFile = NSHomeDirectory() + "/.toodoos.md"
    static let logFile = NSHomeDirectory() + "/.toodoos.log"
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

    static func load() -> [(timestamp: String, text: String)] {
        guard let content = try? String(contentsOfFile: Config.todoFile, encoding: .utf8) else {
            return []
        }
        var entries: [(timestamp: String, text: String)] = []
        for line in content.components(separatedBy: "\n") {
            // Match: - [ISO8601_TIMESTAMP] text
            guard line.hasPrefix("- [") else { continue }
            let after = line.dropFirst(3) // drop "- ["
            guard let closeBracket = after.firstIndex(of: "]") else { continue }
            let timestamp = String(after[after.startIndex..<closeBracket])
            let textStart = after.index(closeBracket, offsetBy: 2, limitedBy: after.endIndex) ?? after.endIndex
            let text = String(after[textStart...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            entries.append((timestamp: timestamp, text: text))
        }
        return entries
    }

    static func rewrite(_ entries: [(timestamp: String, text: String)]) {
        var content = "# Toodoos\n\n"
        for entry in entries {
            content += "- [\(entry.timestamp)] \(entry.text)\n"
        }
        try? content.write(toFile: Config.todoFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - Floating Input Window

class FloatingInputWindow: NSPanel {
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
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true

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

        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(inputField)

        // Retry focus assertion — the panel may need a couple run loop cycles
        assertFocus()

        log("Input window shown")
    }

    func focusInput() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(inputField)
        assertFocus()
    }

    private func assertFocus() {
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, self.isVisible else { timer.invalidate(); return }
            attempts += 1
            if self.isKeyWindow && self.firstResponder === self.inputField {
                timer.invalidate()
            } else {
                self.makeKeyAndOrderFront(nil)
                self.makeFirstResponder(self.inputField)
            }
            if attempts >= 10 { timer.invalidate() }
        }
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

// MARK: - Todo Row TextField

// MARK: - Todo List Window

class TodoListWindow: NSPanel {
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "no todos yet")
    private var entries: [(timestamp: String, text: String)] = []
    private var onDismiss: (() -> Void)?
    private var focusedIndex: Int = 0
    private var textFields: [NSTextField] = []
    private var undoStack: [(timestamp: String, text: String, index: Int)] = []
    private let maxUndoStackSize = 20

    init() {
        let width: CGFloat = 480
        let height: CGFloat = 300

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 12

        super.init(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isFloatingPanel = true

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

        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = stackView
        container.addSubview(scrollView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.3)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    func show(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        focusedIndex = 0
        reload()

        let width: CGFloat = 480
        let rowHeight: CGFloat = 36
        let padding: CGFloat = 16
        let count = max(entries.count, 1)
        let height = min(CGFloat(count) * rowHeight + padding, 400)

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 12
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        // Focus the first todo
        if !textFields.isEmpty {
            makeFirstResponder(textFields[0])
        }

        log("Todo list shown with \(entries.count) entries")
    }

    func reload() {
        entries = TodoStorage.load()
        textFields.removeAll()
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if entries.isEmpty {
            emptyLabel.isHidden = false
            scrollView.isHidden = true
            return
        }

        emptyLabel.isHidden = true
        scrollView.isHidden = false

        for (index, entry) in entries.enumerated() {
            let row = makeRow(index: index, text: entry.text)
            stackView.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
    }

    private func makeRow(index: Int, text: String) -> NSView {
        let row = NSView()

        let textField = NSTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.stringValue = text
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textField.textColor = .white
        textField.focusRingType = .none
        textField.isEditable = true
        textField.tag = index
        textField.target = self
        textField.action = #selector(handleEdit(_:))
        textField.delegate = self
        textField.cell?.sendsActionOnEndEditing = false
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        row.addSubview(textField)
        textFields.append(textField)

        let deleteBtn = NSButton(title: "×", target: self, action: #selector(handleDelete(_:)))
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.isBordered = false
        deleteBtn.font = .systemFont(ofSize: 16, weight: .medium)
        deleteBtn.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        deleteBtn.tag = index
        row.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            deleteBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteBtn.widthAnchor.constraint(equalToConstant: 24),
        ])

        return row
    }

    private func focusRow(_ index: Int) {
        guard index >= 0 && index < textFields.count else { return }
        focusedIndex = index
        makeFirstResponder(textFields[index])
        // Scroll the focused row into view
        if let row = textFields[index].superview {
            scrollView.contentView.scrollToVisible(row.frame)
        }
    }

    @objc private func handleEdit(_ sender: NSTextField) {
        let index = sender.tag
        guard index >= 0 && index < entries.count else { return }
        let newText = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newText.isEmpty {
            pushUndo(index: index)
            entries.remove(at: index)
            focusedIndex = min(index, entries.count - 1)
        } else {
            entries[index].text = newText
            focusedIndex = index
        }
        TodoStorage.rewrite(entries)
        reload()
        resizeToFit()
        if !textFields.isEmpty {
            focusRow(max(0, min(focusedIndex, textFields.count - 1)))
        }
        log("Todo edited at index \(index)")
    }

    @objc private func handleDelete(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < entries.count else { return }
        pushUndo(index: index)
        entries.remove(at: index)
        TodoStorage.rewrite(entries)
        focusedIndex = min(index, max(entries.count - 1, 0))
        reload()
        resizeToFit()
        if !textFields.isEmpty {
            focusRow(focusedIndex)
        }
        log("Todo deleted at index \(index)")
    }

    private func pushUndo(index: Int) {
        guard index >= 0 && index < entries.count else { return }
        let entry = entries[index]
        undoStack.append((timestamp: entry.timestamp, text: entry.text, index: index))
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
    }

    func performUndo() {
        guard let deleted = undoStack.popLast() else { return }
        let restoreIndex = min(deleted.index, entries.count)
        entries.insert((timestamp: deleted.timestamp, text: deleted.text), at: restoreIndex)
        TodoStorage.rewrite(entries)
        focusedIndex = restoreIndex
        reload()
        resizeToFit()
        if !textFields.isEmpty {
            focusRow(focusedIndex)
        }
        log("Undo: restored todo at index \(restoreIndex)")
    }

    private func resizeToFit() {
        let width: CGFloat = 480
        let rowHeight: CGFloat = 36
        let padding: CGFloat = 16
        let count = max(entries.count, 1)
        let height = min(CGFloat(count) * rowHeight + padding, 400)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - height - 12
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func dismiss() {
        orderOut(nil)
        onDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension TodoListWindow: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(moveUp(_:)) {
            focusRow(max(0, focusedIndex - 1))
            return true
        }
        if commandSelector == #selector(moveDown(_:)) {
            focusRow(min(textFields.count - 1, focusedIndex + 1))
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            dismiss()
            return true
        }
        // Cmd+Z triggers undo:
        if commandSelector == NSSelectorFromString("undo:") {
            performUndo()
            return true
        }
        // Cmd+Delete triggers deleteToBeginningOfLine:
        if commandSelector == #selector(NSText.deleteToBeginningOfLine(_:)) {
            if focusedIndex >= 0 && focusedIndex < entries.count {
                pushUndo(index: focusedIndex)
                entries.remove(at: focusedIndex)
                TodoStorage.rewrite(entries)
                focusedIndex = min(focusedIndex, max(entries.count - 1, 0))
                reload()
                resizeToFit()
                if !textFields.isEmpty {
                    focusRow(focusedIndex)
                }
                log("Todo deleted via Cmd+Delete at index \(focusedIndex)")
            }
            return true
        }
        return false
    }
}

// MARK: - Global Hotkey via CGEvent Tap

class HotKeyManager {
    static var callback: (() -> Void)?
    private static var eventTap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?

    static func register(callback: @escaping () -> Void) {
        self.callback = callback

        // Check accessibility silently — don't prompt every launch
        let trusted = AXIsProcessTrusted()
        log("Accessibility trusted: \(trusted)")

        if !trusted {
            log("WARNING: Not trusted for accessibility. Hotkey will not work.")
            // Prompt once, then poll silently
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            )
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

                    if keyCode == 17 && hasCmd && hasCtrl && noOpt && noShift {
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
    private var todoListWindow: TodoListWindow!
    private var lastHotkeyTime: Date = .distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        log("Toodoos starting up")

        inputWindow = FloatingInputWindow()
        todoListWindow = TodoListWindow()

        setupMenuBar()

        HotKeyManager.register { [weak self] in
            self?.handleHotkey()
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
        menu.addItem(withTitle: "New Todo  ⌃⌘T", action: #selector(showInput), keyEquivalent: "")
        menu.addItem(withTitle: "View Todos  ⌃⌘T×2", action: #selector(showTodoList), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Toodoos File", action: #selector(openFile), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func handleHotkey() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastHotkeyTime)
        lastHotkeyTime = now

        if elapsed < 0.4 {
            // Double-tap: dismiss input, show todo list
            inputWindow.dismiss()
            showTodoList()
        } else {
            // Single tap: show input (or dismiss todo list first)
            if todoListWindow.isVisible {
                todoListWindow.dismiss()
            }
            showInput()
        }
    }

    @objc private func showInput() {
        if inputWindow.isVisible {
            inputWindow.focusInput()
            return
        }
        inputWindow.show { [weak self] text in
            TodoStorage.save(text)
            self?.inputWindow.showSuccess()
        }
    }

    @objc private func showTodoList() {
        if todoListWindow.isVisible {
            todoListWindow.dismiss()
            return
        }
        inputWindow.dismiss()
        todoListWindow.show { }
    }

    @objc private func openFile() {
        if !FileManager.default.fileExists(atPath: Config.todoFile) {
            TodoStorage.save("first todo!")
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: Config.todoFile))
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
