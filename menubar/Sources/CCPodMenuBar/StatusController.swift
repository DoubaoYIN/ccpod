import AppKit

final class StatusController {
    private var statusItem: NSStatusItem?
    private let sessionManager = SessionManager()
    private let providerService = ProviderService()
    private var launcherPanel: LauncherPanel?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚪ ccpod"
        statusItem = item

        sessionManager.onChange = { [weak self] in
            self?.rebuildMenu()
        }
        sessionManager.start()

        providerService.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.updateBadge() }
        }
        providerService.start()

        updateBadge()
        rebuildMenu()
    }

    func stop() {
        sessionManager.stop()
        providerService.stop()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func updateBadge() {
        let sessions = sessionManager.sessions
        if sessions.isEmpty {
            statusItem?.button?.title = "⚪ ccpod"
        } else {
            let providers = Set(sessions.map { $0.provider })
            if providers.count == 1 {
                statusItem?.button?.title = badge(for: providers.first)
            } else {
                statusItem?.button?.title = "🔀 ccpod (\(sessions.count))"
            }
        }
    }

    private func badge(for provider: String?) -> String {
        switch provider {
        case "official":   return "🟢 official"
        case "easyclaude": return "🔵 easyclaude"
        case let .some(n): return "⚪ \(n)"
        case .none:        return "⚪ ccpod"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Launch section
        let launchItem = NSMenuItem(
            title: "启动新会话...",
            action: #selector(openLauncher),
            keyEquivalent: "n"
        )
        launchItem.target = self
        menu.addItem(launchItem)

        // Running sessions
        let sessions = sessionManager.sessions
        if !sessions.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "正在运行:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for session in sessions {
                let sessionBadge = badge(for: session.provider)
                let title = "\(sessionBadge) · \(session.projectName)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)

                // Switch sub-items: offer all OTHER providers
                for provName in providerService.availableProviders() {
                    if provName == session.provider { continue }
                    let switchItem = NSMenuItem(
                        title: "    切到 \(provName)",
                        action: #selector(switchSession(_:)),
                        keyEquivalent: ""
                    )
                    switchItem.target = self
                    switchItem.representedObject = SwitchAction(
                        session: session, targetProvider: provName
                    )
                    menu.addItem(switchItem)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(
            title: "退出 ccpod",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        updateBadge()
    }

    @objc private func openLauncher() {
        if launcherPanel == nil {
            let panel = LauncherPanel()
            panel.onLaunch = { [weak self] provider, project, terminalName in
                self?.doLaunch(provider: provider, project: project, terminalName: terminalName)
            }
            launcherPanel = panel
        }
        launcherPanel?.refresh()
        launcherPanel?.center()
        launcherPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func doLaunch(provider: String, project: String, terminalName: String) {
        let registry = TerminalRegistry.shared
        let adapter = registry.adapters.first { $0.name == terminalName }
            ?? registry.defaultAdapter

        let ccgoPath = locateCCGo()
        let command = "\(ccgoPath) \(provider) \(shellQuote(project))"

        DispatchQueue.global().async {
            do {
                try adapter.openNewWindow(command: command)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func switchSession(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SwitchAction else { return }
        let session = action.session
        let target = action.targetProvider

        let adapter = TerminalRegistry.shared.adapter(for: session.terminal)
            ?? TerminalRegistry.shared.defaultAdapter

        let ccgoPath = locateCCGo()

        DispatchQueue.global().async { [weak self] in
            do {
                // Send /quit to the CC session
                try adapter.sendCommand(toTTY: session.tty, command: "/quit")
                Thread.sleep(forTimeInterval: 2.0)
                // Relaunch with new provider
                let cmd = "\(ccgoPath) \(target)"
                try adapter.sendCommand(toTTY: session.tty, command: cmd)
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func locateCCGo() -> String {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/ccgo").path,
            "/usr/local/bin/ccgo",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "ccgo"
    }

    private func shellQuote(_ s: String) -> String {
        if s.rangeOfCharacter(from: .init(charactersIn: " \t'\"\\$`!")) != nil {
            let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        return s
    }

    private func showError(_ err: Error) {
        let alert = NSAlert()
        alert.messageText = "ccpod 操作失败"
        alert.informativeText = String(describing: err)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class SwitchAction: NSObject {
    let session: SessionInfo
    let targetProvider: String

    init(session: SessionInfo, targetProvider: String) {
        self.session = session
        self.targetProvider = targetProvider
    }
}
