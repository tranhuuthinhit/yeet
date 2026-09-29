import AppKit
import Foundation

struct CleanError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Cleaner {
    /// Runs a clean action off the main thread.
    static func perform(_ action: CleanAction) async throws {
        if let bundleID = action.requiresQuitBundleID, await AppRunning.isRunning(bundleID) {
            let name = await AppRunning.name(of: bundleID) ?? bundleID
            throw CleanError(message: L("Quit \(name) completely (⌘Q) before deleting its cache.", "Hãy thoát hẳn \(name) (⌘Q) trước khi xoá cache của nó."))
        }
        #if APPSTORE
        // The sandbox can't run developer CLIs; App Store actions are removal-only.
        if action.command != nil && action.removeURL == nil {
            throw CleanError(message: L("The App Store version can't run commands: \(action.display)", "Bản App Store không chạy được lệnh: \(action.display)"))
        }
        #else
        if let command = action.command {
            let status = await Shell.run(command)
            // Without a removal fallback the command *is* the clean – its failure is an error.
            if status != 0 && action.removeURL == nil {
                throw CleanError(message: L("Command failed (exit code \(status)): \(action.display)", "Lệnh thất bại (mã \(status)): \(action.display)"))
            }
        }
        #endif
        if let url = action.removeURL {
            try remove(url, contentsOnly: action.contentsOnly)
        }
        for extra in action.extraRemovals {
            try remove(extra, contentsOnly: false)
        }
    }

    /// Paths outside the home folder that may be removed (leftover macOS installers only).
    private static func isAllowedOutsideHome(_ path: String) -> Bool {
        path.hasPrefix("/Applications/Install macOS ") && path.hasSuffix(".app") && !path.dropFirst(14).contains("/")
    }

    /// Removes a path permanently. Refuses anything outside the home folder or the home folder itself.
    static func remove(_ url: URL, contentsOnly: Bool) throws {
        let fm = FileManager.default
        let home = Paths.home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let insideHome = path.hasPrefix(home + "/") && path.count > home.count + 1
        guard insideHome || isAllowedOutsideHome(path) else {
            throw CleanError(message: L("Refusing to delete a path outside your home folder: \(path)", "Từ chối xoá đường dẫn ngoài thư mục người dùng: \(path)"))
        }
        // Emptying a folder follows symlinks – make sure the real location is still inside Home.
        if contentsOnly {
            let real = url.resolvingSymlinksInPath().standardizedFileURL.path
            let realHome = Paths.home.resolvingSymlinksInPath().standardizedFileURL.path
            guard real.hasPrefix(realHome + "/") else {
                throw CleanError(message: L("Refusing to delete: \(Paths.tilde(url)) is a link to \(real) (outside your home folder).", "Từ chối xoá: \(Paths.tilde(url)) là liên kết tới \(real) (ngoài thư mục người dùng)."))
            }
        }
        guard fm.fileExists(atPath: path) else { return }
        if contentsOnly {
            for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) {
                try forceRemove(child)
            }
        } else {
            try forceRemove(url)
        }
    }

    /// `removeItem`, retrying after making the tree writable (Go's module cache is read-only).
    private static func forceRemove(_ url: URL) throws {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: url)
        } catch {
            makeWritable(url)
            try fm.removeItem(at: url)
        }
    }

    private static func makeWritable(_ url: URL) {
        let fm = FileManager.default
        func fix(_ u: URL) {
            guard let attrs = try? fm.attributesOfItem(atPath: u.path),
                  let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue else { return }
            let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
            let wanted = perms | (isDir ? 0o700 : 0o600)
            if wanted != perms { try? fm.setAttributes([.posixPermissions: wanted], ofItemAtPath: u.path) }
        }
        fix(url)
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [],
                                     errorHandler: { _, _ in true }) else { return }
        while let item = en.nextObject() as? URL { fix(item) }
    }
}

enum AppRunning {
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    @MainActor
    static func name(of bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName
            ?? (bundleID == claudeDesktopBundleID ? "Claude" : nil)
    }

    /// Names of running apps among `bundleIDs`.
    @MainActor
    static func runningNames(_ bundleIDs: Set<String>) -> [String] {
        bundleIDs.filter { isRunning($0) }.map { name(of: $0) ?? $0 }.sorted()
    }

    @MainActor
    static func isRunning(_ bundleID: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { app in
            app.bundleIdentifier == bundleID
                || (bundleID == claudeDesktopBundleID && app.localizedName == "Claude" && app.bundleIdentifier?.hasPrefix("com.anthropic") == true)
        }
    }
}

enum Shell {
    /// Runs an executable synchronously and returns stdout (nil on failure or timeout).
    /// Used while scanning, e.g. `xcrun simctl runtime list -j`.
    static func capture(_ executable: String, _ args: [String], timeout: TimeInterval = 10) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: box.data, encoding: .utf8)
    }

    /// Runs `command` through a login zsh so Homebrew / nvm tools are on PATH. Returns the exit status.
    static func run(_ command: String) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", command]
            var env = ProcessInfo.processInfo.environment
            let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = extra + ":" + (env["PATH"] ?? "")
            p.environment = env
            p.currentDirectoryURL = Paths.home
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { proc in cont.resume(returning: proc.terminationStatus) }
            do {
                try p.run()
            } catch {
                cont.resume(returning: -1)
            }
        }
    }
}

enum FDAStatus: Equatable {
    case granted
    case denied
    case unknown   // no probe location exists on this Mac
}

enum Permissions {
    /// Locations protected by TCC that exist on (almost) every Mac. Reading any of them
    /// succeeds only with Full Disk Access. Using several probes avoids false negatives
    /// when one of them is missing or specially protected on a given macOS version.
    private static var probes: [(url: URL, isDirectory: Bool)] {
        let lib = Paths.home.appendingPathComponent("Library", isDirectory: true)
        return [
            // No probe inside ~/Library/Containers: on macOS 14+ reading another app's container
            // pops the "access data from other apps" prompt, and this runs during background work.
            (lib.appendingPathComponent("Safari", isDirectory: true), true),
            (lib.appendingPathComponent("Mail", isDirectory: true), true),
            (lib.appendingPathComponent("Messages", isDirectory: true), true),
            (lib.appendingPathComponent("Application Support/com.apple.TCC/TCC.db"), false),
            (URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"), false),
        ]
    }

    static func fullDiskAccessStatus() -> FDAStatus {
        let fm = FileManager.default
        var sawDenied = false
        for probe in probes {
            // fileExists works without FDA (it only stats the path).
            guard fm.fileExists(atPath: probe.url.path) else { continue }
            if probe.isDirectory {
                if (try? fm.contentsOfDirectory(atPath: probe.url.path)) != nil { return .granted }
            } else if let h = try? FileHandle(forReadingFrom: probe.url) {
                try? h.close()
                return .granted
            }
            sawDenied = true
        }
        return sawDenied ? .denied : .unknown
    }

    static func hasFullDiskAccess() -> Bool { fullDiskAccessStatus() == .granted }

    /// TCC grants apply to the `.app` bundle. When running via `swift run` / Xcode the
    /// responsible process is Terminal/Xcode instead, so a grant for Yeet.app has no effect.
    static var isRunningAsAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var appBundleURL: URL { Bundle.main.bundleURL }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([appBundleURL])
    }

    /// macOS sometimes only applies a new grant to freshly launched processes.
    @MainActor
    static func relaunch() {
        guard isRunningAsAppBundle else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appBundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// App Store (sandboxed) build: the user grants their Home folder once; the grant is kept
/// as an app-scoped security-scoped bookmark and re-activated on every launch.
enum FolderAccess {
    private static let bookmarkKey = "homeFolderBookmark"
    private(set) static var grantedURL: URL?

    static var isGranted: Bool { grantedURL != nil }

    /// Call once at launch.
    static func restore() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        guard url.startAccessingSecurityScopedResource() else { return }
        grantedURL = url
        if stale { save(url) }
    }

    /// Shows an open panel pointed at the real Home folder. Returns true when access was granted.
    @MainActor
    @discardableResult
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Paths.home
        panel.prompt = L("Grant Access", "Cấp quyền")
        panel.message = L("Choose your Home folder (\(Paths.home.lastPathComponent)) so Yeet can read and clean caches in ~/Library, ~/.npm, ~/.gradle…", "Chọn thư mục Home (\(Paths.home.lastPathComponent)) để Yeet đọc và dọn cache trong ~/Library, ~/.npm, ~/.gradle…")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        grantedURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        grantedURL = url
        save(url)
        return true
    }

    /// True when the granted folder is the Home folder (or a parent of it).
    static var coversHome: Bool {
        guard let g = grantedURL?.standardizedFileURL.path else { return false }
        let h = Paths.home.standardizedFileURL.path
        return h == g || h.hasPrefix(g.hasSuffix("/") ? g : g + "/")
    }

    static func revoke() {
        grantedURL?.stopAccessingSecurityScopedResource()
        grantedURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}
