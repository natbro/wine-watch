import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?

    private var scan = WineScan()
    /// After a kill we poll hard for a few seconds so the badge drops promptly
    /// instead of sitting stale for most of a refresh interval.
    private var fastPollUntil: Date?
    private var isScanning = false

    private let maxListedProcesses = 14

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        menu.delegate = self
        statusItem.menu = menu

        updateIcon()
        refresh()
        restartTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = fastPollUntil.map { $0 > Date() ? 0.5 : Preferences.refreshInterval } ?? Preferences.refreshInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        // .common keeps the badge live while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if let until = fastPollUntil, until <= Date() {
            fastPollUntil = nil
            restartTimer()
        }
        refresh()
    }

    // MARK: - Scanning

    private func refresh(then completion: (() -> Void)? = nil) {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = WineScanner.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                self.scan = result
                self.updateIcon()
                if self.menu.numberOfItems > 0 { self.rebuildMenu() }
                completion?()
            }
        }
    }

    private func updateIcon() {
        let count = scan.count
        let showBadge = count > 0 || Preferences.showGreenBadgeWhenClear
        let color: NSColor = count > 0 ? .systemRed : .systemGreen

        statusItem.button?.image = GlassIcon.image(
            count: showBadge ? count : nil,
            color: color,
            dimmed: count == 0)

        var tooltip = count == 0 ? "No wine processes running" : "\(count) wine process\(count == 1 ? "" : "es") running"
        if !scan.hosts.isEmpty {
            tooltip += " — \(scan.hosts.joined(separator: ", ")) open"
        }
        statusItem.button?.toolTip = tooltip
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
        refresh()
    }

    func rebuildMenu() {
        menu.removeAllItems()

        let count = scan.count
        let header = NSMenuItem(
            title: count == 0
                ? "No wine processes"
                : "\(count) wine process\(count == 1 ? "" : "es")",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for host in scan.hosts {
            let item = NSMenuItem(title: "\(host) is running", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = "Managed by you, so WineWatch neither counts nor quits it."
            menu.addItem(item)
        }

        if count > 0 {
            menu.addItem(.separator())
            for process in scan.processes.prefix(maxListedProcesses) {
                menu.addItem(processItem(process))
            }
            if count > maxListedProcesses {
                let more = NSMenuItem(title: "…and \(count - maxListedProcesses) more", action: nil, keyEquivalent: "")
                more.isEnabled = false
                menu.addItem(more)
            }
        }

        menu.addItem(.separator())

        let closeAll = NSMenuItem(
            title: "Close Wine Processes",
            action: #selector(closeAll(_:)), keyEquivalent: "k")
        closeAll.target = self
        closeAll.isEnabled = count > 0
        closeAll.toolTip = "Quit every wine process, then force-quit anything still alive. Hold Option to skip straight to force-quit."
        menu.addItem(closeAll)

        let closeServices = NSMenuItem(
            title: "Close Wine Services Only",
            action: #selector(closeServices(_:)), keyEquivalent: "")
        closeServices.target = self
        closeServices.isEnabled = !scan.services.isEmpty
        closeServices.toolTip = "Quit wineserver and Wine's own Windows services, leaving application processes alone."
        menu.addItem(closeServices)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch Automatically at Startup",
            action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = LoginItem.isAvailable && LoginItem.isEnabled ? .on : .off
        launchAtLogin.isEnabled = LoginItem.isAvailable
        if !LoginItem.isAvailable {
            launchAtLogin.toolTip = "Only available when running from WineWatch.app."
        } else if LoginItem.requiresApproval {
            launchAtLogin.toolTip = "Approval needed in System Settings › General › Login Items."
        }
        menu.addItem(launchAtLogin)

        let intervalItem = NSMenuItem(title: "Update Every", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for interval in Preferences.allowedIntervals {
            let item = NSMenuItem(
                title: "\(Int(interval)) seconds",
                action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            item.state = Preferences.refreshInterval == interval ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let greenBadge = NSMenuItem(
            title: "Show Green Badge When Clear",
            action: #selector(toggleGreenBadge(_:)), keyEquivalent: "")
        greenBadge.target = self
        greenBadge.state = Preferences.showGreenBadgeWhenClear ? .on : .off
        menu.addItem(greenBadge)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit WineWatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func processItem(_ process: WineProcess) -> NSMenuItem {
        let item = NSMenuItem(title: "\(process.name)  ·  \(process.pid)", action: nil, keyEquivalent: "")
        item.toolTip = process.detail
        item.attributedTitle = NSAttributedString(
            string: item.title,
            attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.systemFontSize(for: .small)),
                .foregroundColor: process.kind == .app ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ])

        let submenu = NSMenu()
        let quit = NSMenuItem(title: "Quit \(process.name)", action: #selector(quitOne(_:)), keyEquivalent: "")
        quit.target = self
        quit.representedObject = process
        submenu.addItem(quit)

        let force = NSMenuItem(title: "Force Quit \(process.name)", action: #selector(forceQuitOne(_:)), keyEquivalent: "")
        force.target = self
        force.representedObject = process
        submenu.addItem(force)
        item.submenu = submenu

        return item
    }

    /// Builds the menu against the live process table and prints it, so the
    /// menu can be exercised without a menu bar (see `--selftest`).
    func dumpMenu() {
        scan = WineScanner.scan()
        rebuildMenu()

        func print(_ menu: NSMenu, indent: String) {
            for item in menu.items {
                let mark = item.isSeparatorItem ? "---" : (item.state == .on ? "[x]" : (item.isEnabled ? " · " : "   "))
                if !item.isSeparatorItem {
                    Swift.print("\(indent)\(mark) \(item.title)")
                } else {
                    Swift.print("\(indent)---")
                }
                if let submenu = item.submenu { print(submenu, indent: indent + "    ") }
            }
        }
        print(menu, indent: "")
        Swift.print("\n\(menu.numberOfItems) top-level items, icon width \(GlassIcon.image(count: scan.count, color: .systemRed, dimmed: false).size.width)")
    }

    // MARK: - Actions

    @objc private func closeAll(_ sender: NSMenuItem) {
        kill(scan.processes, force: NSEvent.modifierFlags.contains(.option))
    }

    @objc private func closeServices(_ sender: NSMenuItem) {
        kill(scan.services, force: NSEvent.modifierFlags.contains(.option))
    }

    @objc private func quitOne(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? WineProcess else { return }
        kill([process], force: false)
    }

    @objc private func forceQuitOne(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? WineProcess else { return }
        kill([process], force: true)
    }

    private func kill(_ processes: [WineProcess], force: Bool) {
        guard !processes.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            WineScanner.terminate(processes, force: force)
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
        // Poll hard for a few seconds so the badge tracks the teardown.
        fastPollUntil = Date().addingTimeInterval(8)
        restartTimer()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        do {
            try LoginItem.set(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = enable ? "Couldn’t enable launch at startup" : "Couldn’t disable launch at startup"
            alert.informativeText = LoginItem.requiresApproval
                ? "WineWatch needs approval in System Settings › General › Login Items."
                : "\(error.localizedDescription)\n\nMove WineWatch.app to /Applications and try again."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { LoginItem.openSystemSettings() }
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Preferences.refreshInterval = interval
        if fastPollUntil == nil { restartTimer() }
    }

    @objc private func toggleGreenBadge(_ sender: NSMenuItem) {
        Preferences.showGreenBadgeWhenClear.toggle()
        updateIcon()
    }
}
