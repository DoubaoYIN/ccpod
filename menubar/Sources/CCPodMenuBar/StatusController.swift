import AppKit
import SwiftUI

final class StatusController: NSObject {
    private var statusItem: NSStatusItem?
    private let sessionManager = SessionManager()
    private let providerService = ProviderService()
    private let projectManager = ProjectManager()
    private var popover: NSPopover?
    private let vm = PopoverViewModel()
    private var addProviderWindow: NSWindow?

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

        projectManager.onChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshVM() }
        }
        projectManager.start()

        vm.onLaunch = { [weak self] provider, project, terminal in
            self?.popover?.close()
            self?.doLaunch(provider: provider, project: project, terminalName: terminal)
        }
        vm.onSwitch = { [weak self] session, target in
            self?.popover?.close()
            self?.doSwitch(session: session, target: target)
        }
        vm.onClose = { [weak self] session in
            self?.doClose(session: session)
        }
        vm.onQuit = {
            NSApp.terminate(nil)
        }
        vm.onShowAddProvider = { [weak self] in
            self?.popover?.close()
            self?.showAddProviderWindow()
        }
        vm.onAddProject = { [weak self] in
            self?.popover?.close()
            self?.showAddProjectDialog()
        }

        updateBadge()
    }

    func stop() {
        sessionManager.stop()
        providerService.stop()
        projectManager.stop()
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
        let hosting = NSHostingController(rootView: PopoverContentView(vm: vm, onRefresh: { [weak self] in
            self?.refreshVM()
        }))
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
        } else if sessions.count == 1 {
            let s = sessions[0]
            statusItem?.button?.title = "\(badgeEmoji(s.provider)) #\(s.sessionNumber) \(s.provider)"
        } else {
            let nums = sessions.map { "#\($0.sessionNumber)" }.joined(separator: " ")
            statusItem?.button?.title = "🔀 \(nums)"
        }
        updateStatusFile(sessions)
    }

    private func updateStatusFile(_ sessions: [SessionInfo]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let statusURL = home.appendingPathComponent(".claude/ccpod-status.txt")
        let text: String
        if sessions.isEmpty {
            text = "⚪ ccpod"
        } else {
            text = sessions.map { "\(badgeEmoji($0.provider)) #\($0.sessionNumber) \($0.provider)·\($0.projectName)" }.joined(separator: " | ")
        }
        try? text.write(to: statusURL, atomically: true, encoding: .utf8)
    }

    private func badgeEmoji(_ provider: String) -> String {
        switch provider {
        case "official": return "🟢"
        case "easyclaude": return "🔵"
        case "minimax": return "🟠"
        case "glm": return "🟣"
        case "volcengine": return "🔴"
        case "aliyun": return "🟤"
        case "deepseek": return "🔷"
        case "kimi": return "🟡"
        default: return "⚪"
        }
    }

    // MARK: - Add Provider Window

    private func showAddProviderWindow() {
        if let w = addProviderWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = AddProviderView(onComplete: { [weak self] in
            self?.refreshVM()
            self?.addProviderWindow?.close()
        })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "添加线路"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 340, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addProviderWindow = window
    }

    // MARK: - Launch

    private func doLaunch(provider: String, project: String, terminalName: String) {
        let registry = TerminalRegistry.shared
        let adapter = registry.adapters.first { $0.name == terminalName }
            ?? registry.defaultAdapter

        let ccgoPath = locateCCGo()
        let command = "\(ccgoPath) \(provider) \(shellQuote(project))"
        let projectName = (project as NSString).lastPathComponent
        let num = sessionManager.nextSessionNumber()
        let title = "#\(num) \(provider) · \(projectName)"

        DispatchQueue.global().async { [weak self] in
            do {
                try adapter.openNewWindow(command: command, title: title)
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

    // MARK: - Close

    private func doClose(session: SessionInfo) {
        // SIGTERM to the shell PID that runs ccgo — shell exits, claude gets
        // SIGHUP, and the terminal window closes (if the terminal is set to
        // close on shell exit, which is the default for Ghostty/Terminal).
        kill(pid_t(session.pid), SIGTERM)
        // Nudge a refresh so the row disappears promptly; the 5s cleanup timer
        // also catches it, but this is snappier.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sessionManager.reload()
            self?.refreshVM()
            self?.updateBadge()
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

    private func showAddProjectDialog() {
        let panel = NSOpenPanel()
        panel.title = "选择项目目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            projectManager.addManualProject(path: url.path)
            refreshVM()
        }
    }
}
