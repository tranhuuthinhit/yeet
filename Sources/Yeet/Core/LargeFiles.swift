// Logic ported from MacSweep (https://github.com/nihal4/macsweep), MIT License, Copyright (c) 2026 S. M. Nihal Ahmed.
//
// Large & old files in the Home folder, grouped by kind. Never lists ~/Library (app data, browser
// profiles, Mail, iCloud Drive), hidden folders (the Trash, .git, tool caches), packages such as apps
// and Photos or Music libraries, or files that live only in iCloud/Dropbox (no local data).

import CoreServices
import Foundation
import Observation
import SwiftUI

// MARK: - File kinds

enum FileKind: String, CaseIterable, Identifiable, Hashable {
    case video, archive, installer, model, audio, image, document, other

    var id: String { rawValue }

    static func of(_ url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv", "flv":
            return .video
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst":
            return .archive
        case "dmg", "iso", "pkg", "img", "ipa", "xip", "app":
            return .installer
        case "pt", "pth", "ckpt", "safetensors", "onnx", "h5", "npy", "npz", "parquet", "gguf", "bin", "tflite",
             "pkl", "db", "sqlite":
            return .model
        case "mp3", "wav", "flac", "aac", "m4a", "aiff", "ogg":
            return .audio
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "raw", "cr2", "nef", "arw", "gif", "webp":
            return .image
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers", "epub", "txt", "csv",
             "json":
            return .document
        default:
            return .other
        }
    }

    /// Plural label used in the filter panel ("Videos").
    var title: String {
        switch self {
        case .video: return L("Videos", "Video")
        case .archive: return L("Archives", "File nén")
        case .installer: return L("Disk Images", "Ảnh đĩa & bộ cài")
        case .model: return L("Models & Data", "Mô hình & dữ liệu")
        case .audio: return L("Audio", "Âm thanh")
        case .image: return L("Images", "Hình ảnh")
        case .document: return L("Documents", "Tài liệu")
        case .other: return L("Other", "Khác")
        }
    }

    /// Singular label used in table rows ("Video").
    var label: String {
        switch self {
        case .video: return L("Video", "Video")
        case .archive: return L("Archive", "File nén")
        case .installer: return L("Disk image", "Ảnh đĩa")
        case .model: return L("Data", "Dữ liệu")
        case .audio: return L("Audio", "Âm thanh")
        case .image: return L("Image", "Hình ảnh")
        case .document: return L("Document", "Tài liệu")
        case .other: return L("Other", "Khác")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film.fill"
        case .archive: return "doc.zipper"
        case .installer: return "opticaldiscdrive.fill"
        case .model: return "cpu.fill"
        case .audio: return "music.note"
        case .image: return "photo.fill"
        case .document: return "doc.text.fill"
        case .other: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return Color(hex: 0xE24A6A)
        case .archive: return Color(hex: 0xC98A2A)
        case .installer: return Color(hex: 0x6A6FE0)
        case .model: return Color(hex: 0xD96C2B)
        case .audio: return Color(hex: 0x2FB57C)
        case .image: return Color(hex: 0x2B9CC4)
        case .document: return Color(hex: 0x4F86E8)
        case .other: return Color(hex: 0x7D7D8C)
        }
    }
}

// MARK: - Shared skip rules (used by Large Files and Duplicates)

enum SweepRules {
    /// Folders that are really packages (libraries, bundles, projects). Their insides are not the
    /// user's loose files; touching them corrupts the package.
    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "lrdata", "xcodeproj", "xcworkspace",
        "bundle", "framework", "plugin", "kext", "dsym", "pkg", "mpkg",
    ]

    /// Developer / system folders where duplicate files are normal and must not be removed.
    static let devDirs: Set<String> = [
        "node_modules", "__pycache__", "site-packages", "venv", "Pods", "DerivedData", "Library", "Applications",
    ]

    /// True for bundles like "Photos Library.photoslibrary" or "Foo.app".
    static func isPackage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && packageExtensions.contains(ext)
    }

    static func isHidden(_ name: String) -> Bool { name.hasPrefix(".") }

    /// Build and cache folders mark themselves with a standard file: Rust `target` and other tools
    /// write CACHEDIR.TAG, Python virtual environments have pyvenv.cfg.
    static func isGeneratedDir(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("CACHEDIR.TAG").path)
            || fm.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path)
    }

    /// Resource keys prefetched by both walkers.
    static let walkKeys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .contentModificationDateKey, .contentAccessDateKey,
    ]

    /// Fresh size + modification date straight from the file system (no URL resource cache).
    static func currentState(_ url: URL) -> (size: Int64, modified: Date?)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
        let modified = attrs[.modificationDate] as? Date
        return (size, modified)
    }

    static func sameDate(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x.timeIntervalSince(y)) < 1
        default: return false
        }
    }

    /// Spotlight's "Last opened" (kMDItemLastUsedDate), like Finder shows.
    static func spotlightLastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        guard let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else { return nil }
        return value as? Date
    }
}

// MARK: - Model

struct LargeFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    /// Spotlight "last opened", else the access date, else the modification date.
    let lastUsed: Date?
    let kind: FileKind

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    /// Folder the file lives in, in `~/…` form.
    var location: String { Paths.tilde(url.deletingLastPathComponent()) }

    /// Not opened in over a year (shown in the warning colour).
    var isOld: Bool { LargeFilesStore.age(of: lastUsed) > 365 * 86_400 }
}

enum AgeFilter: String, CaseIterable, Identifiable {
    case any, sixMonths, oneYear
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return L("Any time", "Bất kỳ")
        case .sixMonths: return L("Over 6 months", "Hơn 6 tháng")
        case .oneYear: return L("Over a year", "Hơn 1 năm")
        }
    }

    /// Minimum age in seconds.
    var seconds: TimeInterval {
        switch self {
        case .any: return 0
        case .sixMonths: return 182 * 86_400
        case .oneYear: return 365 * 86_400
        }
    }
}

enum LargeSort: String, CaseIterable, Identifiable {
    case size, oldest, name
    var id: String { rawValue }
}

// MARK: - Store

@Observable
final class LargeFilesStore {
    static let shared = LargeFilesStore()

    /// Minimum size choices (base-1000 like Finder).
    static let sizeOptions: [Int64] = [50_000_000, 100_000_000, 500_000_000, 1_000_000_000]
    /// Most files kept in the list (the largest ones).
    static let maxResults = 2_000

    var files: [LargeFile] = []
    var scanning = false
    var scanned = false
    var trashing = false
    /// The last scan was stopped early, so the results are incomplete.
    var partial = false
    /// Files and folders visited by the running scan.
    var progress = 0
    /// Smallest file shown. Lowering it below `scannedMinSize` triggers a new scan.
    var minSize: Int64 = 100_000_000
    var kindFilter: Set<FileKind> = Set(FileKind.allCases)
    var ageFilter: AgeFilter = .any
    var sort: LargeSort = .size
    /// Paths of the ticked files.
    var checked: Set<String> = []
    /// Row the user clicked last (Quick Look / reveal target).
    var focused: String? = nil
    /// Sum of every file the last scan found (including files beyond the list cap).
    private(set) var total: Int64 = 0
    /// Number of files the last scan found (including files beyond the list cap).
    private(set) var foundCount = 0
    /// Minimum size the current results were scanned with.
    private(set) var scannedMinSize: Int64 = 100_000_000

    @ObservationIgnored private var job: ScanProgress? = nil

    // MARK: Derived

    /// Files passing the kind / age / size filters, in the chosen order.
    var visible: [LargeFile] {
        let now = Date()
        let minAge = ageFilter.seconds
        let filtered = files.filter { f in
            guard f.size >= minSize, kindFilter.contains(f.kind) else { return false }
            if minAge > 0 {
                guard let d = f.lastUsed, now.timeIntervalSince(d) > minAge else { return false }
            }
            return true
        }
        switch sort {
        case .size:
            return filtered.sorted { $0.size > $1.size }
        case .oldest:
            // Unknown dates last.
            return filtered.sorted { a, b in
                (a.lastUsed ?? Date.distantFuture) < (b.lastUsed ?? Date.distantFuture)
            }
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var visibleSize: Int64 { visible.reduce(0) { $0 + $1.size } }

    var selectedFiles: [LargeFile] { files.filter { checked.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    /// Ticked files the current filters hide (they would otherwise be removed unseen).
    var hiddenSelectionCount: Int {
        let shown = Set(visible.map(\.id))
        return checked.filter { !shown.contains($0) }.count
    }

    /// (count, bytes) per kind among files at least `minSize` large.
    func stats(for kind: FileKind) -> (count: Int, size: Int64) {
        var n = 0
        var s: Int64 = 0
        for f in files where f.kind == kind && f.size >= minSize {
            n += 1
            s += f.size
        }
        return (n, s)
    }

    static func age(of date: Date?) -> TimeInterval {
        guard let date else { return 0 }
        return Date().timeIntervalSince(date)
    }

    static func sizeLabel(_ bytes: Int64) -> String {
        bytes >= 1_000_000_000 ? "\(bytes / 1_000_000_000) GB" : "\(bytes / 1_000_000) MB"
    }

    // MARK: Actions

    func toggle(_ file: LargeFile) {
        if checked.contains(file.id) { checked.remove(file.id) } else { checked.insert(file.id) }
    }

    func toggleKind(_ kind: FileKind) {
        if kindFilter.contains(kind) { kindFilter.remove(kind) } else { kindFilter.insert(kind) }
    }

    /// Changes the size threshold; rescans when the new one is below what was scanned.
    func setMinSize(_ bytes: Int64) {
        minSize = bytes
        if scanned && !scanning && bytes < scannedMinSize { scan() }
    }

    func cancel() {
        job?.cancel()
        if scanning { partial = true }
    }

    func scan() {
        guard !scanning else { return }
        job?.cancel()
        let p = ScanProgress()
        job = p
        scanning = true
        partial = false
        progress = 0
        let min = minSize
        let home = Paths.home

        // Publish the visited counter while the walk runs.
        Task { @MainActor [weak self] in
            while let self, self.scanning, self.job === p {
                self.progress = p.count
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (files: [LargeFile], total: Int64, count: Int) in
                LargeFilesStore.walk(root: home, minBytes: min, progress: p)
            }.value
            guard let self, self.job === p else { return }
            let cancelled = p.isCancelled
            self.files = result.files
            self.total = result.total
            self.foundCount = result.count
            self.scannedMinSize = min
            self.progress = p.count
            let ids = Set(result.files.map(\.id))
            self.checked = self.checked.filter { ids.contains($0) }
            if let f = self.focused, !ids.contains(f) { self.focused = nil }
            self.partial = cancelled
            self.scanning = false
            self.scanned = true
            self.job = nil
        }
    }

    /// Moves the ticked files to the Trash, then drops the rows that are gone.
    @MainActor
    @discardableResult
    func trashSelected() async -> FileOps.Outcome {
        let targets = selectedFiles
        guard !targets.isEmpty, !trashing else { return FileOps.Outcome() }
        trashing = true
        var sizes: [URL: Int64] = [:]
        for f in targets { sizes[f.url] = f.size }
        let urls = targets.map(\.url)
        let outcome = await Task.detached(priority: .userInitiated) { () -> FileOps.Outcome in
            FileOps.moveToTrash(urls, sizes: sizes)
        }.value
        let fm = FileManager.default
        let gone = files.filter { !fm.fileExists(atPath: $0.url.path) }
        let goneIDs = Set(gone.map(\.id))
        let freed = gone.reduce(Int64(0)) { $0 + $1.size }
        files.removeAll { goneIDs.contains($0.id) }
        checked.subtract(goneIDs)
        if let f = focused, goneIDs.contains(f) { focused = nil }
        total = max(0, total - freed)
        foundCount = max(0, foundCount - gone.count)
        trashing = false
        return outcome
    }

    // MARK: Engine (background)

    /// Lists big files under `root`, skipping ~/Library, hidden folders, packages and cloud-only files.
    static func walk(root: URL, minBytes: Int64, progress: ScanProgress) -> (files: [LargeFile], total: Int64, count: Int) {
        let fm = FileManager.default
        let keys = SweepRules.walkKeys
        let keySet = Set(keys)
        let rootPath = root.standardizedFileURL.path
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                    options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return ([], 0, 0) }

        struct Found {
            let url: URL
            let size: Int64
            let access: Date?
            let modified: Date?
        }
        var found: [Found] = []
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
                let isHomeLibrary = name == "Library"
                    && (e.level <= 1 || url.deletingLastPathComponent().standardizedFileURL.path == rootPath)
                if SweepRules.isHidden(name) || SweepRules.isPackage(name) || isHomeLibrary {
                    e.skipDescendants()
                }
                continue
            }
            if SweepRules.isHidden(name) { continue }
            guard v.isRegularFile == true else { continue }
            // Allocated size 0 = cloud-only placeholder: deleting it would remove it everywhere.
            let allocated = Int64(v.totalFileAllocatedSize ?? 0)
            guard allocated > 0, allocated >= minBytes else { continue }
            found.append(Found(url: url, size: allocated, access: v.contentAccessDate, modified: v.contentModificationDate))
        }
        progress.tick(batch)

        let total = found.reduce(Int64(0)) { $0 + $1.size }
        let count = found.count
        found.sort { $0.size > $1.size }
        if found.count > maxResults { found = Array(found.prefix(maxResults)) }

        var files: [LargeFile] = []
        files.reserveCapacity(found.count)
        for f in found {
            // "Last opened" from Spotlight like Finder; file times are touched by backups and
            // indexing, so they are only the fallback.
            let spotlight: Date? = progress.isCancelled ? nil : SweepRules.spotlightLastUsed(f.url)
            let last = spotlight ?? f.access ?? f.modified
            files.append(LargeFile(url: f.url, size: f.size, lastUsed: last, kind: FileKind.of(f.url)))
        }
        return (files, total, count)
    }
}
