import AppKit

public final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    public private(set) var containerView: DiffContainerView!
    public private(set) var diffCoordinator: DiffCoordinator!
    public private(set) var scrollCoordinator: DiffScrollCoordinator!

    public private(set) var headerBar: NSView!
    public private(set) var prevChangeBtn: ModernPillButton!
    public private(set) var nextChangeBtn: ModernPillButton!
    public private(set) var flipSidesBtn: ModernPillButton!
    public private(set) var invisiblesCheckbox: ModernPillButton!
    public private(set) var copyAllRightBtn: ModernPillButton!
    public private(set) var copyAllLeftBtn: ModernPillButton!
    public private(set) var leftTitleLabel: NSTextField!
    public private(set) var leftStatLabel: NSTextField!
    public private(set) var rightTitleLabel: NSTextField!
    public private(set) var rightStatLabel: NSTextField!

    /// The file behind each pane, if it was opened from or saved to disk.
    public private(set) var documents: [EditorSide: PaneDocument] = [:]
    /// Set once the user chose "Don't Save" while closing, so quitting does not ask twice.
    private var discardConfirmed = false

    // Double ⌘Q quit confirmation HUD
    private var quitHUDView: QuitConfirmationHUDView?
    private var quitHUDDismissTimer: Timer?
    private var quitEventMonitor: Any?


    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1150, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 0, height: 320)
        window.title = "Diffr — Visual Diff Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.center()

        self.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("DiffrMainWindow")
        setupUI()
        initializeEmptyState()
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(containerView.leftEditor.textView)
    }

    private func makePaneTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = NSColor.secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        return label
    }

    private func setupUI() {
        guard let window = self.window else { return }

        let rootView = NSView()
        rootView.wantsLayer = true
        window.contentView = rootView

        // Top Header Visual Effect Bar (frosted glass vibrancy)
        let visualEffect = NSVisualEffectView()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.material = .headerView
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        headerBar = visualEffect
        rootView.addSubview(headerBar)

        // 1px hairline border at bottom of headerBar (redraws on appearance change)
        let bottomBorder = SeparatorLineView()
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(bottomBorder)

        // --- Left Section: Source Pane Tag & Action ---
        leftTitleLabel = makePaneTitle("")

        leftStatLabel = NSTextField(labelWithString: "")
        leftStatLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        leftStatLabel.textColor = DiffTheme.deletionIndicatorColor
        leftStatLabel.isEditable = false
        leftStatLabel.isSelectable = false
        leftStatLabel.isBezeled = false
        leftStatLabel.drawsBackground = false
        leftStatLabel.isHidden = true

        copyAllRightBtn = ModernPillButton(
            symbol: "arrow.right.to.line",
            accessibilityLabel: "Copy all to right pane",
            target: self,
            action: #selector(copyAllRightClicked)
        )
        copyAllRightBtn.toolTip = "Replace the modified pane with the original text (undoable)"

        let leftStack = NSStackView(views: [leftTitleLabel, leftStatLabel, copyAllRightBtn])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 6.0
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(leftStack)

        // --- Center Section (the middle separator): navigation, flip sides, invisibles ---
        prevChangeBtn = ModernPillButton(
            symbol: "chevron.up",
            accessibilityLabel: "Jump to previous change",
            target: self,
            action: #selector(prevChangeClicked)
        )
        prevChangeBtn.toolTip = "Jump to previous change (⌘[)"

        nextChangeBtn = ModernPillButton(
            symbol: "chevron.down",
            accessibilityLabel: "Jump to next change",
            target: self,
            action: #selector(nextChangeClicked)
        )
        nextChangeBtn.toolTip = "Jump to next change (⌘])"

        flipSidesBtn = ModernPillButton(
            symbol: "arrow.left.arrow.right",
            accessibilityLabel: "Flip sides, swapping left and right panes",
            target: self,
            action: #selector(flipSidesClicked)
        )
        flipSidesBtn.toolTip = "Swap left and right pane contents (undoable)"

        invisiblesCheckbox = ModernPillButton(
            symbol: "paragraphsign",
            accessibilityLabel: "Show invisible characters",
            isToggle: true,
            target: self,
            action: #selector(toggleInvisibles(_:))
        )
        invisiblesCheckbox.accentTintWhenActive = true
        invisiblesCheckbox.toolTip = "Show invisible characters (⇧⌘I)"

        // Two quiet clusters — navigation and view tools — separated by whitespace, not chrome.
        let navStack = NSStackView(views: [prevChangeBtn, nextChangeBtn])
        navStack.orientation = .horizontal
        navStack.spacing = 2.0
        let toolStack = NSStackView(views: [flipSidesBtn, invisiblesCheckbox])
        toolStack.orientation = .horizontal
        toolStack.spacing = 2.0

        let centerStack = NSStackView(views: [navStack, toolStack])
        centerStack.orientation = .horizontal
        centerStack.alignment = .centerY
        centerStack.spacing = 18.0
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(centerStack)

        // --- Right Section: Target Action, Tag & Stat ---
        copyAllLeftBtn = ModernPillButton(
            symbol: "arrow.left.to.line",
            accessibilityLabel: "Copy all to left pane",
            target: self,
            action: #selector(copyAllLeftClicked)
        )
        copyAllLeftBtn.toolTip = "Replace the original pane with the modified text (undoable)"

        rightTitleLabel = makePaneTitle("")

        rightStatLabel = NSTextField(labelWithString: "")
        rightStatLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        rightStatLabel.textColor = DiffTheme.additionIndicatorColor
        rightStatLabel.isEditable = false
        rightStatLabel.isSelectable = false
        rightStatLabel.isBezeled = false
        rightStatLabel.drawsBackground = false
        rightStatLabel.isHidden = true

        let rightStack = NSStackView(views: [copyAllLeftBtn, rightTitleLabel, rightStatLabel])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 6.0
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(rightStack)

        // Main Diff Container View
        containerView = DiffContainerView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(containerView)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: rootView.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 48),

            bottomBorder.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),

            // Left Stack (accounting for traffic lights window buttons)
            leftStack.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 84),
            leftStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            // Center Group
            centerStack.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            // Right Stack
            rightStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            containerView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        // Prevent overlap at low priority so minimal window width is never artificially constrained
        let leftOverlap = leftStack.trailingAnchor.constraint(lessThanOrEqualTo: centerStack.leadingAnchor, constant: -12)
        leftOverlap.priority = .defaultLow
        leftOverlap.isActive = true

        let rightOverlap = rightStack.leadingAnchor.constraint(greaterThanOrEqualTo: centerStack.trailingAnchor, constant: 12)
        rightOverlap.priority = .defaultLow
        rightOverlap.isActive = true

        // Setup coordinators
        diffCoordinator = DiffCoordinator(
            leftEditor: containerView.leftEditor,
            rightEditor: containerView.rightEditor
        )

        diffCoordinator.onDiffUpdated = { [weak self] result in
            self?.updateStats(result: result)
        }

        scrollCoordinator = DiffScrollCoordinator()
        scrollCoordinator.attach(
            left: containerView.leftEditor,
            right: containerView.rightEditor
        )

        containerView.leftEditor.textView.onFileDropped = { [weak self] url in
            self?.loadFile(at: url, into: .left)
        }
        containerView.rightEditor.textView.onFileDropped = { [weak self] url in
            self?.loadFile(at: url, into: .right)
        }
    }

    public func initializeEmptyState() {
        diffCoordinator.setInitialTexts(left: "", right: "")
        // Opening the window must not leave "undo typing nothing" on the stack.
        window?.undoManager?.removeAllActions()
        updateStats(result: diffCoordinator.diffResult)
        window?.makeFirstResponder(containerView.leftEditor.textView)
    }

    private func updateStats(result: DiffResult) {
        refreshDocumentState()
        let hasChanges = !result.hunks.isEmpty
        prevChangeBtn.isEnabled = hasChanges
        nextChangeBtn.isEnabled = hasChanges

        let leftEmpty = containerView.leftEditor.textStorage.length == 0
        let rightEmpty = containerView.rightEditor.textStorage.length == 0
        copyAllRightBtn.isEnabled = hasChanges
        copyAllLeftBtn.isEnabled = hasChanges
        flipSidesBtn.isEnabled = !(leftEmpty && rightEmpty) || !documents.isEmpty

        if leftEmpty && rightEmpty {
            leftStatLabel.isHidden = true
            rightStatLabel.isHidden = true
        } else if result.isIdentical {
            leftStatLabel.isHidden = true
            rightStatLabel.isHidden = true
        } else {
            if result.deletionsCount > 0 {
                leftStatLabel.stringValue = "-\(result.deletionsCount)"
                leftStatLabel.isHidden = false
            } else {
                leftStatLabel.isHidden = true
            }
            if result.additionsCount > 0 {
                rightStatLabel.stringValue = "+\(result.additionsCount)"
                rightStatLabel.isHidden = false
            } else {
                rightStatLabel.isHidden = true
            }
        }
    }

    // MARK: - Actions

    private var focusedEditor: DiffEditorView? {
        let responder = window?.firstResponder
        if responder === containerView.leftEditor.textView { return containerView.leftEditor }
        if responder === containerView.rightEditor.textView { return containerView.rightEditor }
        return nil
    }

    @objc public func prevChangeClicked() {
        diffCoordinator.jumpToPreviousHunk()
    }

    @objc public func nextChangeClicked() {
        diffCoordinator.jumpToNextHunk()
    }

    @objc public func copyChangeToRight(_ sender: Any?) {
        diffCoordinator.copyCurrentHunk(direction: .leftToRight, focusedEditor: focusedEditor)
    }

    @objc public func copyChangeToLeft(_ sender: Any?) {
        diffCoordinator.copyCurrentHunk(direction: .rightToLeft, focusedEditor: focusedEditor)
    }

    @objc public func copyAllRightClicked() {
        diffCoordinator.copyAll(direction: .leftToRight)
    }

    @objc public func copyAllLeftClicked() {
        diffCoordinator.copyAll(direction: .rightToLeft)
    }

    @objc public func flipSidesClicked() {
        guard containerView.leftEditor.textStorage.length > 0 ||
              containerView.rightEditor.textStorage.length > 0 ||
              !documents.isEmpty else {
            return
        }

        let undoManager = window?.undoManager
        undoManager?.beginUndoGrouping()

        diffCoordinator.flipSides()
        swapDocuments()

        undoManager?.setActionName("Flip Sides")
        undoManager?.endUndoGrouping()

        if let focused = focusedEditor {
            window?.makeFirstResponder(focused.textView)
        }
    }

    private func swapDocuments() {
        let oldLeft = documents[.left]
        let oldRight = documents[.right]
        if oldLeft == nil && oldRight == nil { return }

        documents[.left] = oldRight
        documents[.right] = oldLeft
        refreshDocumentState()

        window?.undoManager?.registerUndo(withTarget: self) { target in
            target.swapDocuments()
        }
    }

    @objc public func clearAllClicked() {
        confirmUnsavedChanges(for: EditorSide.allCases) { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.documents.removeAll()
            self.diffCoordinator.clearAll()
            self.refreshDocumentState()
            self.window?.makeFirstResponder(self.containerView.leftEditor.textView)
        }
    }

    @objc private func toggleInvisibles(_ sender: NSButton) {
        diffCoordinator.setShowsInvisibles(sender.state == .on)
    }

    @objc public func toggleInvisiblesFromMenu(_ sender: Any?) {
        invisiblesCheckbox.state = (invisiblesCheckbox.state == .on) ? .off : .on
        diffCoordinator.setShowsInvisibles(invisiblesCheckbox.state == .on)
    }

    @objc public func openInLeftPane(_ sender: Any?) {
        presentOpenPanel(for: .left)
    }

    @objc public func openInRightPane(_ sender: Any?) {
        presentOpenPanel(for: .right)
    }

    private func presentOpenPanel(for side: EditorSide) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = side == .left ? "Choose the original file" : "Choose the modified file"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadFile(at: url, into: side)
        }
    }

    public func loadFile(at url: URL, into side: EditorSide, completion: ((Bool) -> Void)? = nil) {
        // Replacing a pane must not silently drop its unsaved edits.
        confirmUnsavedChanges(for: [side]) { [weak self] proceed in
            guard let self = self, proceed else {
                completion?(false)
                return
            }
            do {
                let loaded = try TextFileLoader.loadFile(url: url)
                self.diffCoordinator.loadText(loaded.text, into: side)
                self.documents[side] = PaneDocument(loaded: loaded)
                self.refreshDocumentState()
                completion?(true)
            } catch {
                self.presentError(title: "Couldn’t open “\(url.lastPathComponent)”", error: error) { completion?(false) }
            }
        }
    }

    /// Loads several files one after another (first → left, second → right), so prompts never overlap.
    public func loadFiles(_ urls: [URL]) {
        let pairs = Array(zip(urls.prefix(2), [EditorSide.left, .right]))
        func next(_ index: Int) {
            guard index < pairs.count else { return }
            loadFile(at: pairs[index].0, into: pairs[index].1) { _ in next(index + 1) }
        }
        next(0)
    }

    // MARK: - Documents & saving

    private func editor(for side: EditorSide) -> DiffEditorView {
        return side == .left ? containerView.leftEditor : containerView.rightEditor
    }

    private func titleLabel(for side: EditorSide) -> NSTextField {
        return side == .left ? leftTitleLabel : rightTitleLabel
    }

    public func isDirty(_ side: EditorSide) -> Bool {
        guard let document = documents[side] else { return false }
        return document.isDirty(currentText: editor(for: side).text)
    }

    /// Only file-backed panes count: pasted scratch text is not a document and never nags on close.
    public var hasUnsavedChanges: Bool {
        return !discardConfirmed && EditorSide.allCases.contains { isDirty($0) }
    }

    public func refreshDocumentState() {
        for side in EditorSide.allCases {
            let label = titleLabel(for: side)
            if let document = documents[side] {
                label.stringValue = "\(document.url.lastPathComponent)\(isDirty(side) ? " — Edited" : "")"
                label.toolTip = "\(document.url.path) (\(document.encoding.displayName))"
                label.isHidden = false
            } else {
                label.stringValue = ""
                label.toolTip = nil
                label.isHidden = true
            }
        }
        // Shows the "unsaved" dot in the window's close button.
        window?.isDocumentEdited = EditorSide.allCases.contains { isDirty($0) }
    }

    private var focusedSide: EditorSide? {
        return focusedEditor?.side
    }

    @objc public func savePane(_ sender: Any?) {
        guard let side = focusedSide else { NSSound.beep(); return }
        save(side: side, chooseLocation: false) { _ in }
    }

    @objc public func savePaneAs(_ sender: Any?) {
        guard let side = focusedSide else { NSSound.beep(); return }
        save(side: side, chooseLocation: true) { _ in }
    }

    @objc public func saveBothPanes(_ sender: Any?) {
        saveSequentially(EditorSide.allCases) { _ in }
    }

    private func saveSequentially(_ sides: [EditorSide], completion: @escaping (Bool) -> Void) {
        guard let side = sides.first else {
            completion(true)
            return
        }
        save(side: side, chooseLocation: false) { [weak self] saved in
            guard saved else {
                completion(false)
                return
            }
            self?.saveSequentially(Array(sides.dropFirst()), completion: completion)
        }
    }

    /// Saves a pane to its file (or asks where, for untitled panes / Save As).
    public func save(side: EditorSide, chooseLocation: Bool, completion: @escaping (Bool) -> Void) {
        guard let window = window else {
            completion(false)
            return
        }

        if !chooseLocation, let document = documents[side] {
            guard document.hasChangedOnDisk else {
                write(side: side, to: document.url, encoding: document.encoding, completion: completion)
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(document.url.lastPathComponent)” was changed by another application."
            alert.informativeText = "Saving will overwrite the changes made on disk since you opened it."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Overwrite")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertSecondButtonReturn else {
                    completion(false)
                    return
                }
                self?.write(side: side, to: document.url, encoding: document.encoding, completion: completion)
            }
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.message = side == .left ? "Save the original (left) pane" : "Save the modified (right) pane"
        if let existing = documents[side]?.url {
            panel.directoryURL = existing.deletingLastPathComponent()
            panel.nameFieldStringValue = existing.lastPathComponent
        } else {
            panel.directoryURL = documents[side == .left ? .right : .left]?.url.deletingLastPathComponent()
            panel.nameFieldStringValue = side == .left ? "Original.txt" : "Modified.txt"
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else {
                completion(false)
                return
            }
            // NSSavePanel already confirmed replacing an existing file.
            self.write(side: side, to: url, encoding: self.documents[side]?.encoding ?? .utf8, completion: completion)
        }
    }

    private func write(side: EditorSide, to url: URL, encoding: TextFileEncoding, completion: @escaping (Bool) -> Void) {
        let text = editor(for: side).text
        do {
            let date = try TextFileLoader.save(text, to: url, encoding: encoding)
            documents[side] = PaneDocument(url: url, encoding: encoding, savedText: text, modificationDate: date)
            refreshDocumentState()
            completion(true)
        } catch TextFileLoadError.unencodable where encoding != .utf8 {
            // Never write lossy bytes silently; offer UTF-8 instead.
            guard let window = window else {
                completion(false)
                return
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(url.lastPathComponent)” can’t be saved as \(encoding.displayName)."
            alert.informativeText = "The text contains characters that \(encoding.displayName) cannot represent. Save it as UTF-8 instead?"
            alert.addButton(withTitle: "Save as UTF-8")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else {
                    completion(false)
                    return
                }
                self?.write(side: side, to: url, encoding: .utf8, completion: completion)
            }
        } catch {
            presentError(title: "Couldn’t save “\(url.lastPathComponent)”", error: error) { completion(false) }
        }
    }

    /// Asks before discarding unsaved edits in `sides`; completion(true) means it is safe to proceed.
    public func confirmUnsavedChanges(for sides: [EditorSide], completion: @escaping (Bool) -> Void) {
        let dirtySides = sides.filter { isDirty($0) }
        guard !dirtySides.isEmpty, !discardConfirmed, let window = window else {
            completion(true)
            return
        }
        let names = dirtySides.compactMap { documents[$0]?.url.lastPathComponent }.map { "“\($0)”" }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save the changes made to \(names.joined(separator: " and "))?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = [.command]
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                self?.saveSequentially(dirtySides, completion: completion)
            case .alertThirdButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }
        confirmUnsavedChanges(for: EditorSide.allCases) { [weak self] proceed in
            guard let self = self, proceed else { return }
            self.discardConfirmed = true
            self.window?.close()
        }
        return false
    }

    private func presentError(title: String, error: Error, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        if let window = window {
            alert.beginSheetModal(for: window) { _ in completion() }
        } else {
            alert.runModal()
            completion()
        }
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(nextChangeClicked),
             #selector(prevChangeClicked),
             #selector(copyChangeToRight(_:)),
             #selector(copyChangeToLeft(_:)),
             #selector(copyAllRightClicked),
             #selector(copyAllLeftClicked):
            return diffCoordinator.hasChanges
        case #selector(flipSidesClicked):
            return containerView.leftEditor.textStorage.length > 0 || containerView.rightEditor.textStorage.length > 0 || !documents.isEmpty
        case #selector(clearAllClicked):
            return containerView.leftEditor.textStorage.length > 0 || containerView.rightEditor.textStorage.length > 0
        case #selector(savePane(_:)), #selector(savePaneAs(_:)):
            guard let side = focusedSide else {
                menuItem.title = menuItem.action == #selector(savePane(_:)) ? "Save Pane" : "Save Pane As…"
                return false
            }
            let pane = side == .left ? "Left" : "Right"
            menuItem.title = menuItem.action == #selector(savePane(_:)) ? "Save \(pane) Pane" : "Save \(pane) Pane As…"
            return true
        case #selector(saveBothPanes(_:)):
            return containerView.leftEditor.textStorage.length > 0 || containerView.rightEditor.textStorage.length > 0
                || !documents.isEmpty
        case #selector(toggleInvisiblesFromMenu(_:)):
            menuItem.state = invisiblesCheckbox.state
            return true
        default:
            return true
        }
    }

    // MARK: - Double ⌘Q Quit Confirmation HUD

    public var isQuitHUDVisible: Bool {
        return quitHUDView != nil
    }

    public func showQuitHUD(timeout: TimeInterval, onCancel: @escaping () -> Void) {
        dismissQuitHUD(animated: false)

        guard let contentView = window?.contentView else { return }

        let hud = QuitConfirmationHUDView()
        hud.translatesAutoresizingMaskIntoConstraints = false
        hud.alphaValue = 0.0
        contentView.addSubview(hud)

        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hud.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        quitHUDView = hud

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            hud.animator().alphaValue = 1.0
        }

        quitHUDDismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            onCancel()
            self?.dismissQuitHUD(animated: true)
        }

        quitEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            if event.type == .keyDown,
               event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "q" {
                return event
            }
            onCancel()
            self?.dismissQuitHUD(animated: true)
            return event
        }
    }

    public func dismissQuitHUD(animated: Bool) {
        quitHUDDismissTimer?.invalidate()
        quitHUDDismissTimer = nil

        if let monitor = quitEventMonitor {
            NSEvent.removeMonitor(monitor)
            quitEventMonitor = nil
        }

        guard let hud = quitHUDView else { return }
        quitHUDView = nil

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.20
                hud.animator().alphaValue = 0.0
            }, completionHandler: {
                hud.removeFromSuperview()
            })
        } else {
            hud.removeFromSuperview()
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        if isQuitHUDVisible {
            dismissQuitHUD(animated: true)
            return
        }
        super.cancelOperation(sender)
    }

    deinit {
        if let monitor = quitEventMonitor {
            NSEvent.removeMonitor(monitor)
            quitEventMonitor = nil
        }
    }
}

