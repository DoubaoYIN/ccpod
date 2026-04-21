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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/MacOS/ghostty")
        // Run ccgo, then drop into interactive shell so window stays open
        process.arguments = ["-e", "bash", "-lc", "\(command); exec bash -l"]
        try process.run()
    }

    func sendCommand(toTTY tty: String, command: String) throws {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
