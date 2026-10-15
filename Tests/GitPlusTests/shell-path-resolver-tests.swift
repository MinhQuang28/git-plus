import XCTest
@testable import GitPlus

final class ShellPathResolverTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "gitplus-path-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(atPath: home)
    }

    private func install(_ versions: [String], alias: String? = nil) throws -> String {
        let nvm = home + "/.nvm"
        for v in versions {
            try FileManager.default.createDirectory(atPath: "\(nvm)/versions/node/\(v)/bin", withIntermediateDirectories: true)
        }
        if let alias {
            try FileManager.default.createDirectory(atPath: nvm + "/alias", withIntermediateDirectories: true)
            try (alias + "\n").write(toFile: nvm + "/alias/default", atomically: true, encoding: .utf8)
        }
        return nvm
    }

    func testNvmDefaultBinFollowsAlias() throws {
        let nvm = try install(["v22.1.0", "v26.12.0"], alias: "22.1.0")
        XCTAssertEqual(ShellPathResolver.nvmDefaultBin(nvmDir: nvm), nvm + "/versions/node/v22.1.0/bin")
    }

    func testNvmDefaultBinMatchesMajorAlias() throws {
        let nvm = try install(["v22.1.0", "v26.12.0"], alias: "22")
        XCTAssertEqual(ShellPathResolver.nvmDefaultBin(nvmDir: nvm), nvm + "/versions/node/v22.1.0/bin")
    }

    func testNvmDefaultBinFallsBackToNewest() throws {
        // "lts/*" is not an installed version; numeric ordering must beat lexical (v9 < v26).
        let nvm = try install(["v9.0.0", "v26.12.0"], alias: "lts/*")
        XCTAssertEqual(ShellPathResolver.nvmDefaultBin(nvmDir: nvm), nvm + "/versions/node/v26.12.0/bin")
    }

    func testNvmDefaultBinNilWithoutInstalls() {
        XCTAssertNil(ShellPathResolver.nvmDefaultBin(nvmDir: home + "/.nvm"))
    }

    func testToolchainDirectoriesOnlyExisting() throws {
        let nvm = try install(["v26.12.0"])
        try FileManager.default.createDirectory(atPath: home + "/.volta/bin", withIntermediateDirectories: true)
        let dirs = ShellPathResolver.toolchainDirectories(home: home, env: [:])
        XCTAssertEqual(dirs, [nvm + "/versions/node/v26.12.0/bin", home + "/.volta/bin"])
    }

    func testToolchainDirectoriesHonourNvmDir() throws {
        let custom = home + "/custom-nvm"
        try FileManager.default.createDirectory(atPath: custom + "/versions/node/v26.12.0/bin", withIntermediateDirectories: true)
        let dirs = ShellPathResolver.toolchainDirectories(home: home, env: ["NVM_DIR": custom])
        XCTAssertEqual(dirs, [custom + "/versions/node/v26.12.0/bin"])
    }

    func testEnvironmentPathIsDeduplicatedAndUsable() {
        let path = ProcessRunner.environment["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(path.count, Set(path).count, "PATH must not repeat entries")
        XCTAssertTrue(path.contains("/usr/bin"))
    }
}
