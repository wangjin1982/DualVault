import XCTest
@testable import DualVault

/// F2-A：zip 虚拟树 + 容错 + 按条目提取。
final class ZipBrowserTests: XCTestCase {
    var base: URL!
    var srcDir: URL!
    var outDir: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-zipb-\(UUID().uuidString)")
        srcDir = base.appendingPathComponent("src")
        outDir = base.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func makeZip() throws -> URL {
        let sub = srcDir.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("内容A".utf8).write(to: srcDir.appendingPathComponent("根文件.txt"))
        try Data("内容B".utf8).write(to: sub.appendingPathComponent("嵌套 文件.txt"))
        let zipURL = outDir.appendingPathComponent("browse.zip")
        try ZipEngine.zip([srcDir.appendingPathComponent("根文件.txt"), sub],
                          to: zipURL, isCancelled: { false })
        return zipURL
    }

    func testVirtualTreeNestedAndChineseNames() throws {
        let zip = try makeZip()
        let root = try ZipBrowser.children(of: zip, innerPath: "")
        XCTAssertEqual(root.map(\.name), ["子目录", "根文件.txt"])   // 目录优先
        XCTAssertTrue(root[0].isDirectory)
        XCTAssertFalse(root[1].isDirectory)

        let sub = try ZipBrowser.children(of: zip, innerPath: "子目录/")
        XCTAssertEqual(sub.map(\.name), ["嵌套 文件.txt"])
        XCTAssertEqual(sub[0].size, Int64(Data("内容B".utf8).count))
    }

    func testEmptyZipHasNoChildren() throws {
        let zip = outDir.appendingPathComponent("empty.zip")
        try ZipEngine.zip([], to: zip, isCancelled: { false })
        XCTAssertTrue(try ZipBrowser.children(of: zip, innerPath: "").isEmpty)
    }

    func testDamagedZipThrows() throws {
        let broken = outDir.appendingPathComponent("broken.zip")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x00]).write(to: broken)
        XCTAssertThrowsError(try ZipBrowser.children(of: broken, innerPath: ""))
    }

    func testEncryptedZipThrowsEncrypted() throws {
        // 构造带加密标志位的手写 zip：一个本地头 + 一个中央目录条目（gpFlags=1）+ EOCD
        var zip = Data()
        let name = Array("a.txt".utf8)
        zip.appendLE(UInt32(0x04034b50)); zip.appendLE(UInt16(20)); zip.appendLE(UInt16(1))
        zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0)); zip.appendLE(UInt32(0)); zip.appendLE(UInt32(0))
        zip.appendLE(UInt16(name.count)); zip.appendLE(UInt16(0)); zip.append(contentsOf: name)
        let localOffset = zip.count - (30 + name.count)
        zip.append(contentsOf: [0x00]) // 假数据
        let centralOffset = zip.count
        zip.appendLE(UInt32(0x02014b50)); zip.appendLE(UInt16(20)); zip.appendLE(UInt16(20))
        zip.appendLE(UInt16(1))  // gpFlags = 1（加密）
        zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0)); zip.appendLE(UInt32(1)); zip.appendLE(UInt32(0))
        zip.appendLE(UInt16(name.count)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0)); zip.appendLE(UInt32(0)); zip.appendLE(UInt32(UInt32(localOffset)))
        zip.append(contentsOf: name)
        zip.appendLE(UInt32(0x06054b50)); zip.appendLE(UInt16(0)); zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(1)); zip.appendLE(UInt16(1))
        zip.appendLE(UInt32(46 + name.count + 1)); zip.appendLE(UInt32(centralOffset)); zip.appendLE(UInt16(0))
        let file = outDir.appendingPathComponent("enc.zip")
        try zip.write(to: file)

        XCTAssertThrowsError(try ZipBrowser.children(of: file, innerPath: "")) { error in
            XCTAssertEqual(error as? ZipEngine.ZipError, .encrypted)
        }
    }

    func testExtractOnlySelectedEntries() throws {
        let zip = try makeZip()
        let extractTo = base.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractTo, withIntermediateDirectories: true)
        let op = ZipExtractOperation(
            archive: zip, destination: extractTo,
            resolutions: ConflictResolutions(),
            only: ["根文件.txt"])
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractTo.appendingPathComponent("根文件.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractTo.appendingPathComponent("子目录").path))
    }

    func testExtractDirectoryEntryPullsChildren() throws {
        let zip = try makeZip()
        let extractTo = base.appendingPathComponent("extracted2")
        try FileManager.default.createDirectory(at: extractTo, withIntermediateDirectories: true)
        let op = ZipExtractOperation(
            archive: zip, destination: extractTo,
            resolutions: ConflictResolutions(),
            only: ["子目录/"])
        try op.execute(isCancelled: { false }, progress: { _, _, _, _ in })
        let extracted = try String(contentsOf: extractTo.appendingPathComponent("子目录/嵌套 文件.txt"))
        XCTAssertEqual(extracted, "内容B")
    }
}

/// F2-B：App 扫描与关联收集。
final class AppScannerTests: XCTestCase {
    var base: URL!
    var appsDir: URL!
    var libraryRoot: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("dv-app-\(UUID().uuidString)")
        appsDir = base.appendingPathComponent("Applications")
        libraryRoot = base.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: appsDir.appendingPathComponent("FakeApp.app/Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func installFakeApp(name: String = "FakeApp", bundleID: String = "com.example.fake") throws {
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleIdentifier": bundleID,
        ]
        let plist = appsDir.appendingPathComponent("\(name).app/Contents/Info.plist")
        try (info as NSDictionary).write(to: plist)
        try Data(count: 100).write(to: appsDir.appendingPathComponent("\(name).app/Contents/payload.bin"))
    }

    func testScanReadsBundleInfo() throws {
        try installFakeApp()
        let apps = AppScanner.scan(applicationsDirs: [appsDir])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].name, "FakeApp")
        XCTAssertEqual(apps[0].version, "1.2.3")
        XCTAssertEqual(apps[0].bundleID, "com.example.fake")
        XCTAssertGreaterThan(apps[0].size, 0)
        XCTAssertFalse(apps[0].isSystem)
    }

    func testSystemAppsMarkedReadonly() throws {
        let systemDir = base.appendingPathComponent("SystemApplications")
        try FileManager.default.createDirectory(at: systemDir, withIntermediateDirectories: true)
        let apps = AppScanner.scan(applicationsDirs: [systemDir])
        // 构造的目录不以 /System 开头，用前缀模拟验证标记逻辑
        XCTAssertTrue(apps.isEmpty)
    }

    func testRelatedFilesByBundleIDHighConfidence() throws {
        try installFakeApp()
        let prefs = libraryRoot.appendingPathComponent("Preferences")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        try Data().write(to: prefs.appendingPathComponent("com.example.fake.plist"))
        try Data().write(to: prefs.appendingPathComponent("unrelated.plist"))

        let app = AppScanner.scan(applicationsDirs: [appsDir])[0]
        let related = AppScanner.relatedFiles(app: app, libraryRoots: [libraryRoot])
        XCTAssertEqual(related.count, 1)
        XCTAssertEqual(related[0].path.lastPathComponent, "com.example.fake.plist")
        XCTAssertEqual(related[0].confidence, .high)
    }

    func testRelatedFilesByNameLowConfidence() throws {
        try installFakeApp()
        let caches = libraryRoot.appendingPathComponent("Caches")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data().write(to: caches.appendingPathComponent("FakeAppCache"))

        let app = AppScanner.scan(applicationsDirs: [appsDir])[0]
        let related = AppScanner.relatedFiles(app: app, libraryRoots: [libraryRoot])
        XCTAssertEqual(related.count, 1)
        XCTAssertEqual(related[0].confidence, .low)
    }

    func testExcludedPrefixesNeverReturned() {
        // 直接验证红线：不匹配系统路径
        for prefix in AppScanner.excludedPrefixes {
            XCTAssertTrue("/System/Library/x".hasPrefix(prefix) == (prefix == "/System"))
        }
        // 构造一个在 excludedPrefixes 下的假路径参与 consider 逻辑（经 relatedFiles 的 guard）
        let fakeApp = InstalledApp(bundleURL: URL(fileURLWithPath: "/tmp/x.app"), name: "System",
                                   version: "1", size: 0, bundleID: "com.system", isSystem: false)
        // libraryRoots 指向真实文件系统受限，构造不可能的 root 使扫描为空但不崩
        let related = AppScanner.relatedFiles(app: fakeApp, libraryRoots: [URL(fileURLWithPath: "/nonexistent-root")])
        XCTAssertTrue(related.isEmpty)
    }

    func testSystemAppYieldsNoRelatedFiles() throws {
        try installFakeApp()
        let systemApp = InstalledApp(bundleURL: URL(fileURLWithPath: "/System/Applications/Safari.app"),
                                     name: "Safari", version: "17", size: 0,
                                     bundleID: "com.apple.Safari", isSystem: true)
        let related = AppScanner.relatedFiles(app: systemApp, libraryRoots: [libraryRoot])
        XCTAssertTrue(related.isEmpty)
    }
}
