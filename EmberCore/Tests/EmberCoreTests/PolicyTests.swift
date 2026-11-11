import Testing
@testable import EmberCore

private func snapshot(
    power: PowerSource = .ac,
    battery: Int? = 80,
    lidClosed: Bool = false,
    externalDisplays: Int = 2,
    displaysAsleep: Bool = false,
    idle: Double = 0,
    lidSleepDisabled: Bool = true
) -> SystemSnapshot {
    SystemSnapshot(
        powerSource: power,
        batteryPercent: battery,
        isLidClosed: lidClosed,
        externalDisplayCount: externalDisplays,
        areDisplaysAsleep: displaysAsleep,
        secondsSinceUserInput: idle,
        isLidSleepDisabled: lidSleepDisabled
    )
}

private func decide(
    _ now: SystemSnapshot,
    settings: EmberSettings = .default,
    previous: SystemSnapshot? = nil,
    previousDecision: PowerDecision? = nil
) -> PowerDecision {
    Policy.decide(now, settings: settings, previousSnapshot: previous, previousDecision: previousDecision)
}

@Suite("Default settings")
struct DefaultSettingsTests {
    @Test("Plugged in, lid open: stay awake with the screen on")
    func pluggedInLidOpen() {
        let d = decide(snapshot())
        #expect(d.preventIdleSystemSleep)
        #expect(d.preventIdleDisplaySleep)
        #expect(d.disableLidSleep)
        #expect(!d.darkenDisplaysNow)
        #expect(!d.sleepSystemNow)
    }

    @Test("Plugged in, lid just closed: keep running and darken the displays at once")
    func pluggedInLidJustClosed() {
        let before = snapshot()
        let now = snapshot(lidClosed: true)
        let d = decide(now, previous: before, previousDecision: decide(before))
        #expect(d.preventIdleSystemSleep)
        #expect(!d.preventIdleDisplaySleep)
        #expect(d.disableLidSleep)
        #expect(d.darkenDisplaysNow)
        #expect(!d.sleepSystemNow)
    }

    @Test("Lid closed, displays woken by a stray input: darken again only after the idle delay")
    func redarkenAfterIdle() {
        let closed = snapshot(lidClosed: true)
        let woken = snapshot(lidClosed: true, idle: 5)
        #expect(!decide(woken, previous: closed).darkenDisplaysNow)

        let idle = snapshot(lidClosed: true, idle: 31)
        #expect(decide(idle, previous: closed).darkenDisplaysNow)
    }

    @Test("Lid closed and displays already asleep: nothing more to do")
    func displaysAlreadyAsleep() {
        let closed = snapshot(lidClosed: true)
        let asleep = snapshot(lidClosed: true, displaysAsleep: true, idle: 600)
        #expect(!decide(asleep, previous: closed).darkenDisplaysNow)
    }

    @Test("Lid closed with no external display: keep running, nothing to darken")
    func lidClosedNoExternalDisplay() {
        let before = snapshot(externalDisplays: 0)
        let now = snapshot(lidClosed: true, externalDisplays: 0)
        let d = decide(now, previous: before, previousDecision: decide(before))
        #expect(d.preventIdleSystemSleep)
        #expect(d.disableLidSleep)
        #expect(!d.darkenDisplaysNow)
    }

    @Test("On battery: behave like a normal laptop")
    func onBattery() {
        let d = decide(snapshot(power: .battery, lidClosed: true))
        #expect(d == .inactive)
    }

    @Test("Unplugged with the lid closed (into the bag): release everything and sleep now")
    func unpluggedWithLidClosed() {
        let pluggedClosed = snapshot(lidClosed: true, displaysAsleep: true)
        let unpluggedClosed = snapshot(power: .battery, lidClosed: true, displaysAsleep: true)
        let d = decide(unpluggedClosed, previous: pluggedClosed, previousDecision: decide(pluggedClosed))
        #expect(!d.disableLidSleep)
        #expect(!d.preventIdleSystemSleep)
        #expect(d.sleepSystemNow)
    }

    @Test("Unplugged with the lid open: release everything but do not force sleep")
    func unpluggedWithLidOpen() {
        let plugged = snapshot()
        let unplugged = snapshot(power: .battery)
        let d = decide(unplugged, previous: plugged, previousDecision: decide(plugged))
        #expect(d == .inactive)
    }
}

@Suite("Without closed-lid support (disablesleep off)")
struct WithoutClosedLidSupportTests {
    // Regression: darkening the displays with the lid closed and `disablesleep` off made
    // macOS enter "Clamshell Sleep" on power, stopping the work Ember was meant to keep alive.
    @Test("Lid just closed: do not darken, keep an external display awake so the Mac keeps running")
    func lidClosedKeepsDisplayAwake() {
        let before = snapshot(lidSleepDisabled: false)
        let now = snapshot(lidClosed: true, lidSleepDisabled: false)
        let d = decide(now, previous: before, previousDecision: decide(before))
        #expect(!d.darkenDisplaysNow)
        #expect(d.preventIdleDisplaySleep)
        #expect(d.preventIdleSystemSleep)
        #expect(d.darkeningNeedsLidSleepDisabled)
    }

    @Test("Lid closed for a while: still never darken")
    func neverDarkenWithoutFlag() {
        let closed = snapshot(lidClosed: true, lidSleepDisabled: false)
        let idle = snapshot(lidClosed: true, idle: 600, lidSleepDisabled: false)
        #expect(!decide(idle, previous: closed).darkenDisplaysNow)
    }

    @Test("Lid closed with darkening off and display on off: still hold a display for clamshell")
    func holdDisplayEvenWhenKeepDisplayOff() {
        var settings = EmberSettings.default
        settings.onPower.keepDisplayOn = false
        settings.onPower.darkenDisplaysWhenLidClosed = false
        let d = decide(snapshot(lidClosed: true, lidSleepDisabled: false), settings: settings)
        #expect(d.preventIdleDisplaySleep)
        #expect(!d.darkeningNeedsLidSleepDisabled)
    }

    @Test("Lid open: nothing changes, but the menu can warn that darkening needs set-up")
    func lidOpenWarns() {
        let d = decide(snapshot(lidSleepDisabled: false))
        #expect(d.preventIdleDisplaySleep)
        #expect(d.darkeningNeedsLidSleepDisabled)
    }
}

@Suite("Custom settings")
struct CustomSettingsTests {
    @Test("Disabled: nothing held, and a closed lid that was being kept awake sleeps")
    func disabled() {
        var settings = EmberSettings.default
        let closed = snapshot(lidClosed: true)
        let previous = decide(closed)
        settings.isEnabled = false
        let d = decide(closed, settings: settings, previous: closed, previousDecision: previous)
        #expect(!d.isKeepingAwake)
        #expect(d.sleepSystemNow)
    }

    @Test("Clamshell desk mode: lid closed, darkening off, keep display on stays honoured")
    func clamshellDeskMode() {
        var settings = EmberSettings.default
        settings.onPower.darkenDisplaysWhenLidClosed = false
        let before = snapshot()
        let now = snapshot(lidClosed: true, idle: 120)
        let d = decide(now, settings: settings, previous: before, previousDecision: decide(before, settings: settings))
        #expect(d.preventIdleDisplaySleep)
        #expect(!d.darkenDisplaysNow)
    }

    @Test("Running on battery with the lid closed stops at the battery floor and sleeps")
    func batteryFloor() {
        var settings = EmberSettings.default
        settings.onBattery = .alwaysOn
        settings.batteryFloorPercent = 20

        let above = snapshot(power: .battery, battery: 25, lidClosed: true, displaysAsleep: true)
        let running = decide(above, settings: settings)
        #expect(running.disableLidSleep)

        let below = snapshot(power: .battery, battery: 19, lidClosed: true, displaysAsleep: true)
        let d = decide(below, settings: settings, previous: above, previousDecision: running)
        #expect(d.stoppedByBatteryFloor)
        #expect(!d.isKeepingAwake)
        #expect(d.sleepSystemNow)
    }

    @Test("Battery floor never applies on power")
    func floorIgnoredOnPower() {
        let d = decide(snapshot(battery: 5))
        #expect(!d.stoppedByBatteryFloor)
        #expect(d.preventIdleSystemSleep)
    }

    @Test("Keep awake off but run with lid closed on: only hold system sleep while the lid is closed")
    func runWithLidClosedOnly() {
        var settings = EmberSettings.default
        settings.onPower = PowerProfile(
            keepAwake: false,
            keepDisplayOn: false,
            runWithLidClosed: true,
            darkenDisplaysWhenLidClosed: false
        )
        #expect(!decide(snapshot(), settings: settings).preventIdleSystemSleep)
        #expect(decide(snapshot(lidClosed: true), settings: settings).preventIdleSystemSleep)
    }
}
