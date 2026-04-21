import AppKit

final class StatusController {
    private var statusItem: NSStatusItem?
    private let service = ProviderService()

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚪ …"
        statusItem = item

        service.onChange = { [weak self] provider in
            DispatchQueue.main.async {
                self?.refresh(provider: provider)
            }
        }
        service.start()
        refresh(provider: service.currentProvider())
    }

    func stop() {
        service.stop()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func refresh(provider: String?) {
        statusItem?.button?.title = badge(for: provider)
        statusItem?.menu = buildMenu(current: provider)
    }

    private func badge(for provider: String?) -> String {
        switch provider {
        case "official":   return "🟢 official"
        case "easyclaude": return "🔵 easyclaude"
        case let .some(name): return "⚪ \(name)"
        case .none:        return "⚪ unset"
        }
    }

    private func buildMenu(current: String?) -> NSMenu {
        let menu = NSMenu()
        for name in service.availableProviders() {
            let item = NSMenuItem(
                title: "切换到 \(name)",
                action: #selector(switchProvider(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = name
            if name == current { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        let start = NSMenuItem(
            title: "在终端启动 ccstart…",
            action: #selector(launchStart),
            keyEquivalent: ""
        )
        start.target = self
        menu.addItem(start)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: "退出 ccpod",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func switchProvider(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        service.switchTo(provider: name) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.refresh(provider: name)
                case .failure(let err):
                    self?.presentError(err)
                }
            }
        }
    }

    @objc private func launchStart() {
        service.launchCCStartInTerminal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentError(_ err: Error) {
        let alert = NSAlert()
        alert.messageText = "ccpod 切换失败"
        alert.informativeText = String(describing: err)
        alert.alertStyle = .warning
        alert.runModal()
    }
}
