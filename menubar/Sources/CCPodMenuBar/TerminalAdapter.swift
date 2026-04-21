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
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Ghostty"
            activate
            tell application "System Events" to tell process "ghostty" to click menu item "New Window" of menu "File" of menu bar 1
            delay 0.5
            set term to focused terminal of selected tab of front window
            input text "\(escaped)\\n" to term
        end tell
        """
        try runAppleScript(script)
    }

    func sendCommand(toTTY tty: String, command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        // Use Ghostty's input text on the focused terminal of each window,
        // matching by checking if the window's terminal tty matches.
        // Fallback: write directly to TTY device file.
        if tty != "unknown", FileManager.default.isWritableFile(atPath: tty) {
            let data = (command + "\n").data(using: .utf8)!
            guard let fh = FileHandle(forWritingAtPath: tty) else {
                throw TerminalAdapterError.scriptFailed("无法写入 \(tty)")
            }
            fh.write(data)
            fh.closeFile()
        } else {
            let script = """
            tell application "Ghostty"
                set term to focused terminal of selected tab of front window
                input text "\(escaped)\\n" to term
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
            let data = (command + "\n").data(using: .utf8)!
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
