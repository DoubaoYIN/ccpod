import Foundation

/// Reads `~/.claude/current-provider`, watches it for changes,
/// and shells out to `ccuse` for switches.
final class ProviderService {
    enum ServiceError: Error, CustomStringConvertible {
        case ccuseNotFound
        case ccuseFailed(code: Int32, stderr: String)

        var description: String {
            switch self {
            case .ccuseNotFound:
                return "找不到 ccuse 命令。请先运行 install.sh。"
            case .ccuseFailed(let code, let stderr):
                return "ccuse 退出码 \(code)\n\(stderr)"
            }
        }
    }

    var onChange: ((String?) -> Void)?

    private let claudeDir: URL
    private let currentProviderURL: URL
    private let providersDirURL: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        self.currentProviderURL = claudeDir.appendingPathComponent("current-provider")
        self.providersDirURL = claudeDir.appendingPathComponent("providers", isDirectory: true)
    }

    // MARK: - Reads

    func currentProvider() -> String? {
        guard let data = try? String(contentsOf: currentProviderURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func availableProviders() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: providersDirURL,
                                                        includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.hasSuffix(".example") && !$0.contains(".example") }
            .sorted()
    }

    // MARK: - File watching

    func start() {
        watchCurrentProvider()
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
    }

    private func watchCurrentProvider() {
        // Re-arm if the file is replaced (atomic rename → new inode).
        stop()

        // Ensure the file exists so we can open it; if it doesn't yet, poll
        // the directory instead.
        let path = currentProviderURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            watchClaudeDir()
            return
        }

        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .global()
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let events = source.data
            self.onChange?(self.currentProvider())
            // If the file was deleted/renamed (atomic rename from ccuse),
            // re-arm on the new inode.
            if events.contains(.delete) || events.contains(.rename) {
                self.watchCurrentProvider()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 {
                close(fd)
                self?.fd = -1
            }
        }
        source.resume()
        fileSource = source
    }

    private func watchClaudeDir() {
        let path = claudeDir.path
        let dirFD = open(path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        fd = dirFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write],
            queue: .global()
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.currentProviderURL.path) {
                self.watchCurrentProvider()
                self.onChange?(self.currentProvider())
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 {
                close(fd)
                self?.fd = -1
            }
        }
        source.resume()
        fileSource = source
    }

    // MARK: - Switching

    func switchTo(provider: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let ccuse = locateCCUse() else {
            completion(.failure(ServiceError.ccuseNotFound))
            return
        }
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ccuse)
            process.arguments = [provider]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                completion(.failure(error))
                return
            }
            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(ServiceError.ccuseFailed(
                    code: process.terminationStatus,
                    stderr: stderr
                )))
            }
        }
    }

    private func locateCCUse() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/ccuse").path,
            "/usr/local/bin/ccuse",
            "/opt/homebrew/bin/ccuse",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Terminal launch

    func launchCCStartInTerminal() {
        // Open Terminal.app with a fresh window running ccstart.
        let script = """
        tell application "Terminal"
            activate
            do script "ccstart"
        end tell
        """
        if let apple = NSAppleScript(source: script) {
            var err: NSDictionary?
            apple.executeAndReturnError(&err)
        }
    }
}
