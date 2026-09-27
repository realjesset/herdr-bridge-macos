import AppKit
import UserNotifications
import BridgeCore

private final class Selection: NSObject {
    let id: String, token: UUID, epoch: UUID
    init(_ entry: Bridge.Entry, epoch: UUID) {
        id = entry.service.id; token = entry.token; self.epoch = epoch
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let bridge = Bridge()
    private var item: NSStatusItem!
    private var notifications: UNUserNotificationCenter?
    private var notificationStatus = "Checking permission…"
    private var notificationResult = ""
    private var notificationTimer: Timer?
    private var notificationTimes: [TimeInterval] = []

    private func refreshNotificationSettings(retryPending: Bool = false) {
        guard let center = notifications else {
            notificationStatus = "Unavailable — launch the .app bundle"
            render(); return
        }
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let allowed: Bool
                switch settings.authorizationStatus {
                case .authorized:
                    allowed = true
                    self.notificationStatus = settings.alertSetting == .enabled
                        ? "Enabled" : "Allowed — banners disabled in macOS"
                case .provisional:
                    allowed = true
                    self.notificationStatus = "Quiet delivery — check Notification Center"
                case .denied:
                    allowed = false
                    self.notificationStatus = "Blocked — enable in System Settings"
                case .notDetermined:
                    allowed = false
                    self.notificationStatus = "Not enabled"
                @unknown default:
                    allowed = false
                    self.notificationStatus = "Unknown permission status"
                }
                if retryPending && allowed {
                    for entry in self.bridge.entries.values {
                        if case .pending = entry.state {
                            self.notify(entry, epoch: self.bridge.generation)
                        }
                    }
                }
                self.render()
            }
        }
    }
    private var alias: String {
        get { UserDefaults.standard.string(forKey: "SSHAlias") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "SSHAlias") }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        item.button?.setAccessibilityLabel("Herdr Bridge")
        item.button?.toolTip = "Herdr Bridge — explicit loopback forwarding"
        if Bundle.main.bundleURL.pathExtension == "app" {
            let center = UNUserNotificationCenter.current()
            notifications = center; center.delegate = self
            let forward = UNNotificationAction(identifier: "forward", title: "Forward", options: [.authenticationRequired])
            let ignore = UNNotificationAction(identifier: "ignore", title: "Ignore", options: [])
            center.setNotificationCategories([UNNotificationCategory(identifier: "service", actions: [forward, ignore], intentIdentifiers: [], options: [])])
            // No prompts on launch. Existing OS consent is respected; granting consent
            // or denying it does not change pending services or approval state.
        }
        bridge.changed = { [weak self] in self?.render() }
        bridge.discovered = { [weak self] entry, epoch in self?.notify(entry, epoch: epoch) }
        bridge.clearNotifications = { [weak self] in
            self?.notifications?.removeAllDeliveredNotifications()
            self?.notifications?.removeAllPendingNotificationRequests()
        }
        render()
        refreshNotificationSettings()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshNotificationSettings()
        }
    }
    private func row(_ title: String, action: Selector? = nil, selection: Selection? = nil) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self; row.representedObject = selection
        return row
    }
    private func statusIcon(ready: Bool) -> NSImage {
        // Render real colour pixels; template images may be recoloured by the menu bar.
        let colour = ready
            ? NSColor(srgbRed: 0.15, green: 0.85, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 1.0, green: 0.60, blue: 0.12, alpha: 1)
        let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: "Herdr Bridge")
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            if let symbol = symbol {
                symbol.draw(in: rect)
                NSGraphicsContext.current?.compositingOperation = .sourceIn
                colour.setFill()
                NSBezierPath(rect: rect).fill()
            } else {
                colour.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
    private func render() {
        let menu = NSMenu()
        menu.addItem(row(bridge.status))
        menu.addItem(row("SSH alias: \(alias.isEmpty ? "Not set" : alias)", action: #selector(editAlias)))
        menu.addItem(row(bridge.connected ? "Disconnect" : "Connect", action: #selector(toggleConnection)))
        menu.addItem(row("Notifications: \(notificationStatus)"))
        if !notificationResult.isEmpty { menu.addItem(row(notificationResult)) }
        menu.addItem(row("Enable / Retry Pending Notifications…", action: #selector(enableNotifications)))
        menu.addItem(row("Send Test Notification", action: #selector(testNotification)))
        menu.addItem(row("Open Notification Settings…", action: #selector(openNotificationSettings)))
        menu.addItem(.separator())
        if bridge.entries.isEmpty { menu.addItem(row("No detected services")) }
        for entry in bridge.entries.values.sorted(by: { ($0.service.port, $0.service.id) < ($1.service.port, $1.service.id) }) {
            let s = entry.service
            let selection = Selection(entry, epoch: bridge.generation)
            let parent = row("\(s.project.isEmpty ? s.pane : s.project) · \(s.host):\(s.port)")
            let actions = NSMenu()
            actions.addItem(row("Pane: \(s.pane)"))
            switch entry.state {
            case .pending:
                actions.addItem(row("Forward", action: #selector(forward), selection: selection))
                actions.addItem(row("Ignore", action: #selector(ignore), selection: selection))
            case .activating:
                actions.addItem(row("Connecting…"))
                actions.addItem(row("Stop", action: #selector(stop), selection: selection))
            case .active:
                actions.addItem(row("Active · 127.0.0.1:\(s.port)"))
                actions.addItem(row("Open HTTP in Browser", action: #selector(openHTTP), selection: selection))
                actions.addItem(row("Stop", action: #selector(stop), selection: selection))
            case .stopping: actions.addItem(row("Stopping…"))
            case .ignored: actions.addItem(row("Ignored / stopped for this connection"))
            case .error(let message): actions.addItem(row("Error: \(message)"))
            }
            parent.submenu = actions; menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(row("Quit Herdr Bridge", action: #selector(quit)))
        item.menu = menu
        // Green means the SSH detector has delivered a valid snapshot,
        // not merely that an SSH process has started.
        item.button?.contentTintColor = nil
        item.button?.image = statusIcon(ready: bridge.detectorReady)
        item.button?.toolTip = "Herdr Bridge — \(bridge.status)"
    }
    @objc private func editAlias() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SSH Host Alias"
        alert.informativeText = "Use an existing trusted ~/.ssh/config alias with a known host key and public-key authentication. Editing disconnects the current session."
        let field = NSTextField(string: alias)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard SSHValidation.alias(field.stringValue) else {
            let error = NSAlert(); error.messageText = "Invalid SSH alias"
            error.informativeText = "Use letters, digits, _, ., @ or -, without a leading -. Maximum 255 ASCII characters."
            error.runModal(); return
        }
        bridge.disconnect(); alias = field.stringValue; render()
    }
    @objc private func toggleConnection() {
        if bridge.connected { bridge.disconnect() }
        else if alias.isEmpty { editAlias() }
        else { bridge.connect(alias: alias) }
    }
    @objc private func enableNotifications() {
        guard let center = notifications else { refreshNotificationSettings(); return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.notificationResult = error.map { "Permission error: \($0.localizedDescription)" } ?? ""
                self.refreshNotificationSettings(retryPending: true)
            }
        }
    }
    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func testNotification() {
        guard let center = notifications else { refreshNotificationSettings(); return }
        let content = UNMutableNotificationContent()
        content.title = "Herdr Bridge notification test"
        content.body = "Notifications are reaching this Mac. No port was forwarded."
        center.add(UNNotificationRequest(identifier: "bridge-test", content: content,
                   trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))) { [weak self] error in
            DispatchQueue.main.async {
                self?.notificationResult = error.map { "Test failed: \($0.localizedDescription)" }
                    ?? "Test submitted to macOS — delivery may be suppressed by Focus"
                self?.refreshNotificationSettings()
            }
        }
    }
    @objc private func forward(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Selection else { return }
        bridge.approve(id: s.id, token: s.token, epoch: s.epoch)
    }
    @objc private func ignore(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Selection else { return }
        bridge.ignore(id: s.id, token: s.token, epoch: s.epoch)
    }
    @objc private func stop(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Selection, s.epoch == bridge.generation else { return }
        bridge.stop(id: s.id, token: s.token)
    }
    @objc private func openHTTP(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Selection, s.epoch == bridge.generation,
              let entry = bridge.entries[s.id], entry.token == s.token,
              case .active = entry.state,
              let url = URL(string: "http://127.0.0.1:\(entry.service.port)/") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        bridge.shutdown { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func notify(_ entry: Bridge.Entry, epoch: UUID) {
        guard let center = notifications else { return }
        let now = ProcessInfo.processInfo.systemUptime
        notificationTimes.removeAll { now - $0 >= 60 }
        guard notificationTimes.count < 10 else {
            notificationResult = "Notification limit reached — approve remaining services in the menu"
            return
        }
        notificationTimes.append(now)
        let content = UNMutableNotificationContent()
        content.title = "Service available: \(entry.service.project)"
        content.body = "\(entry.service.host):\(entry.service.port) — forward to this Mac?"
        content.categoryIdentifier = "service"
        content.userInfo = ["id": entry.service.id, "token": entry.token.uuidString, "epoch": epoch.uuidString]
        center.add(UNNotificationRequest(identifier: entry.token.uuidString, content: content, trigger: nil)) { [weak self] error in
            guard let error = error else { return }
            DispatchQueue.main.async {
                guard let self = self, self.bridge.generation == epoch else { return }
                self.notificationResult = "Notification error: \(error.localizedDescription)"
                self.refreshNotificationSettings()
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard let id = info["id"] as? String,
              let rawToken = info["token"] as? String, let token = UUID(uuidString: rawToken),
              let rawEpoch = info["epoch"] as? String, let epoch = UUID(uuidString: rawEpoch) else {
            completionHandler(); return
        }
        DispatchQueue.main.async { [weak self] in
            if response.actionIdentifier == "forward" { self?.bridge.approve(id: id, token: token, epoch: epoch) }
            else if response.actionIdentifier == "ignore" { self?.bridge.ignore(id: id, token: token, epoch: epoch) }
            completionHandler()
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
