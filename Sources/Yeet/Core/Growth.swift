import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

// MARK: - Snapshot

/// One measurement of the disk: used space plus the size of every folder up to a few levels deep.
struct DiskSnapshot: Codable, Sendable {
    var date: Date
    var diskTotal: Int64
    var diskUsed: Int64
    /// Absolute folder path → allocated bytes (folders ≥ 1 MB only).
    var folders: [String: Int64]
    /// Roots that were walked (Home, /Applications, …) → their total size.
    var roots: [String: Int64]
    /// Local APFS / Time Machine snapshots on "/" (direct build only, -1 when unknown).
    var localSnapshots: Int = -1
    /// Folders that were not walked (e.g. other apps' containers without Full Disk Access).
    var skipped: [String] = []

    var trackedTotal: Int64 { roots.values.reduce(0, +) }

    /// Removes `paths` from the measurement so two snapshots taken with different access
    /// (Full Disk Access granted/revoked in between) compare like for like.
    func excluding(_ paths: Set<String>) -> DiskSnapshot {
        guard !paths.isEmpty else { return self }
        var out = self
        for p in paths where !skipped.contains(p) {
            let size = folders[p] ?? 0
            guard size > 0 else { continue }
            var parent = (p as NSString).deletingLastPathComponent
            while let v = out.folders[parent] {
                out.folders[parent] = v - size
                parent = (parent as NSString).deletingLastPathComponent
            }
            for (r, v) in out.roots where p.hasPrefix(r + "/") { out.roots[r] = v - size }
        }
        out.folders = out.folders.filter { key, _ in
            !paths.contains { key == $0 || key.hasPrefix($0 + "/") }
        }
        out.skipped = Array(Set(skipped).union(paths))
        return out
    }
}

extension DiskSnapshot {
    private enum CodingKeys: String, CodingKey {
        case date, diskTotal, diskUsed, folders, roots, localSnapshots, skipped
    }

    /// Tolerant decoding: fields added later default instead of dropping the file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        diskTotal = try c.decodeIfPresent(Int64.self, forKey: .diskTotal) ?? 0
        diskUsed = try c.decode(Int64.self, forKey: .diskUsed)
        folders = try c.decodeIfPresent([String: Int64].self, forKey: .folders) ?? [:]
        roots = try c.decodeIfPresent([String: Int64].self, forKey: .roots) ?? [:]
        localSnapshots = try c.decodeIfPresent(Int.self, forKey: .localSnapshots) ?? -1
        skipped = try c.decodeIfPresent([String].self, forKey: .skipped) ?? []
    }
}

struct SnapshotInfo: Identifiable, Hashable {
    let id: String          // yyyy-MM-dd
    let date: Date
    let diskUsed: Int64
}

// MARK: - Diff tree

struct GrowthNode: Identifiable, Hashable {
    let id: String          // absolute path
    var name: String
    var before: Int64
    var after: Int64
    var children: [GrowthNode]
    var delta: Int64 { after - before }
    var url: URL { URL(fileURLWithPath: id) }
    var displayPath: String { Paths.tilde(url) }
}

// MARK: - Cancellation

/// Thread-safe flag checked by the background walk ("Stop Analysis").
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

// MARK: - Scanner

enum GrowthScanner {
    /// Folders deeper than this (relative to each root) are folded into their ancestor.
    static let homeDepth = 3

    /// Roots measured besides Home, with their depth.
    static var extraRoots: [(URL, Int)] {
        var r: [(URL, Int)] = []
        #if !APPSTORE
        r.append((URL(fileURLWithPath: "/Applications", isDirectory: true), 1))
        r.append((URL(fileURLWithPath: "/Library/Developer", isDirectory: true), 2))
        r.append((URL(fileURLWithPath: "/opt/homebrew", isDirectory: true), 1))
        #endif
        return r.filter { FileManager.default.fileExists(atPath: $0.0.path) }
    }

    /// Folders inside Home that are not walked, so a (background) capture never pops a privacy
    /// prompt: other apps' containers and Desktop/Documents/Downloads until the user allowed
    /// them explicitly (or Yeet has Full Disk Access), plus folders the user switched off.
    static func skippedHomeFolders(hasFDA: Bool) -> Set<String> {
        var s = Set<String>()
        if !(hasFDA || ProtectedFolders.mayMeasureContainers) {
            s.insert(ProtectedFolders.containersURL.path)
            s.insert(ProtectedFolders.groupContainersURL.path)
        }
        for f in ProtectedFolders.folders {
            let allowed = hasFDA ? ProtectedFolders.isEnabled(f.key) : ProtectedFolders.mayAccess(f.key)
            if !allowed { s.insert(f.url.path) }
        }
        // Cloud drives (Dropbox, Google Drive, OneDrive, iCloud Drive) are File Provider domains:
        // on macOS 14+ reading them can ask “access files managed by …”. Only with FDA.
        if !hasFDA && !BuildFlavor.isAppStore {
            s.insert(Paths.url("Library/CloudStorage").path)
            s.insert(Paths.url("Library/Mobile Documents").path)
        }
        return s
    }

    /// Friendly names for skipped folders (for the “not measured” banner).
    static func skippedNames(_ paths: [String]) -> [String] {
        paths.sorted().map { p in
            if p == ProtectedFolders.containersURL.path { return "Containers" }
            if p == ProtectedFolders.groupContainersURL.path { return "Group Containers" }
            if p.hasSuffix("/Library/CloudStorage") { return "Cloud (Dropbox, Drive…)" }
            if p.hasSuffix("/Library/Mobile Documents") { return "iCloud Drive" }
            return (p as NSString).lastPathComponent
        }
    }

    /// Walks the tree once and attributes every file's allocated size to its ancestors
    /// up to `maxDepth` levels below `root`.
    static func walk(_ root: URL, maxDepth: Int, skip: Set<String>, folders: inout [String: Int64],
                     cancel: CancelToken? = nil, progress: (Int) -> Void) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let keySet = Set(keys)
        let rootPath = root.standardizedFileURL.path
        let rootCount = root.standardizedFileURL.pathComponents.count
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                      errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        var files = 0
        while let item = en.nextObject() as? URL {
            guard let rv = try? item.resourceValues(forKeys: keySet) else { continue }
            if rv.isDirectory == true {
                if skip.contains(item.path) { en.skipDescendants() }
                continue
            }
            guard rv.isRegularFile == true else { continue }
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            total += size
            files += 1
            if files % 5_000 == 0 {
                progress(files)
                if cancel?.isCancelled == true { break }
            }
            let comps = item.pathComponents
            let depth = comps.count - rootCount          // 1 = file directly in root
            guard depth >= 2 else { continue }
            var path = rootPath
            for d in 0..<min(maxDepth, depth - 1) {
                path += (path.hasSuffix("/") ? "" : "/") + comps[rootCount + d]
                folders[path, default: 0] += size
            }
        }
        progress(files)
        return total
    }

    /// Returns nil when cancelled (nothing is saved then).
    static func capture(hasFDA: Bool, cancel: CancelToken? = nil, progress: @escaping (Int) -> Void) -> DiskSnapshot? {
        var folders: [String: Int64] = [:]
        var roots: [String: Int64] = [:]
        var counted = 0, lastN = 0
        let report: (Int) -> Void = { n in lastN = n; progress(counted + n) }

        let home = Paths.home
        roots[home.path] = walk(home, maxDepth: homeDepth, skip: skippedHomeFolders(hasFDA: hasFDA),
                                folders: &folders, cancel: cancel, progress: report)
        for (root, depth) in extraRoots {
            if cancel?.isCancelled == true { break }
            counted += lastN; lastN = 0
            roots[root.path] = walk(root, maxDepth: depth, skip: [], folders: &folders, cancel: cancel, progress: report)
        }
        if cancel?.isCancelled == true { return nil }
        // Keep the file small: drop folders under 1 MB.
        folders = folders.filter { $0.value >= 1_000_000 }

        var total: Int64 = 0, used: Int64 = 0
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            total = Int64(v.volumeTotalCapacity ?? 0)
            used = total - Int64(v.volumeAvailableCapacity ?? 0)
        }
        var snap = DiskSnapshot(date: Date(), diskTotal: total, diskUsed: used, folders: folders, roots: roots)
        snap.skipped = Array(skippedHomeFolders(hasFDA: hasFDA))
        #if !APPSTORE
        if let out = Shell.capture("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 10) {
            snap.localSnapshots = out.split(separator: "\n").filter { $0.contains("com.apple") }.count
        }
        #endif
        return snap
    }

    /// Builds the growth tree between two snapshots, keeping nodes whose size changed ≥ `minDelta`.
    static func diff(_ a: DiskSnapshot, _ b: DiskSnapshot, minDelta: Int64 = 10_000_000) -> [GrowthNode] {
        let allRoots = Set(a.roots.keys).union(b.roots.keys)
        var byParent: [String: [String]] = [:]
        for path in Set(a.folders.keys).union(b.folders.keys) {
            let parent = (path as NSString).deletingLastPathComponent
            byParent[parent, default: []].append(path)
        }
        func build(_ path: String, before: Int64, after: Int64, name: String) -> GrowthNode {
            let kids = (byParent[path] ?? [])
                .map { p in build(p, before: a.folders[p] ?? 0, after: b.folders[p] ?? 0,
                                  name: (p as NSString).lastPathComponent) }
                .filter { abs($0.delta) >= minDelta }
                .sorted { $0.delta > $1.delta }
            return GrowthNode(id: path, name: name, before: before, after: after, children: kids)
        }
        return allRoots.map { root in
            let name = root == Paths.home.path ? L("Home folder (~)", "Thư mục người dùng (~)") : root
            return build(root, before: a.roots[root] ?? 0, after: b.roots[root] ?? 0, name: name)
        }
        .sorted { $0.delta > $1.delta }
    }

    /// Largest leaf-most growth (for notifications): follows the biggest child down the tree.
    static func topCause(_ nodes: [GrowthNode]) -> GrowthNode? {
        guard var n = nodes.filter({ $0.delta > 0 }).max(by: { $0.delta < $1.delta }) else { return nil }
        while let c = n.children.first, c.delta > 0, Double(c.delta) >= Double(n.delta) * 0.5 { n = c }
        return n
    }
}

// MARK: - Store

@Observable
final class GrowthStore {
    /// Shared so the app delegate can run the daily schedule even without a window
    /// (menu bar / launched at login).
    static let shared = GrowthStore()

    var snapshots: [SnapshotInfo] = []
    var current: DiskSnapshot?
    @ObservationIgnored private var rawCurrent: DiskSnapshot?
    var baseline: DiskSnapshot?
    var baselineID: String?
    var tree: [GrowthNode] = []
    var expanded: Set<String> = []
    var focused: String?
    var isCapturing = false
    var progressFiles = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var cancelToken: CancelToken?
    /// True between “Stop Analysis” and the walk actually stopping.
    var isCancelling = false

    /// Stops a running capture; nothing is saved.
    func cancelCapture() {
        guard isCapturing, let token = cancelToken else { return }
        isCancelling = true
        token.cancel()
    }
    @ObservationIgnored private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let notifyKey = "growthNotify"
    static let thresholdKey = "growthThresholdGB"
    static let keepDays = 60

    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? Paths.url("Library/Application Support")
        return base.appendingPathComponent("Yeet/Snapshots", isDirectory: true)
    }

    // MARK: Loading

    /// Reads the snapshot list off the main thread (up to 60 files), then rebuilds the diff.
    func load() {
        let dir = folder
        let wantedBaseline = baselineID
        Task { @MainActor in
            let (infos, cur) = await Task.detached(priority: .userInitiated) { () -> ([SnapshotInfo], DiskSnapshot?) in
                let fm = FileManager.default
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension == "json" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                var infos: [SnapshotInfo] = []
                var last: DiskSnapshot?
                for f in files {
                    guard let s = GrowthStore.read(f) else { continue }
                    infos.append(SnapshotInfo(id: f.deletingPathExtension().lastPathComponent, date: s.date, diskUsed: s.diskUsed))
                    last = s
                }
                return (infos, last)
            }.value
            snapshots = infos
            rawCurrent = cur
            if wantedBaseline == nil || !infos.contains(where: { $0.id == wantedBaseline }) {
                baselineID = defaultBaseline()?.id
            }
            rebuild()
        }
    }

    func selectBaseline(_ id: String) {
        baselineID = id
        rebuild()
    }

    /// Yesterday's snapshot if there is one, else the newest older one.
    func defaultBaseline() -> SnapshotInfo? {
        guard let cur = snapshots.last else { return nil }
        return snapshots.dropLast().last { $0.id != cur.id }
    }

    func snapshot(daysBefore days: Int) -> SnapshotInfo? {
        guard let cur = snapshots.last else { return nil }
        let target = cur.date.addingTimeInterval(-Double(days) * 86_400)
        return snapshots.dropLast().min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
    }

    private func rebuild() {
        let rawBaseline = baselineID.flatMap { Self.read(file(for: $0)) }
        if let b = rawBaseline, let c = rawCurrent {
            // Compare like for like: drop folders either snapshot couldn't read.
            let skip = Set(b.skipped).union(c.skipped)
            baseline = b.excluding(skip)
            current = c.excluding(skip)
        } else {
            baseline = rawBaseline
            current = rawCurrent
        }
        if let b = baseline, let c = current {
            tree = GrowthScanner.diff(b, c)
        } else if let c = current {
            // First day: show the biggest folders (compared against nothing).
            let empty = DiskSnapshot(date: c.date, diskTotal: c.diskTotal, diskUsed: 0, folders: [:], roots: [:])
            tree = GrowthScanner.diff(empty, c, minDelta: 200_000_000)
        } else {
            tree = []
        }
        if expanded.isEmpty, let top = tree.first { expanded = [top.id] }
    }

    func find(_ id: String?) -> GrowthNode? {
        guard let id else { return nil }
        func search(_ nodes: [GrowthNode]) -> GrowthNode? {
            for n in nodes {
                if n.id == id { return n }
                if let r = search(n.children) { return r }
            }
            return nil
        }
        return search(tree)
    }

    // MARK: Capturing

    var lastCaptureDate: Date? { snapshots.last?.date }

    /// Called at launch and every hour: captures when the last snapshot is older than ~20h.
    @MainActor
    func startSchedule() {
        guard timer == nil else { return }       // idempotent: window + app delegate both call it
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
        // Catch up after the Mac wakes from sleep.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                self?.captureIfNeeded()
            }
        }
        // Give the cache scan a head start.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            self?.captureIfNeeded()
        }
    }

    @MainActor
    func captureIfNeeded() {
        if let last = lastCaptureDate, Date().timeIntervalSince(last) < 20 * 3_600 { return }
        capture()
    }

    @MainActor
    func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        isCancelling = false
        progressFiles = 0
        let hasFDA = BuildFlavor.isAppStore ? false : Permissions.hasFullDiskAccess()
        let token = CancelToken()
        cancelToken = token
        Task { @MainActor in
            let result = await Task.detached(priority: .utility) { () -> DiskSnapshot? in
                GrowthScanner.capture(hasFDA: hasFDA, cancel: token) { n in
                    DispatchQueue.main.async { [weak self] in self?.progressFiles = n }
                }
            }.value
            cancelToken = nil
            guard let snap = result else {
                // Stopped by the user: keep the previous data untouched.
                isCapturing = false
                isCancelling = false
                return
            }
            // Previous day's snapshot (re-capturing today overwrites today's file).
            let todayID = dayFormatter.string(from: snap.date)
            let previous = snapshots.last { $0.id != todayID }.flatMap { Self.read(file(for: $0.id)) }
            save(snap)
            prune()
            load()
            isCapturing = false
            if let previous { notifyIfNeeded(new: snap, previous: previous) }
        }
    }

    private func save(_ s: DiskSnapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(s) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(for: dayFormatter.string(from: s.date)), options: .atomic)
    }

    private func prune() {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for f in files.dropLast(Self.keepDays) { try? fm.removeItem(at: f) }
    }

    static func read(_ url: URL) -> DiskSnapshot? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? dec.decode(DiskSnapshot.self, from: $0) }
    }

    private func file(for id: String) -> URL { folder.appendingPathComponent(id + ".json") }

    // MARK: Notifications

    @MainActor
    private func notifyIfNeeded(new: DiskSnapshot, previous: DiskSnapshot) {
        guard Self.canNotify, UserDefaults.standard.bool(forKey: Self.notifyKey) else { return }
        let skip = Set(new.skipped).union(previous.skipped)
        let cur = new.excluding(skip)
        let prevSnap = previous.excluding(skip)
        let threshold = UserDefaults.standard.double(forKey: Self.thresholdKey)
        let limit = Int64((threshold > 0 ? threshold : 5) * 1_000_000_000)
        let delta = cur.diskUsed - prevSnap.diskUsed
        guard delta >= limit else { return }
        let cause = GrowthScanner.topCause(GrowthScanner.diff(prevSnap, cur))
        let content = UNMutableNotificationContent()
        content.title = L("Disk usage grew by \(Fmt.size(delta)) since \(Fmt.modified(prevSnap.date))",
                          "Ổ đĩa tăng \(Fmt.size(delta)) kể từ \(Fmt.modified(prevSnap.date))")
        content.body = cause.map { L("Biggest growth: \($0.displayPath) (+\(Fmt.size($0.delta)))",
                                     "Tăng nhiều nhất: \($0.displayPath) (+\(Fmt.size($0.delta)))") }
            ?? L("Most of it is outside the folders Yeet tracks (system, snapshots).",
                 "Phần lớn nằm ngoài các thư mục Yeet theo dõi (hệ thống, snapshot).")
        content.sound = .default
        let req = UNNotificationRequest(identifier: "yeet.growth.\(Int(cur.date.timeIntervalSince1970))",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// UNUserNotificationCenter crashes in an unbundled executable (`swift run`).
    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestNotificationPermission(_ done: @escaping (Bool) -> Void) {
        guard canNotify else { done(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

// MARK: - Login item

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
