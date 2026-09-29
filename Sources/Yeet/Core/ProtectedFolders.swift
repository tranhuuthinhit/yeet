import Foundation

/// Folders macOS guards with a privacy prompt (TCC) the first time an app reads them.
///
/// Rule: Yeet never touches these on its own in the background. They are read only when
///  • Yeet has Full Disk Access (no prompts at all), or
///  • the user pressed “Cho phép ngay” (“Allow Now”), which triggers the prompts right then, while they
///    are looking — afterwards macOS remembers the answer and never asks again,
/// and the user hasn't switched the folder off.
enum ProtectedFolders {
    struct Folder: Identifiable, Hashable {
        let key: String
        let name: String
        let url: URL
        var id: String { key }
    }

    static let folders: [Folder] = [
        Folder(key: "Desktop", name: "Desktop", url: Paths.url("Desktop")),
        Folder(key: "Documents", name: "Documents", url: Paths.url("Documents")),
        Folder(key: "Downloads", name: "Downloads", url: Paths.url("Downloads")),
    ]

    static let preparedKey = "protectedFoldersPrepared"
    static let containersKey = "growthIncludeContainers"
    static let containersPreparedKey = "containersPrepared"
    static func enabledKey(_ key: String) -> String { "protectedInclude.\(key)" }

    /// User switch per folder (default on).
    static func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: enabledKey(key)) as? Bool ?? true
    }

    /// Folders whose prompt the user has already answered (via “Cho phép ngay”).
    static var preparedFolders: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: preparedKey) ?? [])
    }

    /// True when some enabled folder still needs its one-time prompt.
    static var needsPreparing: Bool {
        folders.contains { isEnabled($0.key) && !preparedFolders.contains($0.key) }
    }

    /// May Yeet read this folder without risking a surprise prompt?
    static func mayAccess(_ key: String) -> Bool {
        guard isEnabled(key) else { return false }
        if BuildFlavor.isAppStore { return true }          // covered by the Home folder grant
        return Permissions.hasFullDiskAccess() || preparedFolders.contains(key)
    }

    /// Reads each enabled folder once so macOS shows its prompts now. Blocks while a prompt is
    /// on screen, so call it off the main thread. Returns folder key → access granted.
    static func prepare() -> [String: Bool] {
        var result: [String: Bool] = [:]
        var done = preparedFolders
        for f in folders where isEnabled(f.key) {
            result[f.key] = (try? FileManager.default.contentsOfDirectory(atPath: f.url.path)) != nil
            done.insert(f.key)
        }
        UserDefaults.standard.set(Array(done), forKey: preparedKey)
        return result
    }

    /// Current access for folders already answered — never prompts.
    static func status() -> [String: Bool] {
        let done = Permissions.hasFullDiskAccess() ? Set(folders.map(\.key)) : preparedFolders
        var result: [String: Bool] = [:]
        for f in folders where done.contains(f.key) {
            result[f.key] = (try? FileManager.default.contentsOfDirectory(atPath: f.url.path)) != nil
        }
        return result
    }

    // MARK: Other apps' containers

    static let containersURL = Paths.url("Library/Containers")
    static let groupContainersURL = Paths.url("Library/Group Containers")

    /// Measure ~/Library/Containers & Group Containers? Always with FDA; otherwise only after the
    /// user opted in and answered the one-time “access data from other apps” prompt.
    static var mayMeasureContainers: Bool {
        if BuildFlavor.isAppStore { return false }          // the sandbox can't read them anyway
        if Permissions.hasFullDiskAccess() { return true }
        return UserDefaults.standard.bool(forKey: containersKey)
            && UserDefaults.standard.bool(forKey: containersPreparedKey)
    }

    /// Touches one other app's container so macOS shows its “data from other apps” prompt now.
    static func prepareContainers() -> Bool {
        let fm = FileManager.default
        let candidates = ["com.docker.docker", "com.apple.mail", "com.apple.Notes"]
            .map { containersURL.appendingPathComponent($0).appendingPathComponent("Data") }
            + ((try? fm.contentsOfDirectory(at: containersURL, includingPropertiesForKeys: nil)) ?? [])
                .prefix(3).map { $0.appendingPathComponent("Data") }
        var ok = false
        for u in candidates where fm.fileExists(atPath: u.path) {
            if (try? fm.contentsOfDirectory(atPath: u.path)) != nil { ok = true }
            break
        }
        UserDefaults.standard.set(true, forKey: containersPreparedKey)
        return ok
    }
}
