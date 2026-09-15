import Foundation

/// The light-sleep detector for the iOS/macOS adaptive smart alarm (#207) — PURE so it can be
/// reasoned about and tested, and a direct port of the Android `SleepWindowWatcher` so the two
/// platforms make the same call from the same heart-rate pattern.
///
/// It never touches the strap or a notification itself; it only DECIDES whether the current
/// overnight HR pattern looks like a lighter sleep phase (or an arousal) within the wake window.
/// The caller (`AppModel.evaluateSmartAlarmWindow`) feeds it the live heart rate once `now` is
/// inside the window and, if `shouldWake` returns true, advances the guaranteed wake by re-arming
/// the strap buzz + backup notification for `now` instead of the deadline. This detector is
/// advisory only — the hard deadline, armed the moment the window opens by `applySmartAlarm`,
/// remains the floor of safety if this never fires.
///
/// HONEST signal, no over-claiming: during deep sleep heart rate sits near its nightly trough and
/// is steady; in lighter sleep / on an arousal it lifts above that trough. We track the lowest
/// smoothed HR seen this window (the trough proxy) and fire when the current HR rises a meaningful
/// margin above it AND is itself not at the floor. This is a coarse "you're stirring" heuristic —
/// it is NOT a sleep-stage classifier and makes no clinical claim. If the strap streams nothing
/// (BLE down, phone out of range, or the app never gets a background delivery), the detector simply
/// never fires and the hard deadline wakes the user, exactly as it did before this existed.
final class SleepWindowWatcher {
    /// How far above the nightly trough (bpm) counts as "lighter / stirring".
    private let riseBpm: Int
    /// Don't trust the trough until we've seen at least this many samples this window.
    private let minSamples: Int
    /// Ignore obviously-awake-high HR as a trough candidate (e.g. the user got up briefly).
    private let troughCeilingBpm: Int

    private var troughBpm: Int = .max
    private var sampleCount: Int = 0
    /// Set once we've advanced the alarm so we don't keep re-advancing every sample.
    private var fired: Bool = false

    init(riseBpm: Int = 6, minSamples: Int = 30, troughCeilingBpm: Int = 90) {
        self.riseBpm = riseBpm
        self.minSamples = minSamples
        self.troughCeilingBpm = troughCeilingBpm
    }

    /// Reset for a fresh window (called whenever `AppModel.applySmartAlarm` re-arms tonight's alarm).
    func reset() {
        troughBpm = .max
        sampleCount = 0
        fired = false
    }

    /// Feed one heart-rate reading (bpm). Returns true exactly once — when the reading first looks
    /// like a lighter phase inside the window — so the caller advances the alarm a single time. All
    /// later calls return false until `reset()`. A non-positive HR (no live data) is ignored.
    func shouldWake(bpm: Int) -> Bool {
        guard bpm > 0 else { return false }
        sampleCount += 1
        if bpm <= troughCeilingBpm && bpm < troughBpm { troughBpm = bpm }
        if fired { return false }
        guard sampleCount >= minSamples, troughBpm != .max else { return false }
        if bpm >= troughBpm + riseBpm && bpm > troughBpm {
            fired = true
            return true
        }
        return false
    }
}
