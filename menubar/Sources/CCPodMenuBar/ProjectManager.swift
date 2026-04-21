import Foundation

struct ProjectInfo {
    let path: String
    let name: String
    let lastUsed: Date
}

final class ProjectManager {
    private let projectsDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.projectsDir = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    func recentProjects(limit: Int = 20) -> [ProjectInfo] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> ProjectInfo? in
            let encoded = url.lastPathComponent
            let decoded = decodeCCProjectPath(encoded)
            guard fm.fileExists(atPath: decoded) else { return nil }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let name = (decoded as NSString).lastPathComponent
            return ProjectInfo(path: decoded, name: name, lastUsed: mtime)
        }
        .sorted { $0.lastUsed > $1.lastUsed }
        .prefix(limit)
        .map { $0 }
    }

    private func decodeCCProjectPath(_ encoded: String) -> String {
        // CC encodes: leading '-' → '/', then all '-' → '/'
        var s = encoded
        if s.hasPrefix("-") {
            s = "/" + String(s.dropFirst())
        }
        s = s.replacingOccurrences(of: "-", with: "/")
        return s
    }
}
