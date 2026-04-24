import Foundation

struct SessionInfo: Codable {
    let pid: Int
    let tty: String
    let provider: String
    let project: String
    let terminal: String
    let started_at: String
    let num: Int?

    var sessionNumber: Int { num ?? 0 }

    var projectName: String {
        (project as NSString).lastPathComponent
    }

    var isAlive: Bool {
        kill(pid_t(pid), 0) == 0
    }
}

extension SessionManager {
    func nextSessionNumber() -> Int {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let counterURL = home
            .appendingPathComponent(".claude")
            .appendingPathComponent("ccpod-session-counter")
        var counter = 0
        if let str = try? String(contentsOf: counterURL, encoding: .utf8),
           let val = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            counter = val
        }
        return counter + 1
    }
}

final class SessionManager {
    var sessions: [SessionInfo] = []
    var onChange: (() -> Void)?

    private let sessionsURL: URL
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var cleanupTimer: DispatchSourceTimer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.sessionsURL = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("ccpod-sessions.json")
    }

    func start() {
        reload()
        watchFile()
        startCleanupTimer()
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        dirSource?.cancel()
        dirSource = nil
        cleanupTimer?.cancel()
        cleanupTimer = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    func reload() {
        guard let data = try? Data(contentsOf: sessionsURL),
              let decoded = try? JSONDecoder().decode([SessionInfo].self, from: data) else {
            sessions = []
            return
        }
        sessions = decoded.filter { $0.isAlive }
    }

    private func startCleanupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.cleanupAndNotify()
        }
        timer.resume()
        cleanupTimer = timer
    }

    private func cleanupAndNotify() {
        reload()
        if let data = try? Data(contentsOf: sessionsURL),
           let all = try? JSONDecoder().decode([SessionInfo].self, from: data),
           all.count != sessions.count {
            writeSessionsFile(sessions)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    private func writeSessionsFile(_ sessions: [SessionInfo]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        let tmp = sessionsURL.deletingLastPathComponent()
            .appendingPathComponent("ccpod-sessions.tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.moveItem(at: tmp, to: sessionsURL)
        } catch {
            // Atomic write via JSONEncoder + .atomic option as fallback
            try? data.write(to: sessionsURL, options: .atomic)
        }
    }

    private func watchFile() {
        fileSource?.cancel()
        if fd >= 0 { close(fd); fd = -1 }

        let path = sessionsURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            watchDir()
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
            self.reload()
            DispatchQueue.main.async { self.onChange?() }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                self.watchFile()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        fileSource = source
    }

    private func watchDir() {
        let dirPath = sessionsURL.deletingLastPathComponent().path
        let dirFD = open(dirPath, O_EVTONLY)
        guard dirFD >= 0 else { return }
        fd = dirFD
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD, eventMask: [.write], queue: .global()
        )
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.sessionsURL.path) {
                self.watchFile()
                self.reload()
                DispatchQueue.main.async { self.onChange?() }
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd); self?.fd = -1 }
        }
        source.resume()
        dirSource = source
    }
}
