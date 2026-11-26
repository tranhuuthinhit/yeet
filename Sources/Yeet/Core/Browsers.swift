// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// Browser Cleanup: finds what each Chromium-family browser keeps on this Mac and sorts it into
// three groups, so nothing is removed by surprise:
//  - Caches: page, script and graphics caches the browser rebuilds (deleted, pre-selected),
//  - AI models the browser downloaded, e.g. Chrome's Gemini Nano (moved to the Trash),
//  - Website data: databases, offline files and file storage, listed per website and never
//    pre-selected; web games keep their saves here (moved to the Trash).
// Passwords (Login Data), cookies, history, bookmarks, extensions and Local Storage (where
// sign-ins live) are never listed and can never be removed: `BrowserScanner.allowed` only
// accepts the exact folder kinds above, inside one browser's own folders.

import AppKit
import Foundation
import Observation

enum BrowserGroup: Int, CaseIterable, Sendable {
    case caches, models, siteData

    var title: String {
        switch self {
        case .caches: return L("Caches", "Cache")
        case .models: return L("AI models", "Mô hình AI")
        case .siteData: return L("Website data", "Dữ liệu trang web")
        }
    }

    var description: String {
        switch self {
        case .caches:
            return L("Page, script and graphics caches. The browser rebuilds them as you browse.",
                     "Cache trang, script và đồ hoạ. Trình duyệt sẽ tự tạo lại khi bạn duyệt web.")
        case .models:
            return L("AI models the browser downloaded for on-device features. It may download them again when a feature needs them.",
                     "Mô hình AI trình duyệt đã tải cho các tính năng chạy trên máy. Trình duyệt có thể tải lại khi cần.")
        case .siteData:
            return L("Databases, offline files and files websites keep. Web games keep saves here, so nothing is selected for you.",
                     "Cơ sở dữ liệu, file ngoại tuyến và file các trang web lưu. Game web lưu tiến trình ở đây nên không có mục nào được chọn sẵn.")
        }
    }

    var symbol: String {
        switch self {
        case .caches: return "internaldrive"
        case .models: return "cpu"
        case .siteData: return "globe"
        }
    }

    /// Caches are deleted outright; models and website data go to the Trash.
    var method: CleanMethod { self == .caches ? .delete : .trash }
}

struct BrowserItem: Identifiable, Sendable {
    let id: String
    let group: BrowserGroup
    /// "Gemini Nano", "web.example.com", "Cache"
    let title: String
    /// What it is or what it's made of.
    let detail: String
    /// The profile it belongs to (nil for browser-wide items).
    let profile: String?
    let urls: [URL]
    let size: Int64
    var method: CleanMethod { group.method }
}

struct BrowserInfo: Identifiable, Sendable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let appURL: URL?
    let dataURL: URL
    let cacheURL: URL
    /// Profile names as shown in the browser ("Nihal (Default)").
    let profiles: [String]
    let items: [BrowserItem]
    /// False when the sandbox lets Yeet see the data folder but not list it.
    var readable: Bool = true

    var total: Int64 { items.reduce(Int64(0)) { $0 + $1.size } }

    func items(in group: BrowserGroup) -> [BrowserItem] { items.filter { $0.group == group } }

    func size(of group: BrowserGroup) -> Int64 { items(in: group).reduce(Int64(0)) { $0 + $1.size } }

    var icon: NSImage {
        if let appURL { return AppIconCache.icon(for: appURL) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }
}

/// What one clean did.
struct BrowserCleanOutcome {
    var deleted: Int64 = 0
    var trashed: Int64 = 0
    var failures: [String] = []
    /// Browsers that were open, so nothing of theirs was touched.
    var skipped: [String] = []

    var message: String {
        var parts: [String] = []
        let freed = deleted + trashed
        if freed > 0 { parts.append(L("Freed \(Fmt.size(freed))", "Đã dọn \(Fmt.size(freed))")) }
        if !skipped.isEmpty {
            let names = skipped.joined(separator: ", ")
            parts.append(L("Skipped \(names): quit it first", "Bỏ qua \(names): hãy thoát trước"))
        }
        if !failures.isEmpty {
            parts.append(L("\(failures.count) failed: \(failures[0])", "\(failures.count) mục lỗi: \(failures[0])"))
        }
        if parts.isEmpty { return L("Nothing to clean", "Không có gì để dọn") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Store

@Observable
final class BrowsersStore {
    static let shared = BrowsersStore()

    var browsers: [BrowserInfo] = []
    var scanning = false
    var scanned = false
    /// Ids of ticked items. Caches start ticked, models and website data don't.
    var checked: Set<String> = []
    /// Browser shown on the right.
    var selectedBrowser: String? = nil
    /// Bundle ids of browsers open right now (refreshed on scan and before cleaning).
    var running: Set<String> = []

    var total: Int64 { browsers.reduce(Int64(0)) { $0 + $1.total } }
    var browserCount: Int { browsers.count }

    var allItems: [BrowserItem] { browsers.flatMap(\.items) }
    var selectedItems: [BrowserItem] { allItems.filter { checked.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(Int64(0)) { $0 + $1.size } }

    var current: BrowserInfo? {
        if let id = selectedBrowser, let b = browsers.first(where: { $0.id == id }) { return b }
        return browsers.first
    }

    func isRunning(_ b: BrowserInfo) -> Bool { running.contains(b.bundleID) }

    /// Browsers with at least one ticked item.
    var browsersWithSelection: [BrowserInfo] {
        browsers.filter { b in b.items.contains { checked.contains($0.id) } }
    }

    // MARK: Selection

    func toggle(_ item: BrowserItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    }

    func state(_ items: [BrowserItem]) -> CheckState {
        if items.isEmpty { return .disabled }
        let n = items.filter { checked.contains($0.id) }.count
        if n == 0 { return .unchecked }
        return n == items.count ? .checked : .partial
    }

    func toggleAll(_ items: [BrowserItem]) {
        let ids = Set(items.map(\.id))
        if state(items) == .checked { checked.subtract(ids) } else { checked.formUnion(ids) }
    }

    // MARK: Scan

    @MainActor
    func refreshRunning() {
        running = FileOps.runningBundleIDs()
    }

    @MainActor
    func scan() {
        guard !scanning else { return }
        scanning = true
        refreshRunning()
        Task { @MainActor in
            let found: [BrowserInfo] = await Task.detached(priority: .userInitiated) {
                BrowserScanner.scan()
            }.value
            let oldIDs = Set(self.browsers.flatMap { $0.items.map(\.id) })
            var sel = self.checked
            for b in found {
                for i in b.items where i.group == .caches && !oldIDs.contains(i.id) { sel.insert(i.id) }
            }
            let ids = Set(found.flatMap { $0.items.map(\.id) })
            self.checked = sel.intersection(ids)
            self.browsers = found
            if let s = self.selectedBrowser, !found.contains(where: { $0.id == s }) { self.selectedBrowser = nil }
            self.scanning = false
            self.scanned = true
        }
    }

    // MARK: Clean

    /// Cleans the ticked items, browser by browser. A browser that is open is skipped entirely:
    /// it could be writing those files right now. Caches are deleted, the rest goes to the Trash.
    @MainActor
    @discardableResult
    func clean() -> BrowserCleanOutcome {
        var out = BrowserCleanOutcome()
        refreshRunning()
        var done: Set<String> = []
        for b in browsers {
            let picked = b.items.filter { checked.contains($0.id) }
            if picked.isEmpty { continue }
            if running.contains(b.bundleID) {
                out.skipped.append(b.name)
                continue
            }
            var toTrash: [BrowserItem] = []
            for item in picked {
                guard item.urls.allSatisfy({ BrowserScanner.allowed($0, data: b.dataURL, cache: b.cacheURL) }) else {
                    out.failures.append(L("Refused: \(item.title)", "Từ chối: \(item.title)"))
                    continue
                }
                if item.group == .caches {
                    var ok = true
                    for url in item.urls {
                        do {
                            try Cleaner.remove(url, contentsOnly: true)
                        } catch {
                            ok = false
                            out.failures.append(error.localizedDescription)
                        }
                    }
                    if ok {
                        out.deleted += item.size
                        done.insert(item.id)
                    }
                } else {
                    toTrash.append(item)
                }
            }
            for item in toTrash {
                let result = FileOps.moveToTrash(item.urls)
                let fm = FileManager.default
                let gone = item.urls.allSatisfy { !fm.fileExists(atPath: $0.path) }
                if gone {
                    out.trashed += item.size
                    done.insert(item.id)
                } else {
                    out.failures.append(result.failures.first ?? L("Couldn't move \(item.title)", "Không chuyển được \(item.title)"))
                }
            }
        }
        checked.subtract(done)
        if !out.failures.isEmpty {
            NSLog("Yeet browser clean failures:\n%@", out.failures.joined(separator: "\n"))
        }
        scan()
        return out
    }
}

// MARK: - Scanner (runs off the main thread)

enum BrowserScanner {
    /// Browsers built on Chromium, which all lay their files out the same way.
    /// (name, bundle id, app, data folder, cache folder) — folders relative to ~/Library.
    static let chromium: [(String, String, String, String, String)] = [
        ("Chrome", "com.google.Chrome", "Google Chrome.app", "Application Support/Google/Chrome", "Caches/Google/Chrome"),
        ("Chrome Beta", "com.google.Chrome.beta", "Google Chrome Beta.app", "Application Support/Google/Chrome Beta", "Caches/Google/Chrome Beta"),
        ("Chrome Canary", "com.google.Chrome.canary", "Google Chrome Canary.app", "Application Support/Google/Chrome Canary", "Caches/Google/Chrome Canary"),
        ("Brave", "com.brave.Browser", "Brave Browser.app", "Application Support/BraveSoftware/Brave-Browser", "Caches/BraveSoftware/Brave-Browser"),
        ("Edge", "com.microsoft.edgemac", "Microsoft Edge.app", "Application Support/Microsoft Edge", "Caches/Microsoft Edge"),
        ("Arc", "company.thebrowser.Browser", "Arc.app", "Application Support/Arc/User Data", "Caches/Arc/User Data"),
        ("Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi.app", "Application Support/Vivaldi", "Caches/Vivaldi"),
        ("Opera", "com.operasoftware.Opera", "Opera.app", "Application Support/com.operasoftware.Opera", "Caches/com.operasoftware.Opera"),
        ("Opera GX", "com.operasoftware.OperaGX", "Opera GX.app", "Application Support/com.operasoftware.OperaGX", "Caches/com.operasoftware.OperaGX"),
        ("Chromium", "org.chromium.Chromium", "Chromium.app", "Application Support/Chromium", "Caches/Chromium"),
    ]

    /// AI model folders browsers keep next to their profiles: (folder, name, what it does).
    static var models: [(String, String, String)] {
        [
            ("OptGuideOnDeviceModel", L("Gemini Nano", "Gemini Nano"),
             L("Google's on-device language model, used for Help me write, page summaries and tab organising.",
               "Mô hình ngôn ngữ chạy trên máy của Google, dùng cho Help me write, tóm tắt trang và sắp xếp tab.")),
            ("OptGuideOnDeviceClassifierModel", L("Scam detection model", "Mô hình phát hiện lừa đảo"),
             L("A small model that checks pages for scams and phishing. Removing it may weaken those warnings.",
               "Mô hình nhỏ kiểm tra trang lừa đảo và giả mạo. Xoá nó có thể làm các cảnh báo này yếu đi.")),
            ("optimization_guide_model_store", L("Small feature models", "Mô hình tính năng nhỏ"),
             L("Small models individual browser features download, such as tab grouping and form filling.",
               "Các mô hình nhỏ do từng tính năng tải về, như nhóm tab và điền biểu mẫu.")),
            ("OnDeviceHeadSuggestModel", L("Address bar suggestions", "Gợi ý thanh địa chỉ"),
             L("Suggests searches as you type in the address bar.", "Gợi ý tìm kiếm khi bạn gõ vào thanh địa chỉ.")),
            ("screen_ai", L("Screen AI", "Screen AI"),
             L("Reads text in images and PDFs, for accessibility.", "Đọc chữ trong ảnh và PDF, phục vụ trợ năng.")),
            ("SODA", L("Live Caption", "Phụ đề trực tiếp"),
             L("Speech recognition for Live Caption.", "Nhận dạng giọng nói cho Phụ đề trực tiếp.")),
            ("SODALanguagePacks", L("Live Caption languages", "Ngôn ngữ Phụ đề trực tiếp"),
             L("Language packs for Live Caption.", "Gói ngôn ngữ cho Phụ đề trực tiếp.")),
        ]
    }

    static let modelFolders: Set<String> = [
        "OptGuideOnDeviceModel", "OptGuideOnDeviceClassifierModel", "optimization_guide_model_store",
        "OnDeviceHeadSuggestModel", "screen_ai", "SODA", "SODALanguagePacks",
    ]

    /// Profiles the browser uses internally; never listed or touched.
    static let hiddenProfiles: Set<String> = ["System Profile", "Guest Profile"]
    /// Graphics caches shared by all profiles.
    static let sharedJunk: [String] = ["GrShaderCache", "ShaderCache", "GraphiteDawnCache"]
    /// Caches inside a profile (in the data folder or ~/Library/Caches).
    static let profileJunk: [String] = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"]

    // MARK: File helpers

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func isSymlink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink ?? false
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    static func isFile(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && !dir.boolValue
    }

    static func size(_ url: URL) -> Int64 { Scanner.stats(url).size }

    // MARK: Names

    /// "https_www.facebook.com_0" → "www.facebook.com"; nil for anything that isn't a website
    /// (extensions, chrome:// pages, local files).
    static func originHost(_ id: String) -> String? {
        guard let us = id.firstIndex(of: "_") else { return nil }
        let scheme = String(id[id.startIndex..<us])
        guard scheme == "https" || scheme == "http" else { return nil }
        let rest = String(id[id.index(after: us)...])
        guard let last = rest.lastIndex(of: "_") else { return nil }
        let host = String(rest[rest.startIndex..<last])
        let port = String(rest[rest.index(after: last)...])
        guard !host.isEmpty else { return nil }
        return port == "0" ? host : "\(host):\(port)"
    }

    /// "https://web.example.com/" → "web.example.com"
    static func urlHost(_ url: String) -> String? {
        let rest: Substring
        if url.hasPrefix("https://") { rest = url.dropFirst(8) }
        else if url.hasPrefix("http://") { rest = url.dropFirst(7) }
        else { return nil }
        let host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return host.isEmpty ? nil : String(host)
    }

    /// The website a Service Worker cache folder belongs to. Chrome names the folder by a hash
    /// and writes the site's address into its index.txt, a protocol buffer: the first web
    /// address in it is the site that owns it.
    static func cacheStorageOwner(_ data: Data) -> String? {
        let buf: [UInt8] = [UInt8](data)
        var pos = 0

        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard pos < buf.count else { return nil }
                let b = buf[pos]
                pos += 1
                value |= UInt64(b & 0x7F) << shift
                if b < 0x80 { return value }
                shift += 7
                if shift > 63 { return nil }
            }
        }

        while pos < buf.count {
            guard let key = varint() else { return nil }
            switch key & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1:
                pos += 8
            case 5:
                pos += 4
            case 2:
                guard let len64 = varint(), len64 <= UInt64(buf.count) else { return nil }
                let len = Int(len64)
                guard pos + len <= buf.count else { return nil }
                let slice = Array(buf[pos..<(pos + len)])
                pos += len
                if let text = String(bytes: slice, encoding: .utf8),
                   let host = urlHost(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return host
                }
            default:
                return nil
            }
        }
        return nil
    }

    /// Profile folder names with the names you gave them, from the browser's "Local State".
    static func profileNames(_ data: URL) -> [String: String] {
        guard let raw = try? Data(contentsOf: data.appendingPathComponent("Local State")),
              let json = try? JSONSerialization.jsonObject(with: raw, options: []),
              let root = json as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (dir, value) in cache {
            if let d = value as? [String: Any], let name = d["name"] as? String { out[dir] = name }
        }
        return out
    }

    /// Profile folders: those with a Preferences file, except the browser's own hidden ones.
    /// Opera keeps its only profile in the data folder itself, returned as "".
    static func profileDirs(_ data: URL) -> [String] {
        var v: [String] = children(data)
            .filter { isFile($0.appendingPathComponent("Preferences")) }
            .map { $0.lastPathComponent }
            .filter { !hiddenProfiles.contains($0) }
        if isFile(data.appendingPathComponent("Preferences")) { v.append("") }
        // Default first, then "Profile 2", "Profile 10"… in number order.
        func rank(_ n: String) -> (Int, Int, String) {
            let num: Int = n.hasPrefix("Profile ") ? (Int(n.dropFirst(8)) ?? Int.max) : Int.max
            return (n == "Default" ? 0 : 1, num, n)
        }
        return v.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra.0 != rb.0 { return ra.0 < rb.0 }
            if ra.1 != rb.1 { return ra.1 < rb.1 }
            return ra.2 < rb.2
        }
    }

    /// Does this folder hold a model file (one Yeet doesn't know by name)?
    static func holdsModelFile(_ dir: URL) -> Bool {
        if isFile(dir.appendingPathComponent("weights.bin")) { return true }
        return children(dir).contains { isFile($0.appendingPathComponent("weights.bin")) }
    }

    /// "2026.2.12.1554" — the newest version folder inside a model folder.
    static func modelVersion(_ dir: URL) -> String? {
        let names = children(dir).filter { isDirectory($0) }.map { $0.lastPathComponent }
            .filter { n in n.contains(".") && n.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } }
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        return names.max { a, b in parts(a).lexicographicallyPrecedes(parts(b)) }
    }

    /// "pages 120 MB · compiled scripts 40 MB"
    static func breakdown(_ parts: [(String, Int64)]) -> String {
        var by: [String: Int64] = [:]
        for (k, s) in parts { by[k, default: 0] += s }
        return by.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { "\($0.key) \(Fmt.size($0.value))" }
            .joined(separator: " · ")
    }

    // MARK: Scan

    /// Every Chromium browser that has a data folder on this Mac.
    static func scan() -> [BrowserInfo] {
        let lib = Paths.home.appendingPathComponent("Library", isDirectory: true)
        var out: [BrowserInfo] = []
        for (name, id, app, d, c) in chromium {
            let data = lib.appendingPathComponent(d, isDirectory: true)
            guard isDirectory(data) else { continue }
            let cache = lib.appendingPathComponent(c, isDirectory: true)
            let b = scanBrowser(name: name, bundleID: id, app: findApp(id, app), data: data, cache: cache)
            // A data folder left behind by an uninstalled browser, with nothing in it: don't list it.
            if b.appURL == nil && b.items.isEmpty && b.readable { continue }
            out.append(b)
        }
        return out
    }

    static func findApp(_ bundleID: String, _ app: String) -> URL? {
        let usual = [URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(app),
                     Paths.home.appendingPathComponent("Applications", isDirectory: true).appendingPathComponent(app)]
        if let p = usual.first(where: { isDirectory($0) }) { return p }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func scanBrowser(name: String, bundleID: String, app: URL?, data: URL, cache: URL) -> BrowserInfo {
        var items: [BrowserItem] = []

        // AI models (browser-wide).
        let known = models
        for e in children(data) {
            guard isDirectory(e), !isSymlink(e) else { continue }
            let folder = e.lastPathComponent
            let k = known.first { $0.0 == folder }
            // A profile folder is never a model folder.
            if isFile(e.appendingPathComponent("Preferences")) { continue }
            if k == nil && !holdsModelFile(e) { continue }
            let s = size(e)
            if s < 1_048_576 { continue }   // an empty placeholder, like OptGuideOnDeviceModel before a download
            let title = k?.1 ?? folder
            let what = k?.2 ?? L("Holds an AI model file (weights.bin) that Yeet doesn't know by name.",
                                 "Chứa file mô hình AI (weights.bin) mà Yeet không biết tên.")
            let version = modelVersion(e).map { L(" Version \($0).", " Phiên bản \($0).") } ?? ""
            items.append(BrowserItem(id: e.path, group: .models, title: title,
                                     detail: "\(what)\(version) \(L("Folder", "Thư mục")): \(folder)",
                                     profile: nil, urls: [e], size: s))
        }

        // Graphics caches shared by all profiles.
        var shared: [URL] = []
        var sharedSize: Int64 = 0
        for j in sharedJunk {
            let p = data.appendingPathComponent(j, isDirectory: true)
            if isDirectory(p) && !isSymlink(p) {
                shared.append(p)
                sharedSize += size(p)
            }
        }
        if sharedSize > 0 {
            items.append(BrowserItem(id: bundleID + "#shared-graphics", group: .caches,
                                     title: L("Graphics cache", "Cache đồ hoạ"),
                                     detail: L("Shared by all profiles", "Dùng chung cho mọi hồ sơ"),
                                     profile: nil, urls: shared, size: sharedSize))
        }

        let names = profileNames(data)
        let dirs = profileDirs(data)
        var labels: [String] = []
        for d in dirs {
            let label: String
            if let n = names[d] {
                label = (!d.isEmpty && n != d) ? "\(n) (\(d))" : n
            } else {
                label = d.isEmpty ? name : d
            }
            labels.append(label)
            items.append(contentsOf: scanProfile(data: data, cache: cache, dir: d, label: label, bundleID: bundleID))
        }

        items.sort { a, b in
            if a.group != b.group { return a.group.rawValue < b.group.rawValue }
            return a.size > b.size
        }
        let readable = (try? FileManager.default.contentsOfDirectory(atPath: data.path)) != nil
        return BrowserInfo(name: name, bundleID: bundleID, appURL: app, dataURL: data, cacheURL: cache,
                           profiles: labels, items: items, readable: readable)
    }

    /// Everything one profile holds that Yeet can list.
    static func scanProfile(data: URL, cache: URL, dir: String, label: String, bundleID: String) -> [BrowserItem] {
        let p = dir.isEmpty ? data : data.appendingPathComponent(dir, isDirectory: true)
        let cacheRoot = dir.isEmpty ? cache : cache.appendingPathComponent(dir, isDirectory: true)
        var items: [BrowserItem] = []

        // Cache, in the data folder and in ~/Library/Caches.
        var cacheParts: [(String, Int64)] = []
        var cacheURLs: [URL] = []
        for root in [p, cacheRoot] {
            for j in profileJunk {
                let path = root.appendingPathComponent(j, isDirectory: true)
                guard isDirectory(path), !isSymlink(path) else { continue }
                let kind: String
                switch j {
                case "Cache": kind = L("pages", "trang")
                case "Code Cache": kind = L("compiled scripts", "script đã biên dịch")
                default: kind = L("graphics", "đồ hoạ")
                }
                cacheParts.append((kind, size(path)))
                cacheURLs.append(path)
            }
        }
        let cacheSize = cacheParts.reduce(Int64(0)) { $0 + $1.1 }
        if cacheSize > 0 {
            items.append(BrowserItem(id: bundleID + "#cache#" + dir, group: .caches, title: L("Cache", "Cache"),
                                     detail: breakdown(cacheParts), profile: label, urls: cacheURLs, size: cacheSize))
        }

        // Website data, collected per website.
        var parts: [(host: String, kind: String, url: URL)] = []
        for e in children(p.appendingPathComponent("IndexedDB", isDirectory: true)) {
            let n = e.lastPathComponent
            var id: String? = nil
            if n.hasSuffix(".indexeddb.leveldb") { id = String(n.dropLast(".indexeddb.leveldb".count)) }
            else if n.hasSuffix(".indexeddb.blob") { id = String(n.dropLast(".indexeddb.blob".count)) }
            if let id, let host = originHost(id), !isSymlink(e) {
                parts.append((host, L("databases", "cơ sở dữ liệu"), e))
            }
        }
        for e in children(p.appendingPathComponent("Service Worker/CacheStorage", isDirectory: true)) {
            let n = e.lastPathComponent
            guard isHexHash(n), !isSymlink(e) else { continue }
            var owner = ""
            if let raw = try? Data(contentsOf: e.appendingPathComponent("index.txt")),
               let host = cacheStorageOwner(raw) {
                owner = host
            }
            parts.append((owner, L("offline files", "file ngoại tuyến"), e))
        }
        // "File System/000": the owner is in a LevelDB index Yeet doesn't read, so these are unnamed.
        for e in children(p.appendingPathComponent("File System", isDirectory: true)) {
            let n = e.lastPathComponent
            if n.count == 3 && n.allSatisfy({ $0.isASCII && $0.isNumber }) && !isSymlink(e) {
                parts.append(("", L("files", "file"), e))
            }
        }

        var order: [String] = []
        var kinds: [String: [(String, Int64)]] = [:]
        var urls: [String: [URL]] = [:]
        for part in parts {
            let s = size(part.url)
            if s == 0 { continue }
            if kinds[part.host] == nil { order.append(part.host) }
            kinds[part.host, default: []].append((part.kind, s))
            urls[part.host, default: []].append(part.url)
        }
        for host in order.sorted() {
            let k = kinds[host] ?? []
            let unknown = host.isEmpty
            let total = k.reduce(Int64(0)) { $0 + $1.1 }
            let title = unknown ? L("Websites Yeet couldn't name", "Trang web Yeet không xác định được") : host
            let detail = unknown
                ? breakdown(k) + L(" · the browser didn't record which site owns these", " · trình duyệt không ghi lại trang nào sở hữu chúng")
                : breakdown(k)
            items.append(BrowserItem(id: bundleID + "#site#" + dir + "#" + host, group: .siteData, title: title,
                                     detail: detail, profile: label, urls: urls[host] ?? [], size: total))
        }
        return items
    }

    static func isHexHash(_ s: String) -> Bool {
        s.count == 40 && s.allSatisfy { $0.isHexDigit && $0.isASCII }
    }

    // MARK: Safety net

    /// True only for the exact kinds of folder this feature lists, inside one browser's own
    /// folders. Anything else — passwords, cookies, history, bookmarks, Local Storage,
    /// extensions, the profile itself — is refused, whatever the scan returned.
    static func allowed(_ url: URL, data: URL, cache: URL) -> Bool {
        let raw = url.path
        let rawParts = raw.split(separator: "/", omittingEmptySubsequences: true)
        if !raw.hasPrefix("/") || rawParts.contains(where: { $0 == "." || $0 == ".." }) { return false }
        if isSymlink(url) { return false }

        func check(_ root: URL, inData: Bool) -> Bool {
            let rootPath = root.standardizedFileURL.path
            guard raw.hasPrefix(rootPath + "/") else { return false }
            let rel = String(raw.dropFirst(rootPath.count + 1))
            let parts: [String] = rel.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !parts.isEmpty else { return false }

            // Browser-wide folders.
            if inData && parts.count == 1 {
                let one = parts[0]
                let isProfile = isFile(data.appendingPathComponent(one).appendingPathComponent("Preferences"))
                let model = modelFolders.contains(one) || (!isProfile && holdsModelFile(url))
                if sharedJunk.contains(one) || (model && !isProfile) { return true }
            }

            // Inside a profile: "Default/…", or the data folder itself for Opera.
            let first = parts[0]
            let rest: [String]
            if hiddenProfiles.contains(first) { return false }
            if isFile(data.appendingPathComponent(first).appendingPathComponent("Preferences")) {
                rest = Array(parts.dropFirst())
            } else if isFile(data.appendingPathComponent("Preferences")) {
                rest = parts
            } else {
                return false
            }

            if rest.count == 1 { return profileJunk.contains(rest[0]) }
            if inData && rest.count == 2 && rest[0] == "IndexedDB" {
                let n = rest[1]
                var id: String? = nil
                if n.hasSuffix(".indexeddb.leveldb") { id = String(n.dropLast(".indexeddb.leveldb".count)) }
                else if n.hasSuffix(".indexeddb.blob") { id = String(n.dropLast(".indexeddb.blob".count)) }
                return id.flatMap { originHost($0) } != nil
            }
            if inData && rest.count == 3 && rest[0] == "Service Worker" && rest[1] == "CacheStorage" {
                return isHexHash(rest[2])
            }
            if inData && rest.count == 2 && rest[0] == "File System" {
                let d = rest[1]
                return d.count == 3 && d.allSatisfy { $0.isASCII && $0.isNumber }
            }
            return false
        }
        return check(data, inData: true) || check(cache, inData: false)
    }
}


/// Extra folders the user granted from the Browsers screen (a browser's data folder that the
/// Home grant alone doesn't open). Each is kept as an app-scoped security-scoped bookmark.
enum BrowserAccess {
    private static let key = "browserFolderBookmarks"
    private static var active: [URL] = []

    /// Call once at launch.
    static func restore() {
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        var keep: [String: Data] = [:]
        for (path, data) in saved {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            active.append(url)
            keep[path] = stale ? (bookmark(url) ?? data) : data
        }
        UserDefaults.standard.set(keep, forKey: key)
    }

    /// Asks the user to choose `folder` in an open panel. Returns true when access was granted.
    @MainActor
    static func request(_ folder: URL, name: String) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = folder.deletingLastPathComponent()
        panel.prompt = L("Allow", "Cho phép")
        panel.message = L("Select the “\(folder.lastPathComponent)” folder so Yeet can read \(name)’s caches.",
                          "Chọn thư mục “\(folder.lastPathComponent)” để Yeet đọc được cache của \(name).")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        _ = url.startAccessingSecurityScopedResource()
        active.append(url)
        var saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        if let data = bookmark(url) { saved[url.path] = data }
        UserDefaults.standard.set(saved, forKey: key)
        return true
    }

    private static func bookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
