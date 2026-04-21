import Foundation

final class ProviderService {
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
            .filter { !$0.contains(".example") }
            .sorted()
    }

    func start() {
        watchCurrentProvider()
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    private func watchCurrentProvider() {
        stop()
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
            self.onChange?(self.currentProvider())
            if source.data.contains(.delete) || source.data.contains(.rename) {
                self.watchCurrentProvider()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        fileSource = source
    }

    private func watchClaudeDir() {
        let dirPath = claudeDir.path
        let dirFD = open(dirPath, O_EVTONLY)
        guard dirFD >= 0 else { return }
        fd = dirFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD, eventMask: [.write], queue: .global()
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.currentProviderURL.path) {
                self.watchCurrentProvider()
                self.onChange?(self.currentProvider())
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        fileSource = source
    }
}
