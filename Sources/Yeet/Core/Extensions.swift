import Foundation
import Observation

// MARK: - Mach-O architecture

/// CPU architectures found in a Mach-O file (thin or universal/fat).
struct MachOArchs: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let arm64 = MachOArchs(rawValue: 1 << 0)
    static let x86_64 = MachOArchs(rawValue: 1 << 1)
    static let other = MachOArchs(rawValue: 1 << 2)

    private static let cpuARM64: UInt32 = 0x0100_000C
    private static let cpuX86_64: UInt32 = 0x0100_0007

    private static func from(cpu: UInt32) -> MachOArchs {
        switch cpu {
        case cpuARM64: return .arm64
        case cpuX86_64: return .x86_64
        default: return .other
        }
    }

    /// Reads only the header. Returns nil for anything that isn't a Mach-O binary.
    static func read(_ url: URL) -> MachOArchs? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 4096), data.count >= 8 else { return nil }
        let b = [UInt8](data)
        func be32(_ o: Int) -> UInt32 {
            guard o + 4 <= b.count else { return 0 }
            return UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
        }
        func le32(_ o: Int) -> UInt32 {
            guard o + 4 <= b.count else { return 0 }
            return UInt32(b[o + 3]) << 24 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 1]) << 8 | UInt32(b[o])
        }
        let magicBE = be32(0)
        // Universal binary: 0xCAFEBABE (32-bit entries, 20 bytes) or 0xCAFEBABF (64-bit, 32 bytes).
        // Java class files share 0xCAFEBABE; their "count" is a version number (≥ 45), so cap it.
        if magicBE == 0xCAFE_BABE || magicBE == 0xCAFE_BABF {
            let n = Int(be32(4))
            guard n > 0, n < 20 else { return nil }
            let stride = magicBE == 0xCAFE_BABF ? 32 : 20
            var out: MachOArchs = []
            for i in 0..<n {
                out.insert(from(cpu: be32(8 + i * stride)))
            }
            return out
        }
        // Thin binary, little-endian (all current Apple platforms): MH_MAGIC / MH_MAGIC_64.
        let magicLE = le32(0)
        if magicLE == 0xFEED_FACE || magicLE == 0xFEED_FACF {
            return from(cpu: le32(4))
        }
        return nil
    }
}

/// What an extension (or app) needs to run on a Mac without Rosetta.
enum NativeStatus: Int, Comparable, Sendable {
    case intelOnly      // every native binary is Intel-only
    case mixed          // some binaries have no Apple silicon slice
    case universal
    case appleSilicon
    case noNative       // JavaScript / WebAssembly / Java only

    static func < (a: NativeStatus, b: NativeStatus) -> Bool { a.rawValue < b.rawValue }

    var needsRosetta: Bool { self == .intelOnly || self == .mixed }

    var title: String {
        switch self {
        case .intelOnly: return L("Intel only", "Chỉ Intel")
        case .mixed: return L("Partly Intel", "Một phần Intel")
        case .universal: return "Universal"
        case .appleSilicon: return "Arm"
        case .noNative: return L("No native code", "Không có mã native")
        }
    }
}

// MARK: - Editor extensions

struct EditorExtension: Identifiable, Sendable {
    var id: String { url.path }
    let editor: String
    let name: String
    let identifier: String      // publisher.name
    let version: String
    let url: URL
    let size: Int64
    let status: NativeStatus
    /// Native binaries without an Apple silicon slice (relative paths, first few).
    let intelBinaries: [String]
    let binaryCount: Int
}

/// Editors whose extensions/plugins live in a known folder under Home.
private struct EditorRoot {
    let editor: String
    let path: String            // relative to Home
    let jetBrains: Bool
}

@Observable
final class ExtensionsStore {
    static let shared = ExtensionsStore()

    var items: [EditorExtension] = []
    var scanning = false
    var scanned = false
    var checked: Set<String> = []
    var onlyRosetta = false
    var trashing = false

    var rosettaCount: Int { items.filter { $0.status.needsRosetta }.count }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var selected: [EditorExtension] { items.filter { checked.contains($0.id) } }
    var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }
    var editors: [String] { Array(Set(items.map(\.editor))).sorted() }

    func visible(search: String) -> [EditorExtension] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { e in
            (!onlyRosetta || e.status.needsRosetta)
                && (q.isEmpty || e.name.lowercased().contains(q) || e.identifier.lowercased().contains(q)
                    || e.editor.lowercased().contains(q))
        }
    }

    func toggle(_ e: EditorExtension) {
        if checked.contains(e.id) { checked.remove(e.id) } else { checked.insert(e.id) }
    }

    @MainActor
    func scan() {
        guard !scanning else { return }
        scanning = true
        Task { @MainActor in
            let found = await Task.detached(priority: .userInitiated) { ExtensionsStore.findAll() }.value
            self.items = found
            self.checked = self.checked.intersection(Set(found.map(\.id)))
            self.scanning = false
            self.scanned = true
        }
    }

    /// Moves the ticked extensions to the Trash. The editor drops them on its next start.
    @MainActor
    func trashSelected() async -> FileOps.Outcome {
        let targets = selected
        guard !targets.isEmpty, !trashing else { return FileOps.Outcome() }
        trashing = true
        var sizes: [URL: Int64] = [:]
        for e in targets { sizes[e.url] = e.size }
        let urls = targets.map(\.url)
        let out = await Task.detached(priority: .userInitiated) { FileOps.moveToTrash(urls, sizes: sizes) }.value
        let gone = Set(out.moved.map(\.path))
        items.removeAll { gone.contains($0.id) }
        checked.subtract(gone)
        trashing = false
        return out
    }

    // MARK: Engine

    private static let roots: [EditorRoot] = [
        EditorRoot(editor: "VS Code", path: ".vscode/extensions", jetBrains: false),
        EditorRoot(editor: "VS Code Insiders", path: ".vscode-insiders/extensions", jetBrains: false),
        EditorRoot(editor: "Cursor", path: ".cursor/extensions", jetBrains: false),
        EditorRoot(editor: "Windsurf", path: ".windsurf/extensions", jetBrains: false),
        EditorRoot(editor: "VSCodium", path: ".vscode-oss/extensions", jetBrains: false),
        EditorRoot(editor: "Kiro", path: ".kiro/extensions", jetBrains: false),
        EditorRoot(editor: "Trae", path: ".trae/extensions", jetBrains: false),
        EditorRoot(editor: "JetBrains", path: "Library/Application Support/JetBrains", jetBrains: true),
    ]

    static func findAll() -> [EditorExtension] {
        let fm = FileManager.default
        var out: [EditorExtension] = []
        for r in roots {
            let base = Paths.home.appendingPathComponent(r.path, isDirectory: true)
            guard fm.fileExists(atPath: base.path) else { continue }
            if r.jetBrains {
                // JetBrains/<Product><version>/plugins/<plugin>
                for product in children(base) where isDir(product) {
                    let plugins = product.appendingPathComponent("plugins", isDirectory: true)
                    for p in children(plugins) where isDir(p) {
                        out.append(inspect(p, editor: product.lastPathComponent, jetBrains: true))
                    }
                }
            } else {
                for e in children(base) where isDir(e) && !e.lastPathComponent.hasPrefix(".") {
                    out.append(inspect(e, editor: r.editor, jetBrains: false))
                }
            }
        }
        return out.sorted { a, b in
            if a.status != b.status { return a.status < b.status }
            return a.size > b.size
        }
    }

    private static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [])) ?? []
    }

    private static func isDir(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Name, version and architecture of one extension / plugin folder.
    static func inspect(_ dir: URL, editor: String, jetBrains: Bool) -> EditorExtension {
        var name = dir.lastPathComponent
        var identifier = dir.lastPathComponent
        var version = ""
        if !jetBrains, let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let pkg = json["name"] as? String ?? name
            let publisher = json["publisher"] as? String
            identifier = publisher.map { "\($0).\(pkg)" } ?? pkg
            if let d = json["displayName"] as? String, !d.isEmpty, !d.hasPrefix("%") { name = d } else { name = pkg }
            version = json["version"] as? String ?? ""
        }

        // Walk the folder: total size + every Mach-O binary.
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        var size: Int64 = 0
        var binaries = 0
        var anyArm = false
        var intelOnly: [String] = []
        let nativeExt: Set<String> = ["node", "dylib", "so", "jnilib", ""]
        if let en = fm.enumerator(at: dir, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            while let u = en.nextObject() as? URL {
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      v.isSymbolicLink != true else { continue }
                size += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                let ext = u.pathExtension.lowercased()
                // Only files that can hold native code: Node add-ons, libraries, extension-less executables.
                guard nativeExt.contains(ext), (v.fileSize ?? 0) >= 4_096 else { continue }
                guard let archs = MachOArchs.read(u) else { continue }
                binaries += 1
                if archs.contains(.arm64) {
                    anyArm = true
                } else if archs.contains(.x86_64) {
                    if intelOnly.count < 5 {
                        intelOnly.append(String(u.path.dropFirst(dir.path.count + 1)))
                    }
                }
            }
        }
        let intelCount = intelOnly.count
        let status: NativeStatus
        if binaries == 0 {
            status = .noNative
        } else if intelCount == 0 {
            status = .appleSilicon
        } else if anyArm {
            status = .mixed
        } else {
            status = .intelOnly
        }
        // "Universal" when every binary carries both slices is rare to tell apart from Arm-only and
        // doesn't change what the user does, so both count as ready for Apple silicon.
        return EditorExtension(editor: editor, name: name, identifier: identifier, version: version, url: dir,
                               size: size, status: status, intelBinaries: intelOnly, binaryCount: binaries)
    }
}
