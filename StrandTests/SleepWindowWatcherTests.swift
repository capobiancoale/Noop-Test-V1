import XCTest
@testable import Strand

/// Pins the iOS/macOS adaptive smart-alarm light-sleep detector (#207) — a direct port of the
/// Android `SleepWindowWatcherTest`. The detector only ADVISES `AppModel.evaluateSmartAlarmWindow`
/// to move the guaranteed wake earlier — it can never skip the hard deadline armed by
/// `applySmartAlarm` — so these tests just assert the heuristic fires once on a real HR rise and
/// stays quiet otherwise.
final class SleepWindowWatcherTests: XCTestCase {

    private func watcher() -> SleepWindowWatcher {
        SleepWindowWatcher(riseBpm: 6, minSamples: 5, troughCeilingBpm: 90)
    }

    func testStaysQuietBeforeEnoughSamples() {
        let w = watcher()
        // Even a spike before the warm-up sample count is reached must not fire.
        for _ in 0..<4 { XCTAssertFalse(w.shouldWake(bpm: 80)) }
    }

    func testFiresOnceOnRiseAboveTrough() {
        let w = watcher()
        // Settle near a trough of 50 bpm over the warm-up window.
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 50)) }
        // A clear rise of >= 6 bpm above the trough = lighter phase → fire exactly once.
        XCTAssertTrue(w.shouldWake(bpm: 58))
        // No re-fire on subsequent readings.
        XCTAssertFalse(w.shouldWake(bpm: 60))
        XCTAssertFalse(w.shouldWake(bpm: 58))
    }

    func testSmallWobbleDoesNotFire() {
        let w = watcher()
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 52)) }
        // +4 is below the 6 bpm threshold.
        XCTAssertFalse(w.shouldWake(bpm: 56))
    }

    func testIgnoresNonPositiveHr() {
        let w = watcher()
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 50)) }
        // No live HR (0 or negative) must never trip the alarm — that's the BLE-down case where the
        // hard deadline is the only thing that should wake the user.
        XCTAssertFalse(w.shouldWake(bpm: 0))
        XCTAssertFalse(w.shouldWake(bpm: -1))
    }

    func testHighBriefSpikeDoesNotPoisonTheTrough() {
        let w = watcher()
        // A brief got-up-to-the-bathroom spike above the ceiling must not be recorded as the trough,
        // so the later genuine trough still anchors the rise detection.
        XCTAssertFalse(w.shouldWake(bpm: 120))
        for _ in 0..<6 { XCTAssertFalse(w.shouldWake(bpm: 48)) }
        XCTAssertTrue(w.shouldWake(bpm: 55))   // 55 is +7 over the real trough of 48
    }

    func testResetClearsState() {
        let w = watcher()
        for _ in 0..<6 { _ = w.shouldWake(bpm: 50) }
        XCTAssertTrue(w.shouldWake(bpm: 58))
        w.reset()
        // After reset the warm-up gate applies again.
        XCTAssertFalse(w.shouldWake(bpm: 58))
    }
}
