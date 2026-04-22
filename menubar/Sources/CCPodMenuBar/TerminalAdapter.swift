import Foundation

enum TerminalAdapterError: Error, CustomStringConvertible {
    case scriptFailed(String)
    case terminalNotRunning(String)

    var description: String {
        switch self {
        case .scriptFailed(let msg): return msg
        case .terminalNotRunning(let name): return "\(name) 未运行"
        }
    }
}

protocol TerminalAdapter {
    var name: String { get }
    var identifier: String { get }
    func openNewWindow(command: String) throws
    func sendCommand(toTTY tty: String, command: String) throws
}

final class GhosttyAdapter: TerminalAdapter {
    let name = "Ghostty"
    let identifier = "ghostty"

    func openNewWindow(command: String) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccpod-zdot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // .zshrc that loads user config then runs the launch command
        let zshrc = base.appendingPathComponent(".zshrc")
        let rcContent = """
        [[ -f "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
        [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
        if [[ -n "$CCPOD_LAUNCH_CMD" ]]; then
            local cmd="$CCPOD_LAUNCH_CMD"
            unset CCPOD_LAUNCH_CMD
            unset ZDOTDIR
            eval "$cmd"
        fi
        """
        try rcContent.write(to: zshrc, atomically: true, encoding: .utf8)

        // Bootstrap script: sets env then execs interactive zsh
        let bootstrap = base.appendingPathComponent("boot.sh")
        let bootContent = """
        #!/bin/zsh
        export ZDOTDIR="\(base.path)"
        export CCPOD_LAUNCH_CMD="\(command.replacingOccurrences(of: "\"", with: "\\\""))"
        exec /bin/zsh
        """
        try bootContent.write(to: bootstrap, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: bootstrap.path)

        // Launch via `open` so Ghostty runs as independent app (no TCC prompts for CCPod)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", "Ghostty", "--args", "-e", bootstrap.path]
        try process.run()
    }

    func sendCommand(toTTY tty: String, command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        if tty != "unknown", FileManager.default.isWritableFile(atPath: tty) {
            // \r (carriage return) is what terminals interpret as Enter
            let data = (command + "\r").data(using: .utf8)!
            guard let fh = FileHandle(forWritingAtPath: tty) else {
                throw TerminalAdapterError.scriptFailed("无法写入 \(tty)")
            }
            fh.write(data)
            fh.closeFile()
        } else {
            let script = """
            tell application "Ghostty"
                set term to focused terminal of selected tab of front window
                set cmd to "\(escaped)" & (ASCII character 10)
                input text cmd to term
            end tell
            """
            try runAppleScript(script)
        }
    }
}

final class TerminalAppAdapter: TerminalAdapter {
    let name = "Terminal"
    let identifier = "terminal"

    func openNewWindow(command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        try runAppleScript(script)
    }

    func sendCommand(toTTY tty: String, command: String) throws {
        if tty != "unknown", FileManager.default.isWritableFile(atPath: tty) {
            let data = (command + "\r").data(using: .utf8)!
            guard let fh = FileHandle(forWritingAtPath: tty) else {
                throw TerminalAdapterError.scriptFailed("无法写入 \(tty)")
            }
            fh.write(data)
            fh.closeFile()
        } else {
            throw TerminalAdapterError.scriptFailed("无法向 Terminal.app 发送命令（TTY 未知）")
        }
    }
}

final class TerminalRegistry {
    static let shared = TerminalRegistry()

    let adapters: [TerminalAdapter] = [
        GhosttyAdapter(),
        TerminalAppAdapter(),
    ]

    var defaultAdapter: TerminalAdapter { adapters[0] }

    func adapter(for identifier: String) -> TerminalAdapter? {
        adapters.first { $0.identifier == identifier }
    }
}

private func runAppleScript(_ source: String) throws {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
        throw TerminalAdapterError.scriptFailed("无法创建 AppleScript")
    }
    script.executeAndReturnError(&error)
    if let error = error {
        let msg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
        throw TerminalAdapterError.scriptFailed(msg)
    }
}
