import AppKit
import Foundation

/// Shared helpers for the modules that move user files to the Trash (large files, duplicates,
/// uninstaller, browser site data). Caches are deleted with `Cleaner.remove` instead.
enum FileOps {
    struct Outcome {
        var moved: [URL] = []
        var freed: Int64 = 0
        var failures: [String] = []
    }

    /// Folders Yeet may move things out of: the user's Home (granted folder) and,
    /// when the user granted it, /Applications.
    static func mayTouch(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let home = Paths.home.standardizedFileURL.path
        if p.hasPrefix(home + "/") && p.count > home.count + 1 {
            // Never the Home folder's own top-level system folders.
            let rel = String(p.dropFirst(home.count + 1))
            let protected: Set<String> = ["Library", "Desktop", "Documents", "Downloads", "Movies", "Music",
                                          "Pictures", "Public", "Applications", ".Trash"]
            return !protected.contains(rel)
        }
        if p.hasPrefix("/Applications/"), p.hasSuffix(".app"),
           !p.dropFirst("/Applications/".count).dropLast(4).contains("/") {
            return true
        }
        return false
    }

    /// Moves each URL to the Trash with `FileManager.trashItem` (no Finder scripting, sandbox-safe).
    /// `sizes` gives the byte count to report for each URL when it is known.
    static func moveToTrash(_ urls: [URL], sizes: [URL: Int64] = [:]) -> Outcome {
        var out = Outcome()
        let fm = FileManager.default
        for url in urls {
            guard mayTouch(url) else {
                out.failures.append(L("Refused (outside allowed folders): \(Paths.tilde(url))",
                                      "Từ chối (ngoài thư mục được phép): \(Paths.tilde(url))"))
                continue
            }
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.trashItem(at: url, resultingItemURL: nil)
                out.moved.append(url)
                out.freed += sizes[url] ?? 0
            } catch {
                out.failures.append("\(Paths.tilde(url)): \(error.localizedDescription)")
            }
        }
        return out
    }

    /// Allocated size of a file or folder (folders are walked; symlinks are not followed).
    static func allocatedSize(_ url: URL) -> Int64 {
        Scanner.stats(url).size
    }

    /// Opens Quick Look-like preview / reveals in Finder.
    @MainActor
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Bundle identifiers of running apps (used to refuse cleaning an app's data while it runs).
    @MainActor
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

/// Cooperative cancel + progress counter shared between a background scan and the UI.
final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _cancelled = false

    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }

    func tick(_ n: Int = 1) { lock.lock(); _count += n; lock.unlock() }
    func cancel() { lock.lock(); _cancelled = true; lock.unlock() }
}

/// Checks what the sandbox actually lets Yeet read in the Home folder, so an empty scan can say
/// "Yeet can't read these folders" instead of "nothing found".
enum HomeAccess {
    struct Report: Equatable {
        /// The Home folder itself can be listed.
        var homeReadable: Bool
        /// Visible top-level folders (Desktop, Downloads, …) that exist but can't be listed.
        var blocked: [String]
        /// The folder the user granted, if any (tilde form).
        var granted: String?
        /// The grant is the Home folder (or a parent of it).
        var coversHome: Bool

        var hasProblem: Bool { !homeReadable || !blocked.isEmpty || !coversHome }
    }

    static func check() -> Report {
        let fm = FileManager.default
        let home = Paths.home
        let top = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        var blocked: [String] = []
        for name in ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"] {
            let u = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if (try? fm.contentsOfDirectory(atPath: u.path)) == nil { blocked.append(name) }
        }
        return Report(homeReadable: top != nil, blocked: blocked,
                      granted: FolderAccess.grantedURL.map(Paths.tilde), coversHome: FolderAccess.coversHome)
    }
}
