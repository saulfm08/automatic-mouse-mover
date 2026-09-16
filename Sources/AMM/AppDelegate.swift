import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mover: MouseMover!
    private var settings = Settings.load()

    private var toggleItem: NSMenuItem!
    private var statusLabelItem: NSMenuItem!
    private var intervalMenu: NSMenu!
    private var distanceMenu: NSMenu!

    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        mover = MouseMover(settings: settings)
        mover.onPermissionProblem = { [weak self] in self?.presentPermissionAlert() }
        mover.onNudge = { [weak self] _ in self?.refreshStatusLabel() }

        buildStatusItem()

        if settings.isEnabled {
            mover.start()
        }
        updateMenuState()

        // Keep the "last nudge / idle" line honest while the menu is closed,
        // so it is already correct the moment the user opens it.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStatusLabel()
        }

        // Ask up front if we cannot move the cursor, rather than waiting for
        // the first silent failure some minutes from now.
        if !AXIsProcessTrusted() {
            presentPermissionAlert()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        mover.stop()
    }

    // MARK: - Menu construction

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // A template SF Symbol adapts to light/dark menu bars and to tinting,
            // which the original's bitmap icon could not do.
            let image = NSImage(systemSymbolName: "cursorarrow.motionlines",
                                accessibilityDescription: "Automatic Mouse Mover")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self

        statusLabelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Pause",
                                action: #selector(toggleRunning),
                                keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // Idle interval submenu
        let intervalItem = NSMenuItem(title: "Move after", action: nil, keyEquivalent: "")
        intervalMenu = NSMenu()
        for interval in Settings.availableIntervals {
            let item = NSMenuItem(title: Settings.label(forInterval: interval),
                                  action: #selector(selectInterval(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        // Nudge distance submenu
        let distanceItem = NSMenuItem(title: "Move by", action: nil, keyEquivalent: "")
        distanceMenu = NSMenu()
        for distance in Settings.availableDistances {
            let item = NSMenuItem(title: distance == 1 ? "1 pixel" : "\(distance) pixels",
                                  action: #selector(selectDistance(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = distance
            distanceMenu.addItem(item)
        }
        distanceItem.submenu = distanceMenu
        menu.addItem(distanceItem)
        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Open Accessibility Settings…",
                                         action: #selector(openAccessibilitySettings),
                                         keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let aboutItem = NSMenuItem(title: "About AMM",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleRunning() {
        settings.isEnabled.toggle()
        settings.save()
        if settings.isEnabled {
            mover.start()
        } else {
            mover.stop()
        }
        updateMenuState()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        settings.idleInterval = interval
        settings.save()
        mover.update(settings: settings)
        updateMenuState()
    }

    @objc private func selectDistance(_ sender: NSMenuItem) {
        guard let distance = sender.representedObject as? Int else { return }
        settings.nudgeDistance = distance
        settings.save()
        mover.update(settings: settings)
        updateMenuState()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Automatic Mouse Mover"
        alert.informativeText = """
            A native Apple silicon rebuild for macOS 26 and later.

            Keeps this Mac awake by nudging the cursor after a period \
            of inactivity.

            Based on the original by Prashant Gupta:
            github.com/prashantgupta24/automatic-mouse-mover
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - State reflection

    private func updateMenuState() {
        toggleItem.title = settings.isEnabled ? "Pause" : "Resume"

        for item in intervalMenu.items {
            let interval = item.representedObject as? TimeInterval
            item.state = (interval == settings.idleInterval) ? .on : .off
        }
        for item in distanceMenu.items {
            let distance = item.representedObject as? Int
            item.state = (distance == settings.nudgeDistance) ? .on : .off
        }

        // Dim the icon while paused, so state is visible without opening the menu.
        statusItem.button?.appearsDisabled = !settings.isEnabled

        refreshStatusLabel()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()

    private func refreshStatusLabel() {
        guard settings.isEnabled else {
            statusLabelItem.title = "Paused"
            return
        }

        let idle = Int(MouseMover.systemIdleTime())
        if let last = mover.lastNudge {
            statusLabelItem.title =
                "Last move \(Self.timeFormatter.string(from: last)) · idle \(idle)s"
        } else {
            statusLabelItem.title = "Active · idle \(idle)s"
        }
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
            Automatic Mouse Mover cannot move the cursor until macOS grants it \
            Accessibility access.

            Open System Settings → Privacy & Security → Accessibility, then \
            enable Automatic Mouse Mover.

            If it is already listed and enabled, remove it with the "−" button \
            and add it again — macOS keeps permissions tied to a specific copy \
            of the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusLabel()
    }
}
