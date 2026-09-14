import XCTest
@testable import DualVault

final class ChecksumServiceTests: XCTestCase {
    var file: URL!

    override func setUpWithError() throws {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("dv-sum-\(UUID().uuidString).txt")
        try Data("DualVault 校验和测试\n".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: file)
    }

    /// 与系统 shasum -a 256 比对（验收 #3）。
    func testSHA256MatchesShasum() throws {
        let ours = try ChecksumAlgorithm.sha256.compute(of: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let expected = output.split(separator: " ").first.map(String.init) ?? ""
        XCTAssertEqual(ours, expected)
    }

    /// 与 md5 命令比对。
    func testMD5MatchesSystem() throws {
        let ours = try ChecksumAlgorithm.md5.compute(of: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/md5")
        process.arguments = ["-q", file.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let expected = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(ours, expected)
    }

    func testHexValidation() {
        XCTAssertTrue(ChecksumAlgorithm.isValidHex("a1B2c3"))
        XCTAssertFalse(ChecksumAlgorithm.isValidHex(""))
        XCTAssertFalse(ChecksumAlgorithm.isValidHex("xyz"))
    }
}
