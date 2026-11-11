/// Where the Mac is currently drawing power from.
public enum PowerSource: String, Codable, Sendable {
    case ac
    case battery
}

/// What Ember should do while the Mac is on one particular power source.
public struct PowerProfile: Codable, Equatable, Sendable {
    /// Prevent idle system sleep.
    public var keepAwake: Bool
    /// Prevent the displays from sleeping when idle.
    public var keepDisplayOn: Bool
    /// Keep the Mac running when the lid is closed, even without an external display.
    public var runWithLidClosed: Bool
    /// Put all displays to sleep as soon as the lid closes (the Mac keeps running).
    public var darkenDisplaysWhenLidClosed: Bool

    public init(
        keepAwake: Bool,
        keepDisplayOn: Bool,
        runWithLidClosed: Bool,
        darkenDisplaysWhenLidClosed: Bool
    ) {
        self.keepAwake = keepAwake
        self.keepDisplayOn = keepDisplayOn
        self.runWithLidClosed = runWithLidClosed
        self.darkenDisplaysWhenLidClosed = darkenDisplaysWhenLidClosed
    }

    /// Everything on: stay awake, screen on while open, keep working and go dark when closed.
    public static let alwaysOn = PowerProfile(
        keepAwake: true,
        keepDisplayOn: true,
        runWithLidClosed: true,
        darkenDisplaysWhenLidClosed: true
    )

    /// Everything off: behave like a normal laptop.
    public static let normal = PowerProfile(
        keepAwake: false,
        keepDisplayOn: false,
        runWithLidClosed: false,
        darkenDisplaysWhenLidClosed: false
    )
}

/// All user-facing settings. Persisted as JSON.
public struct EmberSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var onPower: PowerProfile
    public var onBattery: PowerProfile
    /// On battery, stop keeping the Mac awake below this charge. `nil` disables the floor.
    public var batteryFloorPercent: Int?
    /// While the lid is closed, put displays back to sleep after this many idle seconds
    /// if something woke them (for example a jittery wireless mouse).
    public var redarkenAfterIdleSeconds: Double

    public init(
        isEnabled: Bool,
        onPower: PowerProfile,
        onBattery: PowerProfile,
        batteryFloorPercent: Int?,
        redarkenAfterIdleSeconds: Double
    ) {
        self.isEnabled = isEnabled
        self.onPower = onPower
        self.onBattery = onBattery
        self.batteryFloorPercent = batteryFloorPercent
        self.redarkenAfterIdleSeconds = redarkenAfterIdleSeconds
    }

    /// Plugged in: keep working, lid open or closed. On battery: a normal laptop.
    public static let `default` = EmberSettings(
        isEnabled: true,
        onPower: .alwaysOn,
        onBattery: .normal,
        batteryFloorPercent: 20,
        redarkenAfterIdleSeconds: 30
    )

    public func profile(for source: PowerSource) -> PowerProfile {
        switch source {
        case .ac: onPower
        case .battery: onBattery
        }
    }
}

/// A point-in-time reading of everything the policy depends on.
public struct SystemSnapshot: Equatable, Sendable {
    public var powerSource: PowerSource
    /// Battery charge in percent, or `nil` on Macs without a battery.
    public var batteryPercent: Int?
    public var isLidClosed: Bool
    public var externalDisplayCount: Int
    public var areDisplaysAsleep: Bool
    public var secondsSinceUserInput: Double
    /// Whether `pmset disablesleep` is currently on. Without it, macOS keeps a closed Mac
    /// running only while an external display is awake, and sleeps it as soon as they all sleep.
    public var isLidSleepDisabled: Bool

    public init(
        powerSource: PowerSource,
        batteryPercent: Int?,
        isLidClosed: Bool,
        externalDisplayCount: Int,
        areDisplaysAsleep: Bool,
        secondsSinceUserInput: Double,
        isLidSleepDisabled: Bool
    ) {
        self.powerSource = powerSource
        self.batteryPercent = batteryPercent
        self.isLidClosed = isLidClosed
        self.externalDisplayCount = externalDisplayCount
        self.areDisplaysAsleep = areDisplaysAsleep
        self.secondsSinceUserInput = secondsSinceUserInput
        self.isLidSleepDisabled = isLidSleepDisabled
    }
}

/// What the app should make true right now.
public struct PowerDecision: Equatable, Sendable {
    /// Hold a "prevent idle system sleep" assertion.
    public var preventIdleSystemSleep: Bool
    /// Hold a "prevent idle display sleep" assertion.
    public var preventIdleDisplaySleep: Bool
    /// System-wide `pmset disablesleep 1`, so closing the lid does not sleep the Mac.
    /// Must be set *before* the lid closes. Requires the privileged helper.
    public var disableLidSleep: Bool
    /// One-shot: put all displays to sleep now (`pmset displaysleepnow`).
    public var darkenDisplaysNow: Bool
    /// One-shot: put the Mac to sleep now (`pmset sleepnow`). Used when the Mac stops being
    /// allowed to run with the lid already closed, e.g. it was unplugged to go into a bag.
    public var sleepSystemNow: Bool
    /// Why everything is off, if the battery floor kicked in.
    public var stoppedByBatteryFloor: Bool
    /// The profile wants the displays dark with the lid closed, but that would put the Mac to
    /// sleep because `pmset disablesleep` is off. The displays are kept awake instead.
    public var darkeningNeedsLidSleepDisabled: Bool

    public init(
        preventIdleSystemSleep: Bool = false,
        preventIdleDisplaySleep: Bool = false,
        disableLidSleep: Bool = false,
        darkenDisplaysNow: Bool = false,
        sleepSystemNow: Bool = false,
        stoppedByBatteryFloor: Bool = false,
        darkeningNeedsLidSleepDisabled: Bool = false
    ) {
        self.preventIdleSystemSleep = preventIdleSystemSleep
        self.preventIdleDisplaySleep = preventIdleDisplaySleep
        self.disableLidSleep = disableLidSleep
        self.darkenDisplaysNow = darkenDisplaysNow
        self.sleepSystemNow = sleepSystemNow
        self.stoppedByBatteryFloor = stoppedByBatteryFloor
        self.darkeningNeedsLidSleepDisabled = darkeningNeedsLidSleepDisabled
    }

    public static let inactive = PowerDecision()

    /// True when Ember is actively keeping something awake.
    public var isKeepingAwake: Bool {
        preventIdleSystemSleep || preventIdleDisplaySleep || disableLidSleep
    }
}
