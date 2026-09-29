import Foundation

struct DirStats: Sendable {
    var size: Int64 = 0
    var files: Int = 0
    var modified: Date? = nil
    var exists: Bool = false

    static func + (a: DirStats, b: DirStats) -> DirStats {
        DirStats(size: a.size + b.size,
                 files: a.files + b.files,
                 modified: [a.modified, b.modified].compactMap { $0 }.max(),
                 exists: a.exists || b.exists)
    }
}

/// Discovers developer caches on disk. All functions are synchronous and meant to be
/// called from a background task.
enum Scanner {
    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]
    private static let keySet = Set(keys)
    private static let day: TimeInterval = 86_400

    static func scan(_ tool: ToolKind, gitRoots: [URL]) -> [CacheNode] {
        switch tool {
        case .xcode: return xcode()
        case .npm: return npm()
        case .yarn: return yarn()
        case .gradle: return gradle()
        case .git: return git(roots: gitRoots)
        case .claude: return claude()
        case .swiftDeps: return swiftDeps()
        case .pnpm: return pnpmBun()
        case .nodeModules: return nodeModules(roots: gitRoots)
        case .python: return python()
        case .go: return golang()
        case .rust: return rust(roots: gitRoots)
        case .maven: return maven()
        case .flutter: return flutter()
        case .homebrew: return homebrew()
        case .ide: return ides()
        case .apps: return appCaches()
        case .system: return macOS()
        }
    }

    // MARK: - Disk helpers

    /// Recursive allocated size, file count and newest modification date.
    static func stats(_ url: URL) -> DirStats {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return DirStats() }
        var s = DirStats(exists: true)
        let own = try? url.resourceValues(forKeys: keySet)
        s.modified = own?.contentModificationDate

        guard isDir.boolValue else {
            s.files = 1
            s.size = Int64(own?.totalFileAllocatedSize ?? own?.fileAllocatedSize ?? 0)
            return s
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                     errorHandler: { _, _ in true }) else { return s }
        while let item = en.nextObject() as? URL {
            guard let rv = try? item.resourceValues(forKeys: keySet) else { continue }
            if rv.isRegularFile == true {
                s.files += 1
                s.size += Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            }
            if let m = rv.contentModificationDate, m > (s.modified ?? .distantPast) {
                s.modified = m
            }
        }
        return s
    }

    /// Immediate sub-directories (not following symlinks), sorted by name.
    static func subdirs(_ url: URL, includeHidden: Bool = false) -> [URL] {
        let fm = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: opts) else {
            return []
        }
        return items.filter {
            let rv = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return rv?.isDirectory == true && rv?.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Node builders

    static func rm(_ u: URL) -> CleanAction {
        CleanAction(removeURL: u, display: "rm -rf " + Paths.shellDisplay(u))
    }

    static func rmContents(_ u: URL) -> CleanAction {
        CleanAction(removeURL: u, contentsOnly: true, display: "rm -rf " + Paths.shellDisplay(u) + "/*")
    }

    /// Action that runs the tool's own command first, then removes the path (fallback).
    /// The sandboxed App Store build cannot run CLI tools, so it removes directly.
    static func toolAction(_ command: String, display: String, remove url: URL, contentsOnly: Bool = false) -> CleanAction {
        #if APPSTORE
        return contentsOnly ? rmContents(url) : rm(url)
        #else
        return CleanAction(command: command, removeURL: url, contentsOnly: contentsOnly, display: display)
        #endif
    }

    static func leaf(_ id: String, _ name: String, _ u: URL, _ tool: ToolKind,
                     risk: Risk, note: String, action: CleanAction, stats given: DirStats? = nil) -> CacheNode {
        let s = given ?? stats(u)
        return CacheNode(id: id, name: name, url: u, tool: tool,
                         leafSize: s.size, fileCount: s.files, modified: s.modified,
                         risk: risk, note: s.size > 0 ? note : L("No data.", "Không có dữ liệu."), action: action)
    }

    static func group(_ id: String, _ name: String, _ u: URL, _ tool: ToolKind,
                      path: String? = nil, children: [CacheNode]) -> CacheNode {
        CacheNode(id: id, name: name, url: u, tool: tool, pathOverride: path, children: children)
    }

    private static func isStale(_ date: Date?, days: Double) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > days * day
    }

    // MARK: - Xcode

    static func xcode() -> [CacheNode] {
        let t = ToolKind.xcode
        let xcodeDir = Paths.url("Library/Developer/Xcode")
        var result: [CacheNode] = []

        // Derived Data – one row per project folder
        let ddURL = xcodeDir.appendingPathComponent("DerivedData", isDirectory: true)
        let ddChildren: [CacheNode] = subdirs(ddURL).map { u -> CacheNode in
            let s = stats(u)
            let folder = u.lastPathComponent
            let project = projectName(folder)
            let old = isStale(s.modified, days: 30)
            var note = old
                ? L("\(project) hasn't been opened in over 30 days. Safe to delete.",
                    "Dự án \(project) không mở hơn 30 ngày. Xoá an toàn.")
                : L("The next build of \(project) will be slower because it has to re-index and recompile from scratch.",
                    "Lần build kế tiếp của dự án \(project) sẽ chậm hơn do phải index và biên dịch lại từ đầu.")
            if let ws = workspacePath(u) { note += " Workspace: \(ws)" }
            return leaf("xcode.dd.\(folder)", folder, u, t, risk: old ? .safe : .rebuild,
                        note: note, action: rm(u), stats: s)
        }
        .sorted { $0.leafSize > $1.leafSize }
        result.append(group("xcode.dd", "Derived Data", ddURL, t, children: ddChildren))

        // Device Support – one row per OS build
        let platforms: [(String, String)] = [
            ("iOS", "iOS DeviceSupport"), ("watchOS", "watchOS DeviceSupport"),
            ("tvOS", "tvOS DeviceSupport"), ("visionOS", "visionOS DeviceSupport"),
            ("visionOS", "xrOS DeviceSupport"), ("macOS", "macOS DeviceSupport"),
        ]
        var dsChildren: [CacheNode] = []
        for (platform, folder) in platforms {
            let base = xcodeDir.appendingPathComponent(folder, isDirectory: true)
            let dirs = subdirs(base)
            guard !dirs.isEmpty else { continue }
            let newest = dirs.map { version(in: $0.lastPathComponent) }.max { $0.lexicographicallyPrecedes($1) } ?? []
            let rows = dirs.map { u -> CacheNode in
                let v = version(in: u.lastPathComponent)
                let older = v.lexicographicallyPrecedes(newest)
                let note = older
                    ? L("Symbols for an older \(platform) version. Xcode re-downloads them if you connect a device running this version.",
                        "Symbol của phiên bản \(platform) cũ. Xcode sẽ tải lại nếu bạn cắm thiết bị chạy phiên bản này.")
                    : L("Newest \(platform) version on this Mac. Xcode will copy the symbols again on your next debug session (5–10 minutes).",
                        "Phiên bản \(platform) mới nhất trên máy. Lần debug kế tiếp Xcode sẽ copy lại symbol (5–10 phút).")
                return leaf("xcode.ds.\(folder).\(u.lastPathComponent)", "\(platform) \(u.lastPathComponent)", u, t,
                            risk: older ? .safe : .rebuild, note: note, action: rm(u))
            }
            // newest first
            dsChildren += rows.sorted {
                version(in: $1.url.lastPathComponent).lexicographicallyPrecedes(version(in: $0.url.lastPathComponent))
            }
        }
        result.append(group("xcode.ds", "Device Support", xcodeDir, t,
                            path: "~/Library/Developer/Xcode/*DeviceSupport", children: dsChildren))

        // Simulator caches
        let sim = Paths.url("Library/Developer/CoreSimulator/Caches")
        result.append(leaf("xcode.sim", "Simulator caches", sim, t, risk: .safe,
                           note: L("Simulator dyld cache. The first Simulator launch will be a little slower.",
                                   "Cache dyld của Simulator. Simulator khởi động lần đầu sẽ chậm hơn một chút."),
                           action: toolAction("xcrun simctl delete unavailable",
                                              display: "xcrun simctl delete unavailable && rm -rf " + Paths.shellDisplay(sim) + "/*",
                                              remove: sim, contentsOnly: true)))

        // Archives are intentionally NOT listed: they hold released builds + dSYMs that can't be recreated.

        // Xcode's own cache & Playground simulators
        let xcCache = Paths.url("Library/Caches/com.apple.dt.Xcode")
        result.append(leaf("xcode.cache", L("Xcode cache", "Cache Xcode"), xcCache, t, risk: .safe,
                           note: L("Xcode's internal cache (temporary index, downloads). Recreated when you open Xcode.",
                                   "Cache nội bộ của Xcode (index tạm, tải xuống). Tự tạo lại khi mở Xcode."), action: rm(xcCache)))
        let pg = Paths.url("Library/Developer/XCPGDevices")
        result.append(leaf("xcode.xcpg", "Playground devices", pg, t, risk: .safe,
                           note: L("Temporary simulators created by Swift Playgrounds. Recreated when you run a playground.",
                                   "Simulator tạm do Swift Playgrounds tạo. Tự tạo lại khi chạy playground."), action: rm(pg)))

        #if !APPSTORE
        let runtimes = simulatorRuntimes()
        if !runtimes.isEmpty {
            result.append(group("xcode.runtimes", "Simulator runtimes", URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Images"),
                                t, path: "/Library/Developer/CoreSimulator (xcrun simctl runtime)", children: runtimes))
        }
        #endif

        // Documentation cache
        let doc = xcodeDir.appendingPathComponent("DocumentationCache", isDirectory: true)
        result.append(leaf("xcode.doc", "Documentation Cache", doc, t, risk: .safe,
                           note: L("Xcode re-downloads the docs when you open Developer Documentation.",
                                   "Xcode sẽ tải lại tài liệu khi bạn mở Developer Documentation."), action: rm(doc)))

        // Device logs
        let logs = xcodeDir.appendingPathComponent("iOS Device Logs", isDirectory: true)
        result.append(leaf("xcode.log", "iOS Device Logs", logs, t, risk: .safe,
                           note: L("Collected device logs. Xcode fetches them again when needed.",
                                   "Log thiết bị đã thu thập. Xcode sẽ lấy lại khi cần."), action: rm(logs)))
        return result
    }

    /// `Alpha-gxkqmzbfhvlcabcdefgh` -> `Alpha`
    static func projectName(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        let suffix = folder[folder.index(after: dash)...]
        if suffix.count >= 20, suffix.allSatisfy({ $0.isLetter && $0.isLowercase }) {
            return String(folder[..<dash])
        }
        return folder
    }

    static func workspacePath(_ derivedDataFolder: URL) -> String? {
        let plist = derivedDataFolder.appendingPathComponent("info.plist")
        guard let dict = NSDictionary(contentsOf: plist), let ws = dict["WorkspacePath"] as? String else { return nil }
        return Paths.tilde(URL(fileURLWithPath: ws))
    }

    /// First dotted number in a Device Support folder name: `iPhone15,2 17.5.1 (21F90)` -> [17, 5, 1]
    static func version(in name: String) -> [Int] {
        for token in name.split(separator: " ") {
            let tok = token.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            if let first = tok.first, first.isNumber, tok.allSatisfy({ $0.isNumber || $0 == "." }) {
                return tok.split(separator: ".").compactMap { Int($0) }
            }
        }
        return []
    }

    // MARK: - npm

    static func npm() -> [CacheNode] {
        let t = ToolKind.npm
        let ca = Paths.url(".npm/_cacache")
        let npx = Paths.url(".npm/_npx")
        let logs = Paths.url(".npm/_logs")
        return [
            leaf("npm.cacache", "_cacache", ca, t, risk: .rebuild,
                 note: L("The next npm install has to re-download packages from the registry.",
                         "Lần npm install kế tiếp phải tải lại package từ registry."),
                 action: toolAction("npm cache clean --force", display: "npm cache clean --force", remove: ca)),
            leaf("npm.npx", "_npx", npx, t, risk: .safe,
                 note: L("Temporary packages downloaded by npx. Running npx again re-downloads them.",
                         "Gói tạm do npx tải về. Chạy lại npx sẽ tự tải."), action: rm(npx)),
            leaf("npm.logs", "_logs", logs, t, risk: .safe, note: L("npm debug logs.", "Log debug của npm."), action: rm(logs)),
        ]
    }

    // MARK: - Yarn

    static func yarn() -> [CacheNode] {
        let t = ToolKind.yarn
        var result: [CacheNode] = []
        let classicBase = Paths.url("Library/Caches/Yarn")
        var classic = subdirs(classicBase).filter { $0.lastPathComponent.hasPrefix("v") }
        if classic.isEmpty { classic = [classicBase.appendingPathComponent("v6", isDirectory: true)] }
        for u in classic {
            let v = u.lastPathComponent
            result.append(leaf("yarn.classic.\(v)", "Yarn Classic cache (\(v))", u, t, risk: .rebuild,
                               note: L("The next yarn install has to re-download packages.",
                                        "Lần yarn install kế tiếp phải tải lại package."),
                               action: toolAction("yarn cache clean", display: "yarn cache clean", remove: u)))
        }
        let berry = Paths.url(".yarn/berry/cache")
        result.append(leaf("yarn.berry", "Yarn Berry global cache", berry, t, risk: .rebuild,
                           note: L("Projects using PnP will need yarn install again before they run.",
                                   "Dự án dùng PnP sẽ cần yarn install lại trước khi chạy."), action: rmContents(berry)))
        return result
    }

    // MARK: - Gradle

    static func gradle() -> [CacheNode] {
        let t = ToolKind.gradle
        let caches = Paths.url(".gradle/caches")
        var result: [CacheNode] = []

        let mod = caches.appendingPathComponent("modules-2", isDirectory: true)
        result.append(leaf("gradle.modules", "modules-2 (dependencies)", mod, t, risk: .rebuild,
                           note: L("Gradle re-downloads all dependencies on the next sync.",
                                   "Gradle sẽ tải lại toàn bộ dependency ở lần sync kế tiếp."), action: rm(mod)))

        var transforms = subdirs(caches).filter { $0.lastPathComponent.hasPrefix("transforms-") }
        if transforms.isEmpty { transforms = [caches.appendingPathComponent("transforms-4", isDirectory: true)] }
        for u in transforms {
            result.append(leaf("gradle.\(u.lastPathComponent)", u.lastPathComponent, u, t, risk: .safe,
                               note: L("Transformed artifacts (dex, jetified). Recreated on build.",
                                        "Artifact đã biến đổi (dex, jetified). Tự tạo lại khi build."), action: rm(u)))
        }

        let bc = caches.appendingPathComponent("build-cache-1", isDirectory: true)
        result.append(leaf("gradle.buildcache", "build-cache-1", bc, t, risk: .safe,
                           note: L("Local build cache. The next build can't reuse previous outputs.",
                                   "Build cache cục bộ. Build kế tiếp không dùng lại được output cũ."), action: rm(bc)))

        let distsURL = Paths.url(".gradle/wrapper/dists")
        let dists: [CacheNode] = subdirs(distsURL).map { u -> CacheNode in
            let s = stats(u)
            let old = isStale(s.modified, days: 30)
            return leaf("gradle.dist.\(u.lastPathComponent)", u.lastPathComponent, u, t,
                        risk: old ? .safe : .rebuild,
                        note: old ? L("Unused for over 30 days. ./gradlew re-downloads it if a project needs it.",
                                    "Không dùng hơn 30 ngày. ./gradlew sẽ tải lại nếu dự án cần.")
                                  : L("Used recently. ./gradlew will re-download it when run.",
                                    "Đang dùng gần đây. ./gradlew sẽ tải lại khi chạy."),
                        action: rm(u), stats: s)
        }
        result.append(group("gradle.wrapper", "Wrapper dists", distsURL, t, children: dists))

        let daemon = Paths.url(".gradle/daemon")
        result.append(leaf("gradle.daemon", "Daemon logs", daemon, t, risk: .safe,
                           note: L("Gradle daemon logs. The daemon is stopped before deleting.",
                                   "Log của Gradle daemon. Daemon sẽ được dừng trước khi xoá."),
                           action: toolAction("gradle --stop", display: "gradle --stop && rm -rf ~/.gradle/daemon", remove: daemon)))
        return result
    }

    // MARK: - Git

    static func git(roots: [URL]) -> [CacheNode] {
        let t = ToolKind.git
        var seen = Set<String>()
        var result: [CacheNode] = []
        for root in roots {
            for repo in findRepos(in: root) where seen.insert(repo.path).inserted {
                let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
                let q = Paths.shellQuote(repo.path)
                let shown = Paths.shellDisplay(repo)
                var children: [CacheNode] = []

                let lfs = gitDir.appendingPathComponent("lfs/objects", isDirectory: true)
                let lfsStats = stats(lfs)
                #if APPSTORE
                // Sandboxed build can't run git, and deleting LFS/objects directly could lose data.
                _ = (q, shown, lfsStats)
                #else
                if lfsStats.size > 0 {
                    children.append(leaf("git.\(repo.path).lfs", "LFS objects", lfs, t, risk: .rebuild,
                                         note: L("Only removes old LFS copies that are no longer checked out. Current files are kept.",
                                                  "Chỉ xoá bản LFS cũ không còn được checkout. File hiện tại giữ nguyên."),
                                         action: CleanAction(command: "git -C \(q) lfs prune", display: "git -C \(shown) lfs prune"),
                                         stats: lfsStats))
                }

                // Loose objects can only be packed safely by git itself (never deleted directly).
                let objects = gitDir.appendingPathComponent("objects", isDirectory: true)
                let loose = looseStats(objects)
                if loose.size >= 1_000_000 {
                    children.append(leaf("git.\(repo.path).gc", "Loose objects", objects, t, risk: .safe,
                                         note: L("Packs loose objects. No commits are lost.", "Nén object rời vào pack. Không mất commit."),
                                         action: CleanAction(command: "git -C \(q) gc --prune=now", display: "git -C \(shown) gc --prune=now"),
                                         stats: loose))
                }
                #endif

                if !children.isEmpty {
                    result.append(group("git.\(repo.path)", repo.lastPathComponent, gitDir, t, children: children))
                }
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    static func findRepos(in root: URL, maxDepth: Int = 4) -> [URL] {
        let fm = FileManager.default
        let skip: Set<String> = ["node_modules", "Pods", "DerivedData", "build", "Build", "vendor", "Carthage", "Library", "dist"]
        var found: [URL] = []
        var queue: [(URL, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (dir, depth) = queue[index]
            index += 1
            if fm.fileExists(atPath: dir.appendingPathComponent(".git/objects").path) {
                found.append(dir)
                continue
            }
            guard depth < maxDepth else { continue }
            for c in subdirs(dir) where !skip.contains(c.lastPathComponent) && c.pathExtension != "app" {
                queue.append((c, depth + 1))
            }
        }
        return found
    }

    /// Loose objects live in `.git/objects/xx/` (two hex chars).
    static func looseStats(_ objects: URL) -> DirStats {
        let hex = Set("0123456789abcdef")
        return subdirs(objects)
            .filter { $0.lastPathComponent.count == 2 && $0.lastPathComponent.allSatisfy { hex.contains($0) } }
            .reduce(DirStats()) { $0 + stats($1) }
    }

    // MARK: - Claude Code

    static func claude() -> [CacheNode] {
        let t = ToolKind.claude
        // ~/.claude/projects (session history) is intentionally NOT listed – it can't be recreated.
        let logs = Paths.url("Library/Caches/claude-cli-nodejs")
        let shell = Paths.url(".claude/shell-snapshots")
        let todos = Paths.url(".claude/todos")
        return [
            leaf("claude.logs", L("CLI & MCP logs", "Log CLI & MCP"), logs, t, risk: .safe,
                 note: L("Debug logs from the CLI and MCP servers.", "Log debug của CLI và MCP server."), action: rm(logs)),
            leaf("claude.shell", "Shell snapshots", shell, t, risk: .safe,
                 note: L("Shell environment snapshots, recreated each session.", "Snapshot môi trường shell, tự tạo lại mỗi phiên."), action: rm(shell)),
            leaf("claude.todos", "Todos", todos, t, risk: .safe,
                 note: L("Todo lists from finished sessions.", "Danh sách todo của các phiên đã kết thúc."), action: rm(todos)),
        ] + claudeDesktop()
    }

    /// Claude desktop app: Cowork / Claude Code VM bundles and Electron caches.
    /// Everything here must only be removed while the Claude app is quit.
    static func claudeDesktop() -> [CacheNode] {
        let t = ToolKind.claude
        let support = Paths.url("Library/Application Support/Claude")
        let quit = AppRunning.claudeDesktopBundleID
        let quitNote = L(" Fully quit the Claude app (⌘Q) before deleting.", " Thoát hẳn app Claude (⌘Q) trước khi xoá.")
        var result: [CacheNode] = []

        // VM bundles: ~/Library/Application Support/Claude/vm_bundles/*.bundle
        let vmRoot = support.appendingPathComponent("vm_bundles", isDirectory: true)
        let fm = FileManager.default
        var vmChildren: [CacheNode] = []
        let bundles = (try? fm.contentsOfDirectory(at: vmRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for bundle in bundles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: bundle.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            var rows: [CacheNode] = []
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = f.lastPathComponent
                let s = stats(f)
                guard s.size >= 1_000_000 else { continue }   // skip tiny metadata (macAddress, markers…)
                // Hidden `.<name>.origin` marker must go together with the image it describes.
                let origin = bundle.appendingPathComponent(".\(name).origin")
                let extras = fm.fileExists(atPath: origin.path) ? [origin] : []
                let action = CleanAction(removeURL: f, extraRemovals: extras, requiresQuitBundleID: quit,
                                         display: "rm -f " + Paths.shellDisplay(f))
                let risk: Risk
                let title: String
                let note: String
                if name.hasSuffix(".zst") || name.hasSuffix(".partial") {
                    risk = .safe
                    title = name.hasSuffix(".partial")
                        ? L("Incomplete download (\(name))", "Tải dở (\(name))")
                        : L("Leftover archive (\(name))", "Bản nén thừa (\(name))")
                    note = L("Archive or partial download kept after extraction. The VM doesn't use this file.",
                             "Bản nén/tải dở được giữ lại sau khi đã giải nén. Máy ảo không dùng đến file này.") + quitNote
                } else if name.hasPrefix("sessiondata") {
                    continue   // Cowork session history – can't be recreated, never offered
                } else if name.hasPrefix("rootfs") {
                    risk = .rebuild
                    title = L("VM disk (\(name))", "Ổ đĩa máy ảo (\(name))")
                    note = L("Linux disk of the Cowork/Claude Code VM. Next time you open Cowork, Claude re-downloads it (~1 GB) and extracts it again (~10 GB).",
                             "Ổ đĩa Linux của máy ảo Cowork/Claude Code. Lần mở Cowork kế tiếp, Claude sẽ tải lại (~1 GB) và giải nén lại (~10 GB).") + quitNote
                } else {
                    risk = .rebuild
                    title = name
                    note = L("VM boot files (kernel/initrd). Claude re-downloads them when needed.",
                             "File khởi động của máy ảo (kernel/initrd). Claude sẽ tải lại khi cần.") + quitNote
                }
                rows.append(leaf("claude.vm.\(bundle.lastPathComponent).\(name)", title, f, t,
                                 risk: risk, note: note, action: action, stats: s))
            }
            if !rows.isEmpty {
                vmChildren.append(group("claude.vm.\(bundle.lastPathComponent)", bundle.lastPathComponent, bundle, t,
                                        children: rows.sorted { $0.leafSize > $1.leafSize }))
            }
        }
        // Flatten when there is a single bundle (the usual case).
        if vmChildren.count == 1, let only = vmChildren.first {
            vmChildren = only.children ?? []
        }
        result.append(group("claude.vm", L("Claude desktop VM (Cowork)", "Máy ảo Claude desktop (Cowork)"), vmRoot, t, children: vmChildren))

        // Electron caches of the desktop app
        for (id, name) in [("Cache", L("Claude desktop app cache", "Cache app Claude desktop")),
                         ("Code Cache", L("Claude desktop app Code Cache", "Code Cache app Claude desktop"))] {
            let u = support.appendingPathComponent(id, isDirectory: true)
            result.append(leaf("claude.desktop.\(id)", name, u, t, risk: .safe,
                               note: L("UI cache of the Claude desktop app, recreated when the app opens.",
                                        "Cache giao diện của app Claude desktop, tự tạo lại khi mở app.") + quitNote,
                               action: CleanAction(removeURL: u, requiresQuitBundleID: quit,
                                                   display: "rm -rf " + Paths.shellDisplay(u))))
        }
        return result
    }
}
