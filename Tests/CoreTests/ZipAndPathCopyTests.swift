import XCTest
@testable import DualVault

final class ZipEngineTests: XCTestCase {
    var base: URL!
    var srcDir: URL!
    var outDir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-zip-\(UUID().uuidString)")
        srcDir = base.appendingPathComponent("src")
        outDir = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    /// 压缩 3 文件（含子目录）→ 解压 → 逐字节比对。
    func testZipUnzipRoundTrip() throws {
        let f1 = srcDir.appendingPathComponent("a.txt")
        let f2 = srcDir.appendingPathComponent("b.txt")
        let sub = srcDir.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let f3 = sub.appendingPathComponent("c.bin")
        let d1 = Data(repeating: 1, count: 100_000)   // 可压缩
        let d2 = Data((0..<5000).map { UInt8($0 % 251) })
        let d3 = Data(repeating: 9, count: 777)
        try d1.write(to: f1); try d2.write(to: f2); try d3.write(to: f3)

        let zipURL = outDir.appendingPathComponent("test.zip")
        try ZipEngine.zip([f1, f2, sub], to: zipURL, isCancelled: { false })

        // 压缩确实生效（deflate 对重复数据有明显压缩）
        let zipSize = (try FileManager.default.attributesOfItem(atPath: zipURL.path))[.size] as? Int64 ?? 0
        XCTAssertLessThan(zipSize, Int64(d1.count + d2.count + d3.count))

        let extractTo = base.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractTo, withIntermediateDirectories: true)
        try ZipEngine.unzip(zipURL, to: extractTo, isCancelled: { false }) { $0 }

        XCTAssertEqual(try Data(contentsOf: extractTo.appendingPathComponent("a.txt")), d1)
        XCTAssertEqual(try Data(contentsOf: extractTo.appendingPathComponent("b.txt")), d2)
        XCTAssertEqual(try Data(contentsOf: extractTo.appendingPathComponent("子目录/c.bin")), d3)
    }

    func testSanitizeBlocksZipSlip() {
        XCTAssertNil(ZipEngine.sanitize("../../etc/passwd"))
        XCTAssertNil(ZipEngine.sanitize(".."))
        XCTAssertEqual(ZipEngine.sanitize("a/b/c.txt"), "a/b/c.txt")
    }

    /// 互操作：系统 ditto 生成的 zip 我们能正确解压。
    func testUnzipDittoArchive() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        let refZip = outDir.appendingPathComponent("ref.zip")
        process.arguments = ["-c", "-k", "--keepParent", srcDir.path, refZip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try ZipEngine.unzip(refZip, to: outDir, isCancelled: { false }) { $0 }
        // srcDir 本身会被作为条目（--keepParent），至少不抛错且产出非空
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: outDir.path)).isEmpty)
    }

    func testUnzipConflictUsesResolver() throws {
        let f1 = srcDir.appendingPathComponent("dup.txt")
        try Data("new".utf8).write(to: f1)
        let zipURL = outDir.appendingPathComponent("dup.zip")
        try ZipEngine.zip([f1], to: zipURL, isCancelled: { false })
        try Data("old".utf8).write(to: outDir.appendingPathComponent("dup.txt"))

        try ZipEngine.unzip(zipURL, to: outDir, isCancelled: { false }) { name in
            ConflictResolver.resolvedName(for: name, strategy: .keepBoth,
                                          existingNames: ["dup.txt"])
        }
        XCTAssertEqual(try String(contentsOf: outDir.appendingPathComponent("dup.txt")), "old")
        XCTAssertEqual(try String(contentsOf: outDir.appendingPathComponent("dup 副本.txt")), "new")
    }
}

final class PathCopyServiceTests: XCTestCase {
    let spaced = URL(fileURLWithPath: "/Users/test/我的 文件.txt")

    func testPosixSingle() {
        XCTAssertEqual(PathCopyService.posixPaths([spaced]), "/Users/test/我的 文件.txt")
    }

    func testPosixMultipleJoinsNewline() {
        let urls = [spaced, URL(fileURLWithPath: "/a/b.pdf")]
        XCTAssertEqual(PathCopyService.posixPaths(urls), "/Users/test/我的 文件.txt\n/a/b.pdf")
    }

    func testFileURLFormat() {
        XCTAssertTrue(PathCopyService.fileURLs([spaced]).hasPrefix("file://"))
    }

    func testFileNamesOnly() {
        let urls = [spaced, URL(fileURLWithPath: "/a/b.pdf")]
        XCTAssertEqual(PathCopyService.fileNames(urls), "我的 文件.txt\nb.pdf")
    }
}
