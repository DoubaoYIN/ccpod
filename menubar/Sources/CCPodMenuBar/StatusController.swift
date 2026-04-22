import AppKit
import SwiftUI

final class StatusController: NSObject {
    private var statusItem: NSStatusItem?
    private let sessionManager = SessionManager()
    private let providerService = ProviderService()
    private let projectManager = ProjectManager()
    private var popover: NSPopover?
    private let vm = PopoverViewModel()

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚪ ccpod"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        sessionManager.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateBadge()
                self?.refreshVM()
            }
        }
        sessionManager.start()

        providerService.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.updateBadge() }
        }
        providerService.start()

        vm.onLaunch = { [weak self] provider, project, terminal in
            self?.popover?.close()
            self?.doLaunch(provider: provider, project: project, terminalName: terminal)
        }
        vm.onSwitch = { [weak self] session, target in
            self?.popover?.close()
            self?.doSwitch(session: session, target: target)
        }
        vm.onQuit = {
            NSApp.terminate(nil)
        }

        updateBadge()
    }

    func stop() {
        sessionManager.stop()
        providerService.stop()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.close()
            return
        }
        refreshVM()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        let hosting = NSHostingController(rootView: PopoverContentView(vm: vm))
        let size = hosting.view.fittingSize
        pop.contentSize = NSSize(width: max(size.width, 320), height: size.height)
        pop.contentViewController = hosting
        popover = pop

        if let button = statusItem?.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func refreshVM() {
        vm.refresh(providerService: providerService, projectManager: projectManager, sessionManager: sessionManager)
    }

    // MARK: - Badge

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

    // MARK: - Launch

    private func doLaunch(provider: String, project: String, terminalName: String) {
        let registry = TerminalRegistry.shared
        let adapter = registry.adapters.first { $0.name == terminalName }
            ?? registry.defaultAdapter

        let ccgoPath = locateCCGo()
        let command = "\(ccgoPath) \(provider) \(shellQuote(project))"

        DispatchQueue.global().async { [weak self] in
            do {
                try adapter.openNewWindow(command: command)
            } catch {
                DispatchQueue.main.async { self?.showError(error) }
            }
        }
    }

    // MARK: - Switch

    private func doSwitch(session: SessionInfo, target: String) {
        let ccgoPath = locateCCGo()

        DispatchQueue.global().async { [weak self] in
            let claudeDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
            let pendingFile = claudeDir.appendingPathComponent("ccpod-pending-\(session.pid).sh")
            let cmd = "\(ccgoPath) \(target) \(self?.shellQuote(session.project) ?? "")"

            do {
                try cmd.write(to: pendingFile, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async { self?.showError(error) }
                return
            }

            let claudePID = self?.findClaudePID(onTTY: session.tty)
            if let claudePID = claudePID {
                kill(pid_t(claudePID), SIGTERM)
            }
        }
    }

    // MARK: - Helpers

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

    private func findClaudePID(onTTY tty: String) -> Int? {
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-t", ttyShort, "-o", "pid,comm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("claude") || trimmed.contains(" claude") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let pidStr = parts.first, let pid = Int(pidStr) {
                    return pid
                }
            }
        }
        return nil
    }
}
