// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// Duplicate finder: exact duplicates (same size + same SHA-256 of the content) in the user's own
// folders (the visible folders of Home, never ~/Library). Always keeps at least one copy; removals
// go to the Trash after re-checking that each file is unchanged since the scan.

import CryptoKit
import Foundation
import Observation

struct DupFile: Identifiable, Hashable {
    let url: URL
    let modified: Date?
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var location: String { Paths.tilde(url.deletingLastPathComponent()) }
}

struct DupGroup: Identifiable, Hashable {
    /// Size of each copy (logical bytes).
    let size: Int64
    let kind: FileKind
    /// Oldest first.
    var files: [DupFile]

    /// Stable for the life of the group: the oldest copy's path.
    let id: String

    var name: String { files.first?.name ?? "" }
    /// Bytes taken by the extra copies.
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
}

enum KeepRule: String, CaseIterable, Identifiable {
    case oldest, newest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oldest: return L("Oldest", "Cũ nhất")
        case .newest: return L("Newest", "Mới nhất")
        }
    }
}

@Observable
final class DuplicatesStore {
    static let shared = DuplicatesStore()

    /// Minimum file size choices (base-1024 like MacSweep: 100 KB, 1 MB, 10 MB).
    static let sizeOptions: [Int64] = [100 * 1024, 1024 * 1024, 10 * 1024 * 1024]
    /// Bytes read from each end of a file for the quick first-pass hash.
    static let edge: Int = 16 * 1024
    /// Most groups kept (the most wasteful ones).
    static let maxGroups = 2_000

    var groups: [DupGroup] = []
    var scanning = false
    var scanned = false
    var trashing = false
    /// The last scan was stopped early, so the results are incomplete.
    var partial = false
    /// 0 = listing files, 1 = comparing contents.
    var stage = 0
    /// Files seen (stage 0) or hashed (stage 1) by the running scan.
    var progress = 0
    /// What the sandbox let the last scan read (nil before the first scan).
    var access: HomeAccess.Report? = nil
    var minSize: Int64 = 1024 * 1024
    /// Which copy the "select extra copies" actions keep.
    var keep: KeepRule = .oldest {
        didSet { if keep != oldValue { applyKeep() } }
    }
    /// Paths of copies ticked for removal. Never every copy of a group.
    var checked: Set<String> = []
    /// Group shown in the detail pane.
    var focusedGroup: String? = nil

    @ObservationIgnored private var job: ScanProgress? = nil
    @ObservationIgnored private var hashJob: ScanProgress? = nil

    // MARK: Derived

    /// Space taken by every extra copy (one copy per group is kept).
    var total: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var wasted: Int64 { total }
    var extraCopies: Int { groups.reduce(0) { $0 + max(0, $1.files.count - 1) } }

    var selectedCount: Int {
        groups.reduce(0) { acc, g in acc + g.files.filter { checked.contains($0.id) }.count }
    }

    var selectedSize: Int64 {
        groups.reduce(0) { acc, g in acc + g.size * Int64(g.files.filter { checked.contains($0.id) }.count) }
    }

    var focused: DupGroup? {
        if let id = focusedGroup, let g = groups.first(where: { $0.id == id }) { return g }
        return groups.first
    }

    /// The copy the Keep rule keeps.
    func keeper(_ g: DupGroup) -> DupFile? {
        keep == .oldest ? g.files.first : g.files.last
    }

    func removedCount(_ g: DupGroup) -> Int { g.files.filter { checked.contains($0.id) }.count }

    func checkState(_ g: DupGroup) -> CheckState {
        let n = removedCount(g)
        if n == 0 { return .unchecked }
        return n >= g.files.count - 1 ? .checked : .partial
    }

    // MARK: Selection

    /// Ticks every copy in one group except the one the Keep rule keeps.
    func selectGroup(_ g: DupGroup) {
        let keepID = keeper(g)?.id
        for f in g.files {
            if f.id == keepID { checked.remove(f.id) } else { checked.insert(f.id) }
        }
    }

    func clearGroup(_ g: DupGroup) {
        for f in g.files { checked.remove(f.id) }
    }

    func toggleGroup(_ g: DupGroup) {
        if removedCount(g) > 0 { clearGroup(g) } else { selectGroup(g) }
    }

    func selectAllExtraCopies() {
        for g in groups { selectGroup(g) }
    }

    func deselectAll() { checked.removeAll() }

    /// Ticks / unticks one copy. Returns false (and changes nothing) when ticking it would mark
    /// every copy of the group for removal.
    @discardableResult
    func toggle(_ file: DupFile, in g: DupGroup) -> Bool {
        if checked.contains(file.id) {
            checked.remove(file.id)
            return true
        }
        let others = g.files.filter { $0.id != file.id && !checked.contains($0.id) }
        guard !others.isEmpty else { return false }
        checked.insert(file.id)
        return true
    }

    /// Re-applies the Keep rule, but only to groups the user already selected.
    private func applyKeep() {
        for g in groups where removedCount(g) > 0 { selectGroup(g) }
    }

    // MARK: Scan

    func cancel() {
        job?.cancel()
        if scanning { partial = true }
    }

    func scan() {
        guard !scanning else { return }
        job?.cancel()
        let p = ScanProgress()
        let h = ScanProgress()
        job = p
        hashJob = h
        scanning = true
        partial = false
        stage = 0
        progress = 0
        let min = minSize

        Task { @MainActor [weak self] in
            while let self, self.scanning, self.job === p {
                if h.count > 0 {
                    self.stage = 1
                    self.progress = h.count
                } else {
                    self.progress = p.count
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .userInitiated) { () -> [DupGroup] in
                DuplicatesStore.findDuplicates(roots: DuplicatesStore.scanRoots(), minBytes: min,
                                               progress: p, hashed: h)
            }.value
            guard let self, self.job === p else { return }
            // Nothing is selected until the user chooses.
            self.groups = found
            self.checked = []
            self.focusedGroup = found.first?.id
            self.partial = p.isCancelled
            self.access = HomeAccess.check()
            self.scanning = false
            self.scanned = true
            self.stage = 0
            self.job = nil
            self.hashJob = nil
        }
    }

    // MARK: Removal

    /// Moves the ticked copies to the Trash after re-checking that each one is unchanged since the
    /// scan and that at least one unticked copy of its group still exists with the same size.
    @MainActor
    @discardableResult
    func trashSelected() async -> FileOps.Outcome {
        guard !trashing else { return FileOps.Outcome() }
        struct Plan {
            let size: Int64
            let remove: [DupFile]
            let kept: [DupFile]
        }
        var plans: [Plan] = []
        for g in groups {
            let remove = g.files.filter { checked.contains($0.id) }
            guard !remove.isEmpty else { continue }
            let kept = g.files.filter { !checked.contains($0.id) }
            plans.append(Plan(size: g.size, remove: remove, kept: kept))
        }
        guard !plans.isEmpty else { return FileOps.Outcome() }
        trashing = true

        let outcome = await Task.detached(priority: .userInitiated) { () -> FileOps.Outcome in
            var urls: [URL] = []
            var sizes: [URL: Int64] = [:]
            var skipped = 0
            for plan in plans {
                let keeperOK = plan.kept.contains { k in
                    SweepRules.currentState(k.url)?.size == plan.size
                }
                guard keeperOK else {
                    skipped += plan.remove.count
                    continue
                }
                for f in plan.remove {
                    if let now = SweepRules.currentState(f.url), now.size == plan.size,
                       SweepRules.sameDate(now.modified, f.modified) {
                        urls.append(f.url)
                        sizes[f.url] = plan.size
                    } else {
                        skipped += 1
                    }
                }
            }
            var out = FileOps.moveToTrash(urls, sizes: sizes)
            if skipped > 0 {
                out.failures.append(L(skipped == 1 ? "1 file changed since the scan and was left alone."
                                                   : "\(skipped) files changed since the scan and were left alone.",
                                      "\(skipped) file đã thay đổi sau khi quét nên được giữ nguyên."))
            }
            return out
        }.value

        // Drop copies that are really gone, and groups left with a single copy.
        let fm = FileManager.default
        var next: [DupGroup] = []
        for var g in groups {
            g.files = g.files.filter { fm.fileExists(atPath: $0.url.path) }
            if g.files.count >= 2 { next.append(g) }
        }
        groups = next
        var alive: Set<String> = []
        for g in next { for f in g.files { alive.insert(f.id) } }
        checked = checked.filter { alive.contains($0) }
        if let id = focusedGroup, !next.contains(where: { $0.id == id }) { focusedGroup = next.first?.id }
        trashing = false
        return outcome
    }

    // MARK: Engine (background)

    private struct Entry {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    /// Folders to search: the visible folders in Home (Desktop, Documents, Downloads, Pictures,
    /// Movies, Music…), never ~/Library.
    static func scanRoots() -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? fm.contentsOfDirectory(at: Paths.home, includingPropertiesForKeys: keys,
                                                    options: [])) ?? []
        return children.filter { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            guard v.isDirectory == true, v.isSymbolicLink != true else { return false }
            return !skipDir(url.lastPathComponent)
        }
    }

    static func skipDir(_ name: String) -> Bool {
        SweepRules.isHidden(name) || SweepRules.devDirs.contains(name) || SweepRules.isPackage(name)
    }

    private static func listFiles(roots: [URL], minBytes: Int64, progress: ScanProgress) -> [Entry] {
        let fm = FileManager.default
        let keys = SweepRules.walkKeys
        let keySet = Set(keys)
        var out: [Entry] = []
        var seenInodes: Set<String> = []
        for root in roots {
            if progress.isCancelled { break }
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                        options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }
            var batch = 0
            while let obj = e.nextObject() {
                guard let url = obj as? URL else { continue }
                batch += 1
                if batch >= 256 {
                    progress.tick(batch)
                    batch = 0
                    if progress.isCancelled { break }
                }
                let name = url.lastPathComponent
                guard let v = try? url.resourceValues(forKeys: keySet) else { continue }
                if v.isSymbolicLink == true { continue }
                if v.isDirectory == true {
                    if skipDir(name) || SweepRules.isGeneratedDir(url) { e.skipDescendants() }
                    continue
                }
                if SweepRules.isHidden(name) { continue }
                guard v.isRegularFile == true else { continue }
                let size = Int64(v.fileSize ?? 0)
                // Skip small files, and cloud placeholders (no local data): reading those would
                // trigger a download.
                guard size >= minBytes, (v.totalFileAllocatedSize ?? 0) > 0 else { continue }
                // Hard links are the same file twice, not a duplicate.
                var st = stat()
                if lstat(url.path, &st) == 0 {
                    let key = "\(st.st_dev):\(st.st_ino)"
                    if seenInodes.contains(key) { continue }
                    seenInodes.insert(key)
                }
                out.append(Entry(url: url, size: size, modified: v.contentModificationDate))
            }
            progress.tick(batch)
        }
        return out
    }

    /// Thread-safe sink for the groups found by the parallel hashing pass.
    private final class GroupCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var groups: [[Entry]] = []
        func add(_ g: [[Entry]]) { lock.lock(); groups.append(contentsOf: g); lock.unlock() }
        var all: [[Entry]] { lock.lock(); defer { lock.unlock() }; return groups }
    }

    /// SHA-256 of the first and last 16 KB.
    private static func hashEdges(_ url: URL, size: Int64) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        do {
            let head = try fh.read(upToCount: edge) ?? Data()
            hasher.update(data: head)
            if size > Int64(2 * edge) {
                try fh.seek(toOffset: UInt64(size - Int64(edge)))
                let tail = try fh.read(upToCount: edge) ?? Data()
                hasher.update(data: tail)
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize())
    }

    /// SHA-256 of the whole file, read in 1 MB chunks.
    private static func hashFull(_ url: URL, cancel: ScanProgress) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        do {
            while true {
                if cancel.isCancelled { return nil }
                let chunk: Data = try autoreleasepool { try fh.read(upToCount: 1 << 20) ?? Data() }
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize())
    }

    /// Splits a group into sub-groups whose members share the same hash.
    private static func regroup(_ group: [Entry], hashed: ScanProgress, hash: (Entry) -> Data?) -> [[Entry]] {
        var byHash: [Data: [Entry]] = [:]
        for e in group {
            hashed.tick()
            guard let h = hash(e) else { continue }
            byHash[h, default: []].append(e)
        }
        return byHash.values.filter { $0.count >= 2 }
    }

    static func findDuplicates(roots: [URL], minBytes: Int64, progress: ScanProgress,
                               hashed: ScanProgress) -> [DupGroup] {
        let files = listFiles(roots: roots, minBytes: minBytes, progress: progress)
        if progress.isCancelled { return [] }

        // Pass 1: same size.
        var bySize: [Int64: [Entry]] = [:]
        for f in files { bySize[f.size, default: []].append(f) }
        let candidates: [[Entry]] = bySize.values.filter { $0.count >= 2 }

        // Pass 2: same first/last 16 KB. Pass 3: same full content. Groups hash in parallel.
        let collector = GroupCollector()
        DispatchQueue.concurrentPerform(iterations: candidates.count) { i in
            if progress.isCancelled { return }
            let g = candidates[i]
            let size = g[0].size
            var local: [[Entry]] = []
            for sub in regroup(g, hashed: hashed, hash: { hashEdges($0.url, size: size) }) {
                // The edge hash already covers every byte of files up to 16 KB.
                if size <= Int64(edge) {
                    local.append(sub)
                } else {
                    local.append(contentsOf: regroup(sub, hashed: hashed, hash: { hashFull($0.url, cancel: progress) }))
                }
            }
            if !local.isEmpty { collector.add(local) }
        }
        if progress.isCancelled { return [] }
        let groups = collector.all

        var out: [DupGroup] = groups.map { g in
            let sorted = g.sorted { a, b in
                let da = a.modified ?? Date.distantPast
                let db = b.modified ?? Date.distantPast
                if da != db { return da < db }
                return a.url.path < b.url.path
            }
            let files = sorted.map { DupFile(url: $0.url, modified: $0.modified) }
            return DupGroup(size: sorted[0].size, kind: FileKind.of(sorted[0].url), files: files,
                            id: sorted[0].url.path)
        }
        out.sort { $0.wasted > $1.wasted }
        if out.count > maxGroups { out = Array(out.prefix(maxGroups)) }
        return out
    }
}
