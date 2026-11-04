import Foundation

/// When TabPulse keeps the Mac awake. Plain values in and out, with no AppKit or IOKit, so scripts/test-logic.sh can
/// test it on its own.
struct AwakePolicy {
    /// On battery at or below this, lid-closed mode gives up, so a closed Mac can't run itself flat.
    static let batteryFloor = 20
    /// A blocking Stop hook marks a session done for a few seconds before it works again.
    static let grace: TimeInterval = 15

    var working: Int
    var keepAwake: Bool
    var lidAwake: Bool
    var onBattery = false
    var batteryPercent: Int?        // nil on a Mac with no battery
    var thermal = ProcessInfo.ThermalState.nominal
    var quiet: TimeInterval = .infinity   // seconds since anything last worked; 0 while working

    var busy: Bool { working > 0 || quiet < Self.grace }

    /// Holds off idle sleep only; the display can still sleep.
    var holdIdle: Bool { keepAwake && busy }

    /// Nobody is watching a closed Mac, so lid sleep comes back on when the battery runs low or it gets hot.
    var safe: Bool {
        let low = onBattery && (batteryPercent ?? 100) <= Self.batteryFloor
        return !low && thermal.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    var holdLid: Bool { lidAwake && busy && safe }

    /// Why lid sleep comes back on, read once `holdLid` has turned false.
    var lidRelease: LidRelease { !lidAwake ? .turnedOff : !busy ? .finished : .cutoff }
}

enum LidRelease {
    case finished, cutoff, turnedOff

    /// A lid closed while sleep was off doesn't always put the Mac to sleep once sleep is back on, so TabPulse does.
    /// Not when you turned the option off, and not on a desk setup (external display and power) where macOS keeps
    /// a closed Mac awake anyway.
    func sleepsMac(lidClosed: Bool, clamshellCausesSleep: Bool) -> Bool {
        (self == .finished || self == .cutoff) && lidClosed && clamshellCausesSleep
    }
}
