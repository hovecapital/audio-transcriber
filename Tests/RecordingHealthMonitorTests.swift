import Foundation
import XCTest

@testable import MeetingRecorderCore

@MainActor
final class RecordingHealthMonitorTests: XCTestCase {
    func testInitialState() {
        let monitor = RecordingHealthMonitor()
        XCTAssertTrue(monitor.micHealthy)
        XCTAssertTrue(monitor.systemHealthy)
    }

    func testBufferReceivedKeepsHealthy() async {
        let monitor = RecordingHealthMonitor()
        monitor.start()

        monitor.recordBufferReceived(source: .microphone, frameCount: 1024)
        monitor.recordBufferReceived(source: .systemAudio, frameCount: 512)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(monitor.micHealthy)
        XCTAssertTrue(monitor.systemHealthy)

        monitor.stop()
    }

    func testStreamDeathMarksUnhealthy() async {
        let monitor = RecordingHealthMonitor()
        monitor.start()

        let testError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        monitor.reportStreamDeath(source: .microphone, error: testError)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(monitor.micHealthy)
        XCTAssertTrue(monitor.systemHealthy)

        monitor.stop()
    }

    func testSystemStreamDeathMarksUnhealthy() async {
        let monitor = RecordingHealthMonitor()
        monitor.start()

        let testError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        monitor.reportStreamDeath(source: .systemAudio, error: testError)

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(monitor.micHealthy)
        XCTAssertFalse(monitor.systemHealthy)

        monitor.stop()
    }

    func testBufferRestoresHealth() async {
        let monitor = RecordingHealthMonitor()
        monitor.start()

        let testError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        monitor.reportStreamDeath(source: .microphone, error: testError)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(monitor.micHealthy)

        monitor.recordBufferReceived(source: .microphone, frameCount: 1024)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(monitor.micHealthy)

        monitor.stop()
    }
}
