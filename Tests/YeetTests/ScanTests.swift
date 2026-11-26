import XCTest
@testable import Yeet

/// Runs the Large Files and Duplicates engines on a throw-away folder tree (no sandbox).
final class ScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("yeet-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `bytes` of non-repeating data so the file really occupies disk space.
    @discardableResult
    private func write(_ relative: String, bytes: Int, seed: UInt8 = 1) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            var x: UInt32 = 2_463_534_242 &+ UInt32(seed)
            for i in 0..<p.count {
                x ^= x << 13; x ^= x >> 17; x ^= x << 5
                p[i] = UInt8(truncatingIfNeeded: x)
            }
        }
        try data.write(to: url)
        return url
    }

    func testLargeFilesFindsBigFilesAndSkipsLibraryHiddenAndSmall() throws {
        try write("Downloads/big.iso", bytes: 60_000_000)
        try write("Movies/clip.mov", bytes: 55_000_000, seed: 2)
        try write("Documents/small.pdf", bytes: 2_000_000)
        try write("Library/Caches/huge.bin", bytes: 60_000_000, seed: 3)
        try write(".hidden/secret.bin", bytes: 60_000_000, seed: 4)

        let r = LargeFilesStore.walk(root: root, minBytes: 50_000_000, progress: ScanProgress())
        let names = Set(r.files.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["big.iso", "clip.mov"], "found: \(names)")
        XCTAssertEqual(r.count, 2)
        XCTAssertGreaterThanOrEqual(r.total, 115_000_000)
    }

    func testDuplicatesFindsIdenticalCopies() throws {
        try write("Documents/report.pdf", bytes: 2_000_000, seed: 9)
        try write("Downloads/report (1).pdf", bytes: 2_000_000, seed: 9)
        try write("Downloads/other.pdf", bytes: 2_000_000, seed: 10)

        let roots = [root.appendingPathComponent("Documents"), root.appendingPathComponent("Downloads")]
        let groups = DuplicatesStore.findDuplicates(roots: roots, minBytes: 1_000_000,
                                                    progress: ScanProgress(), hashed: ScanProgress())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }
}
