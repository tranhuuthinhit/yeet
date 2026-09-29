import AppKit
import Observation
import SwiftUI

struct TreeRow: Identifiable {
    let node: CacheNode
    let depth: Int
    var id: String { node.id }
}

@Observable
final class AppModel {
    // Scan results per tool
    var items: [ToolKind: [CacheNode]] = [:]
    var scanned: Set<ToolKind> = []

    // UI state
    var selection: ViewSelection = .all
    var expanded: Set<String> = ["xcode", "xcode.dd", "xcode.ds"]
    var checked: Set<String> = []
    var focused: String? = nil
    var phase: Phase = .idle
    var showConfirm = false
    var toast: String? = nil
    var copied = false
    var disk = DiskInfo()
    private(set) var freedTotal: Int64
    /// Tools the user switched off: not scanned, not shown, not counted.
    private(set) var hiddenTools: Set<ToolKind>
    /// Hide tools that turned out to have nothing on this Mac (0 KB after a scan).
    private(set) var autoHideEmpty: Bool

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    private static let freedKey = "freedTotal"

    private static let hiddenKey = "hiddenTools"
    private static let autoHideKey = "autoHideEmptyTools"

    init() {
        freedTotal = Int64(UserDefaults.standard.integer(forKey: Self.freedKey))
        let raw = UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []
        hiddenTools = Set(raw.compactMap(ToolKind.init(rawValue:)))
        autoHideEmpty = UserDefaults.standard.object(forKey: Self.autoHideKey) as? Bool ?? true
    }

    // MARK: - Tool visibility

    /// Tools that are scanned and counted.
    var enabledTools: [ToolKind] { ToolKind.available.filter { !hiddenTools.contains($0) } }

    /// Tools shown in the sidebar / "All" (enabled, minus empty ones when auto-hide is on).
    var visibleTools: [ToolKind] {
        enabledTools.filter { !(autoHideEmpty && isEmptyOnThisMac($0)) }
    }

    /// Scanned and found nothing (tool not installed / never used).
    func isEmptyOnThisMac(_ k: ToolKind) -> Bool {
        scanned.contains(k) && toolNode(k).size == 0
    }

    var autoHiddenTools: [ToolKind] { autoHideEmpty ? enabledTools.filter(isEmptyOnThisMac) : [] }

    @MainActor
    func setHidden(_ k: ToolKind, _ hidden: Bool) {
        if hidden { hiddenTools.insert(k) } else { hiddenTools.remove(k) }
        UserDefaults.standard.set(hiddenTools.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
        if hidden {
            let ids = Set(toolNode(k).leaves.map(\.id))
            checked.subtract(ids)
            if selection == .tool(k) { selection = .all }
        } else if !scanned.contains(k) {
            scanTools([k])
        }
    }

    /// Hides every enabled tool that has nothing on this Mac.
    @MainActor
    func hideAllEmpty() {
        for k in enabledTools where isEmptyOnThisMac(k) { setHidden(k, true) }
    }

    func setAutoHideEmpty(_ on: Bool) {
        autoHideEmpty = on
        UserDefaults.standard.set(on, forKey: Self.autoHideKey)
        if on, case .tool(let k) = selection, isEmptyOnThisMac(k) { selection = .all }
    }

    /// Scans a few tools (e.g. one that was just un-hidden).
    @MainActor
    func scanTools(_ kinds: [ToolKind]) {
        guard phase == .idle, !kinds.isEmpty else { return }
        phase = .scanning
        Task { @MainActor in
            await performScan(Set(kinds))
            phase = .idle
        }
    }

    // MARK: - Derived tree

    func toolNode(_ kind: ToolKind) -> CacheNode {
        CacheNode(id: kind.rawValue, name: kind.name, url: Paths.expand(kind.rootPath), tool: kind,
                  isTool: true, pathOverride: kind.rootPath, children: items[kind] ?? [])
    }

    var toolNodes: [CacheNode] { enabledTools.map(toolNode) }

    /// Pseudo-root holding every tool; used by the header checkbox in "All".
    var rootNode: CacheNode {
        CacheNode(id: "__all", name: L("All", "Tất cả"), url: Paths.home, tool: .xcode, children: toolNodes)
    }

    /// Node that the header checkbox / header total refer to.
    var headNode: CacheNode {
        switch selection {
        case .all, .growth: return rootNode
        case .tool(let k): return toolNode(k)
        }
    }

    var topNodes: [CacheNode] {
        switch selection {
        case .all: return visibleTools.map(toolNode)
        case .growth: return []
        case .tool(let k): return items[k] ?? []
        }
    }

    func rows(hideEmpty: Bool) -> [TreeRow] {
        var out: [TreeRow] = []
        func walk(_ n: CacheNode, _ depth: Int) {
            if hideEmpty && n.size <= 0 { return }
            out.append(TreeRow(node: n, depth: depth))
            if let children = n.children, expanded.contains(n.id) {
                for c in children { walk(c, depth + 1) }
            }
        }
        for n in topNodes { walk(n, 0) }
        return out
    }

    func find(_ id: String?) -> CacheNode? {
        guard let id else { return nil }
        for t in toolNodes {
            if let n = t.find(id) { return n }
        }
        return nil
    }

    var allLeaves: [CacheNode] { toolNodes.flatMap { $0.leaves } }
    var grandTotal: Int64 { toolNodes.reduce(Int64(0)) { $0 + $1.size } }
    var safeTotal: Int64 { allLeaves.filter { $0.risk == .safe }.reduce(Int64(0)) { $0 + $1.leafSize } }
    var selectedLeaves: [CacheNode] { allLeaves.filter { checked.contains($0.id) && $0.leafSize > 0 } }
    var selectedSize: Int64 { selectedLeaves.reduce(Int64(0)) { $0 + $1.leafSize } }
    var isScanComplete: Bool { enabledTools.allSatisfy(scanned.contains) }

    // MARK: - Checking

    func checkState(_ n: CacheNode) -> CheckState {
        let live = n.liveLeaves
        if live.isEmpty { return .disabled }
        let k = live.filter { checked.contains($0.id) }.count
        if k == 0 { return .unchecked }
        return k == live.count ? .checked : .partial
    }

    func toggleCheck(_ n: CacheNode) {
        let state = checkState(n)
        guard state != .disabled else { return }
        var c = checked
        for l in n.liveLeaves {
            if state == .checked { c.remove(l.id) } else { c.insert(l.id) }
        }
        checked = c
    }

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func selectSafe() {
        checked = Set(allLeaves.filter { $0.risk == .safe && $0.leafSize > 0 }.map(\.id))
    }

    // MARK: - Navigation

    func select(_ s: ViewSelection) {
        selection = s
        if case .tool(let k) = s {
            focus(items[k]?.first?.id ?? k.rawValue)
        }
    }

    func focus(_ id: String?) {
        focused = id
        copied = false
    }

    // MARK: - Actions

    func copyPath(_ node: CacheNode) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(node.isGroup && node.pathOverride != nil ? node.path : node.url.path, forType: .string)
        copied = true
    }

    @MainActor
    func reveal(_ node: CacheNode) {
        let fm = FileManager.default
        var target = node.url
        // Walk up to the nearest existing folder.
        while !fm.fileExists(atPath: target.path) && target.path != "/" && target.pathComponents.count > 1 {
            target = target.deletingLastPathComponent()
        }
        if fm.fileExists(atPath: node.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        } else {
            NSWorkspace.shared.open(target)
        }
        showToast(L("Opened \(Paths.tilde(target)) in Finder", "Đã mở \(Paths.tilde(target)) trong Finder"))
    }

    @MainActor
    func showToast(_ message: String, seconds: Double = 3) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func refreshDisk() {
        let root = URL(fileURLWithPath: "/")
        guard let v = try? root.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey]) else { return }
        var info = DiskInfo()
        info.name = v.volumeName ?? "Macintosh HD"
        info.total = Int64(v.volumeTotalCapacity ?? 0)
        info.free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        disk = info
    }

    // MARK: - Scan

    @MainActor
    func rescan(announce: Bool = true) {
        guard phase == .idle else { return }
        phase = .scanning
        Task { @MainActor in
            await performScan(Set(enabledTools))
            phase = .idle
            refreshDisk()
            if announce {
                let n = enabledTools.count
                showToast(L(n == 1 ? "Scanned 1 category" : "Scanned \(n) categories", "Đã quét xong \(n) nhóm"))
            }
        }
    }

    /// Scans tools concurrently and publishes each result as soon as it's ready.
    @MainActor
    private func performScan(_ kinds: Set<ToolKind>) async {
        let roots = GitRoots.load()
        await withTaskGroup(of: (ToolKind, [CacheNode]).self) { group in
            for k in kinds {
                group.addTask(priority: .userInitiated) { (k, Scanner.scan(k, gitRoots: roots)) }
            }
            for await (k, nodes) in group {
                self.items[k] = nodes
                self.scanned.insert(k)
            }
        }
        // Keep focus valid.
        if find(focused) == nil {
            focus(rows(hideEmpty: false).first?.id)
        }
    }

    // MARK: - Clean

    @MainActor
    func requestClean(confirm: Bool) {
        guard !selectedLeaves.isEmpty, phase == .idle else { return }
        if confirm { showConfirm = true } else { startClean() }
    }

    @MainActor
    func startClean() {
        showConfirm = false
        let targets = selectedLeaves
        guard !targets.isEmpty, phase == .idle else { return }
        let affected = Set(targets.map(\.tool))
        let before = affected.reduce(Int64(0)) { $0 + toolNode($1).size }
        let totalBytes = max(1, targets.reduce(Int64(0)) { $0 + $1.leafSize })
        phase = .cleaning(0)

        Task { @MainActor in
            var failures: [String] = []
            var done: Int64 = 0
            for t in targets {
                if let action = t.action {
                    do { try await Cleaner.perform(action) } catch { failures.append(error.localizedDescription) }
                }
                done += t.leafSize
                phase = .cleaning(min(1, Double(done) / Double(totalBytes)))
            }
            await performScan(affected)
            let after = affected.reduce(Int64(0)) { $0 + toolNode($1).size }
            let freed = max(0, before - after)
            addFreed(freed)
            checked.removeAll()
            phase = .idle
            refreshDisk()
            if failures.isEmpty {
                showToast(L("Freed \(Fmt.size(freed))", "Đã dọn \(Fmt.size(freed))"))
            } else {
                let n = failures.count
                showToast(L("Freed \(Fmt.size(freed)) · \(n == 1 ? "1 item" : "\(n) items") failed: \(failures[0])",
                            "Đã dọn \(Fmt.size(freed)) · \(n) mục lỗi: \(failures[0])"), seconds: 6)
                NSLog("Yeet clean failures:\n%@", failures.joined(separator: "\n"))
            }
        }
    }

    private func addFreed(_ bytes: Int64) {
        freedTotal += bytes
        UserDefaults.standard.set(Int(freedTotal), forKey: Self.freedKey)
    }
}
