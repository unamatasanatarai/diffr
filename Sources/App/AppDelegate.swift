import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var mainWindowController: MainWindowController?

    // Double ⌘Q to quit
    private var lastQuitAttemptTimestamp: TimeInterval = 0
    public var doubleQuitTimeout: TimeInterval = 1.75
    public var terminateHandler: ((Any?) -> Void)?

    // The window exists before launch finishes so files passed at launch (open urls) have a target.
    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        mainWindowController = MainWindowController()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindowController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        // Files dropped on the Dock icon / "Open With": first → left, second → right.
        mainWindowController?.loadFiles(urls)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = mainWindowController, controller.hasUnsavedChanges else { return .terminateNow }
        controller.showWindow(nil)
        controller.confirmUnsavedChanges(for: EditorSide.allCases) { proceed in
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    // MARK: - Double ⌘Q Quit Handling

    @objc public func quitRequested(_ sender: Any?) {
        let isShortcut = (NSApp.currentEvent?.type == .keyDown)
        handleQuitRequest(isKeyboardShortcut: isShortcut, sender: sender)
    }

    public func handleQuitRequest(isKeyboardShortcut: Bool, sender: Any? = nil) {
        let doTerminate: (Any?) -> Void = { [weak self] s in
            if let custom = self?.terminateHandler {
                custom(s)
            } else {
                NSApp.terminate(s)
            }
        }

        // If clicked from the menu bar with mouse, quit immediately (prompting for unsaved changes if needed)
        guard isKeyboardShortcut else {
            mainWindowController?.dismissQuitHUD(animated: false)
            doTerminate(sender)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastQuitAttemptTimestamp

        if lastQuitAttemptTimestamp > 0 && elapsed <= doubleQuitTimeout {
            // Second ⌘Q confirmed within timeout
            lastQuitAttemptTimestamp = 0
            mainWindowController?.dismissQuitHUD(animated: false)
            doTerminate(sender)
        } else {
            // First ⌘Q: record timestamp and prompt user
            lastQuitAttemptTimestamp = now
            if let controller = mainWindowController, controller.window?.isVisible == true {
                controller.showQuitHUD(timeout: doubleQuitTimeout) { [weak self] in
                    self?.lastQuitAttemptTimestamp = 0
                }
            } else {
                // Window not visible; reset timestamp after timeout
                Timer.scheduledTimer(withTimeInterval: doubleQuitTimeout, repeats: false) { [weak self] _ in
                    self?.lastQuitAttemptTimestamp = 0
                }
            }
        }
    }


    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appName = AppConfig.appName

        // 1. App Menu
        let appMenu = NSMenu()
        appMenu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        let quitItem = item("Quit \(appName)", #selector(quitRequested(_:)), "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        addSubmenu(appMenu, to: mainMenu)

        // 2. File Menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Open in Left Pane…", #selector(MainWindowController.openInLeftPane(_:)), "o"))
        fileMenu.addItem(item("Open in Right Pane…", #selector(MainWindowController.openInRightPane(_:)), "o", [.command, .option]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Save Pane", #selector(MainWindowController.savePane(_:)), "s"))
        fileMenu.addItem(item("Save Pane As…", #selector(MainWindowController.savePaneAs(_:)), "s", [.command, .shift]))
        fileMenu.addItem(item("Save Both Panes", #selector(MainWindowController.saveBothPanes(_:)), "s", [.command, .option]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Clear Both Panes", #selector(MainWindowController.clearAllClicked)))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        addSubmenu(fileMenu, to: mainMenu)

        // 3. Edit Menu (Undo, Redo, Cut, Copy, Paste, Find)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Undo", Selector(("undo:")), "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Delete", #selector(NSText.delete(_:))))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editMenu.addItem(.separator())

        let findMenu = NSMenu(title: "Find")
        let finderItems: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
            ("Find…", "f", [.command], .showFindInterface),
            ("Find and Replace…", "f", [.command, .option], .showReplaceInterface),
            ("Find Next", "g", [.command], .nextMatch),
            ("Find Previous", "g", [.command, .shift], .previousMatch),
            ("Use Selection for Find", "e", [.command], .setSearchString)
        ]
        for (title, key, modifiers, action) in finderItems {
            let finderItem = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
            finderItem.tag = action.rawValue
            findMenu.addItem(finderItem)
        }
        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)
        addSubmenu(editMenu, to: mainMenu)

        // 4. View Menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Show Invisibles", #selector(MainWindowController.toggleInvisiblesFromMenu(_:)), "i", [.command, .shift]))
        addSubmenu(viewMenu, to: mainMenu)

        // 5. Changes Menu
        let changesMenu = NSMenu(title: "Changes")
        changesMenu.addItem(item("Next Change", #selector(MainWindowController.nextChangeClicked), "]"))
        changesMenu.addItem(item("Previous Change", #selector(MainWindowController.prevChangeClicked), "["))
        changesMenu.addItem(.separator())
        let rightArrow = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        let leftArrow = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        changesMenu.addItem(item("Copy Change to Right", #selector(MainWindowController.copyChangeToRight(_:)), rightArrow, [.command, .option]))
        changesMenu.addItem(item("Copy Change to Left", #selector(MainWindowController.copyChangeToLeft(_:)), leftArrow, [.command, .option]))
        changesMenu.addItem(.separator())
        changesMenu.addItem(item("Copy All to Right", #selector(MainWindowController.copyAllRightClicked)))
        changesMenu.addItem(item("Copy All to Left", #selector(MainWindowController.copyAllLeftClicked)))
        changesMenu.addItem(.separator())
        changesMenu.addItem(item("Flip Sides", #selector(MainWindowController.flipSidesClicked)))
        addSubmenu(changesMenu, to: mainMenu)

        // 6. Window Menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to mainMenu: NSMenu) {
        let holder = NSMenuItem()
        holder.submenu = submenu
        mainMenu.addItem(holder)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
