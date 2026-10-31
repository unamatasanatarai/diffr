import AppKit

public final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    public private(set) var containerView: DiffContainerView!
    public private(set) var diffCoordinator: DiffCoordinator!
    public private(set) var scrollCoordinator: DiffScrollCoordinator!

    public private(set) var headerBar: NSView!
    public private(set) var statusCapsule: ModernStatusCapsuleView!
    public private(set) var prevChangeBtn: ModernPillButton!
    public private(set) var nextChangeBtn: ModernPillButton!
    public private(set) var invisiblesCheckbox: ModernPillButton!
    public private(set) var copyAllRightBtn: ModernPillButton!
    public private(set) var copyAllLeftBtn: ModernPillButton!
    public private(set) var clearBtn: ModernPillButton!
    public private(set) var leftTitleLabel: NSTextField!
    public private(set) var rightTitleLabel: NSTextField!

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1150, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 980, height: 480)
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
        leftTitleLabel = makePaneTitle("ORIGINAL")

        copyAllRightBtn = ModernPillButton(
            title: "Copy All ➔",
            target: self,
            action: #selector(copyAllRightClicked)
        )
        copyAllRightBtn.toolTip = "Replace the modified pane with the original text (undoable)"
        copyAllRightBtn.setAccessibilityLabel("Copy all to right pane")

        let leftStack = NSStackView(views: [leftTitleLabel, copyAllRightBtn])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 10.0
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(leftStack)

        // --- Center Section (the middle separator): stats, navigation, invisibles ---
        statusCapsule = ModernStatusCapsuleView()
        statusCapsule.translatesAutoresizingMaskIntoConstraints = false

        prevChangeBtn = ModernPillButton(
            title: "‹ Prev",
            target: self,
            action: #selector(prevChangeClicked)
        )
        prevChangeBtn.toolTip = "Previous change (⌘[)"
        prevChangeBtn.setAccessibilityLabel("Previous change")

        nextChangeBtn = ModernPillButton(
            title: "Next ›",
            target: self,
            action: #selector(nextChangeClicked)
        )
        nextChangeBtn.toolTip = "Next change (⌘])"
        nextChangeBtn.setAccessibilityLabel("Next change")

        invisiblesCheckbox = ModernPillButton(
            title: "¶ Invisibles",
            isToggle: true,
            target: self,
            action: #selector(toggleInvisibles(_:))
        )
        invisiblesCheckbox.accentTintWhenActive = true
        invisiblesCheckbox.toolTip = "Show invisible characters: spaces, tabs, line endings, non-breaking and zero-width characters (⇧⌘I)"
        invisiblesCheckbox.setAccessibilityLabel("Show invisible characters")

        let centerStack = NSStackView(views: [statusCapsule, prevChangeBtn, nextChangeBtn, invisiblesCheckbox])
        centerStack.orientation = .horizontal
        centerStack.alignment = .centerY
        centerStack.spacing = 8.0
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(centerStack)

        // --- Right Section: Target Action, Tag & Clear ---
        copyAllLeftBtn = ModernPillButton(
            title: "⬅ Copy All",
            target: self,
            action: #selector(copyAllLeftClicked)
        )
        copyAllLeftBtn.toolTip = "Replace the original pane with the modified text (undoable)"
        copyAllLeftBtn.setAccessibilityLabel("Copy all to left pane")

        rightTitleLabel = makePaneTitle("MODIFIED")

        clearBtn = ModernPillButton(
            title: "Clear",
            target: self,
            action: #selector(clearAllClicked)
        )
        clearBtn.toolTip = "Clear both panes (undoable with ⌘Z)"

        let rightStack = NSStackView(views: [copyAllLeftBtn, rightTitleLabel, clearBtn])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 10.0
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(rightStack)

        // Main Diff Container View
        containerView = DiffContainerView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(containerView)

        let buttonHeight: CGFloat = 26
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
            copyAllRightBtn.heightAnchor.constraint(equalToConstant: buttonHeight),

            // Center Group
            centerStack.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            prevChangeBtn.heightAnchor.constraint(equalToConstant: buttonHeight),
            prevChangeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            nextChangeBtn.heightAnchor.constraint(equalToConstant: buttonHeight),
            nextChangeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            invisiblesCheckbox.heightAnchor.constraint(equalToConstant: buttonHeight),

            // Right Stack
            rightStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -16),
            rightStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            copyAllLeftBtn.heightAnchor.constraint(equalToConstant: buttonHeight),
            clearBtn.heightAnchor.constraint(equalToConstant: buttonHeight),

            // Prevent overlap
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: centerStack.leadingAnchor, constant: -12),
            rightStack.leadingAnchor.constraint(greaterThanOrEqualTo: centerStack.trailingAnchor, constant: 12),

            containerView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

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
        let hasChanges = !result.hunks.isEmpty
        prevChangeBtn.isEnabled = hasChanges
        nextChangeBtn.isEnabled = hasChanges

        let leftEmpty = containerView.leftEditor.textStorage.length == 0
        let rightEmpty = containerView.rightEditor.textStorage.length == 0
        copyAllRightBtn.isEnabled = hasChanges
        copyAllLeftBtn.isEnabled = hasChanges
        clearBtn.isEnabled = !(leftEmpty && rightEmpty)

        if leftEmpty && rightEmpty {
            statusCapsule.setWaitingForInput()
        } else if result.isIdentical {
            statusCapsule.setIdentical()
        } else {
            statusCapsule.setDiff(
                hunksCount: result.hunks.count,
                additions: result.additionsCount,
                deletions: result.deletionsCount
            )
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

    @objc public func clearAllClicked() {
        diffCoordinator.clearAll()
        leftTitleLabel.stringValue = "ORIGINAL"
        leftTitleLabel.toolTip = nil
        rightTitleLabel.stringValue = "MODIFIED"
        rightTitleLabel.toolTip = nil
        window?.makeFirstResponder(containerView.leftEditor.textView)
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

    public func loadFile(at url: URL, into side: EditorSide) {
        do {
            let text = try TextFileLoader.load(url: url)
            diffCoordinator.loadText(text, into: side)
            let label = side == .left ? leftTitleLabel! : rightTitleLabel!
            label.stringValue = "\(side == .left ? "ORIGINAL" : "MODIFIED") · \(url.lastPathComponent)"
            label.toolTip = url.path
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't open “\(url.lastPathComponent)”"
            alert.informativeText = error.localizedDescription
            if let window = window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
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
        case #selector(clearAllClicked):
            return clearBtn.isEnabled
        case #selector(toggleInvisiblesFromMenu(_:)):
            menuItem.state = invisiblesCheckbox.state
            return true
        default:
            return true
        }
    }
}
