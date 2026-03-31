import Foundation
import XCTest

@testable import MeetingRecorderCore

final class WAVFileValidatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAVValidatorTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testNonExistentFile() {
        let url = tempDir.appendingPathComponent("missing.wav")
        let result = WAVFileValidator.validate(url: url)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.fileSize, 0)
        XCTAssertFalse(result.hasAudioData)
        XCTAssertNotNil(result.errorMessage)
    }

    func testEmptyFile() throws {
        let url = tempDir.appendingPathComponent("empty.wav")
        try Data().write(to: url)
        let result = WAVFileValidator.validate(url: url)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.fileSize, 0)
        XCTAssertFalse(result.hasAudioData)
    }

    func testHeaderOnlyFile() throws {
        let url = tempDir.appendingPathComponent("header_only.wav")
        let headerData = Data(repeating: 0, count: 44)
        try headerData.write(to: url)
        let result = WAVFileValidator.validate(url: url)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.fileSize, 44)
        XCTAssertFalse(result.hasAudioData)
    }

    func testValidFile() throws {
        let url = tempDir.appendingPathComponent("valid.wav")
        let data = Data(repeating: 0, count: 1024)
        try data.write(to: url)
        let result = WAVFileValidator.validate(url: url)

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.fileSize, 1024)
        XCTAssertTrue(result.hasAudioData)
        XCTAssertNil(result.errorMessage)
    }

    func testBarelyAboveHeader() throws {
        let url = tempDir.appendingPathComponent("barely_valid.wav")
        let data = Data(repeating: 0, count: 45)
        try data.write(to: url)
        let result = WAVFileValidator.validate(url: url)

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.fileSize, 45)
        XCTAssertTrue(result.hasAudioData)
    }
}
