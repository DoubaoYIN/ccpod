import Foundation

struct ProjectInfo {
    let path: String
    let name: String
    let lastUsed: Date
    let source: ProjectSource
}

enum ProjectSource {
    case manual
    case scanned
    case claudeCode
}

private struct ProjectsConfig: Codable {
    var scan_dirs: [String]
    var manual: [ManualEntry]

    struct ManualEntry: Codable {
        let path: String
        let name: String
    }
}

final class ProjectManager {
    var onChange: (() -> Void)?

    private let claudeProjectsDir: URL
    private let configURL: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeProjectsDir = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        self.configURL = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("ccpod-projects.json")
        ensureConfig()
    }

    func start() {
        watchConfig()
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    // MARK: - Public API

    func recentProjects(limit: Int = 30) -> [ProjectInfo] {
        var seen = Set<String>()
        var result: [ProjectInfo] = []

        let config = loadConfig()

        for entry in config.manual {
            let expanded = expandTilde(entry.path)
            guard FileManager.default.fileExists(atPath: expanded) else { continue }
            guard seen.insert(expanded).inserted else { continue }
            let mtime = modificationDate(atPath: expanded)
            result.append(ProjectInfo(path: expanded, name: entry.name, lastUsed: mtime, source: .manual))
        }

        for dir in config.scan_dirs {
            let expanded = expandTilde(dir)
            for proj in scanDirectory(expanded) {
                guard seen.insert(proj.path).inserted else { continue }
                result.append(proj)
            }
        }

        for proj in claudeCodeProjects() {
            guard seen.insert(proj.path).inserted else { continue }
            result.append(proj)
        }

        return result
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit)
            .map { $0 }
    }

    func addManualProject(path: String) {
        var config = loadConfig()
        let expanded = expandTilde(path)
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        if config.manual.contains(where: { expandTilde($0.path) == expanded }) { return }
        let name = (expanded as NSString).lastPathComponent
        config.manual.append(ProjectsConfig.ManualEntry(path: expanded, name: name))
        saveConfig(config)
    }

    func removeManualProject(path: String) {
        var config = loadConfig()
        let expanded = expandTilde(path)
        config.manual.removeAll { expandTilde($0.path) == expanded }
        saveConfig(config)
    }

    // MARK: - Scan

    private func scanDirectory(_ dir: String) -> [ProjectInfo] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: dir)
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { entry -> ProjectInfo? in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let p = entry.path
            let hasClaude = fm.fileExists(atPath: (p as NSString).appendingPathComponent("CLAUDE.md"))
            let hasGit = fm.fileExists(atPath: (p as NSString).appendingPathComponent(".git"))
            guard hasClaude || hasGit else { return nil }
            let mtime = modificationDate(atPath: p)
            let name = entry.lastPathComponent
            return ProjectInfo(path: p, name: name, lastUsed: mtime, source: .scanned)
        }
    }

    // MARK: - Claude Code projects (original logic)

    private func claudeCodeProjects() -> [ProjectInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> ProjectInfo? in
            let encoded = url.lastPathComponent
            let decoded = decodeCCProjectPath(encoded)
            guard fm.fileExists(atPath: decoded) else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let name = (decoded as NSString).lastPathComponent
            return ProjectInfo(path: decoded, name: name, lastUsed: mtime, source: .claudeCode)
        }
    }

    private func decodeCCProjectPath(_ encoded: String) -> String {
        var s = encoded
        if s.hasPrefix("-") {
            s = "/" + String(s.dropFirst())
        }
        s = s.replacingOccurrences(of: "-", with: "/")
        return s
    }

    // MARK: - Config I/O

    private func loadConfig() -> ProjectsConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ProjectsConfig.self, from: data) else {
            return ProjectsConfig(scan_dirs: ["~/Projects"], manual: [])
        }
        return config
    }

    private func saveConfig(_ config: ProjectsConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        let dir = configURL.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent("ccpod-projects.json.tmp")
        try? data.write(to: tmp, options: .atomic)
        try? FileManager.default.moveItem(at: tmp, to: configURL)
    }

    private func ensureConfig() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let config = ProjectsConfig(scan_dirs: ["~/Projects"], manual: [])
        saveConfig(config)
    }

    // MARK: - File Watcher

    private func watchConfig() {
        stop()
        let path = configURL.path
        if !FileManager.default.fileExists(atPath: path) {
            watchParentDir()
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
            self.onChange?()
            if source.data.contains(.delete) || source.data.contains(.rename) {
                self.watchConfig()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        fileSource = source
    }

    private func watchParentDir() {
        let dirPath = configURL.deletingLastPathComponent().path
        let dirFD = open(dirPath, O_EVTONLY)
        guard dirFD >= 0 else { return }
        fd = dirFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD, eventMask: [.write], queue: .global()
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.configURL.path) {
                self.watchConfig()
                self.onChange?()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        fileSource = source
    }

    // MARK: - Helpers

    private func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst(1))
        }
        return path
    }

    private func modificationDate(atPath path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
    }
}
