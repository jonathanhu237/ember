/// Pure decision logic: given the current system state and settings, decide what to hold.
///
/// The app calls `decide` on every tick and applies the difference. Everything that depends
/// on time or on the previous tick is passed in explicitly, so the logic stays testable.
public enum Policy {
    public static func decide(
        _ now: SystemSnapshot,
        settings: EmberSettings,
        previousSnapshot: SystemSnapshot?,
        previousDecision: PowerDecision?
    ) -> PowerDecision {
        guard settings.isEnabled else {
            return finish(.inactive, now: now, previousDecision: previousDecision)
        }

        if now.powerSource == .battery,
           let floor = settings.batteryFloorPercent,
           let charge = now.batteryPercent,
           charge < floor {
            var stopped = PowerDecision.inactive
            stopped.stoppedByBatteryFloor = true
            return finish(stopped, now: now, previousDecision: previousDecision)
        }

        let profile = settings.profile(for: now.powerSource)
        let lidClosed = now.isLidClosed
        // Displays may only go dark with the lid closed while `disablesleep` is on: otherwise
        // macOS sleeps a closed Mac the moment its last awake external display sleeps.
        let goDark = lidClosed && profile.darkenDisplaysWhenLidClosed && now.isLidSleepDisabled
        // For the same reason, without the flag a closed Mac that should keep running needs an
        // external display kept awake.
        let holdDisplayForClamshell = lidClosed && profile.runWithLidClosed
            && !now.isLidSleepDisabled && now.externalDisplayCount > 0

        var decision = PowerDecision()
        decision.preventIdleSystemSleep = profile.keepAwake || (lidClosed && profile.runWithLidClosed)
        // With the lid closed and going dark, let the displays sleep; otherwise (for example
        // working in clamshell mode at a desk) honour "keep display on" as usual.
        decision.preventIdleDisplaySleep = (profile.keepDisplayOn && !goDark) || holdDisplayForClamshell
        // Has to be in place before the lid closes, or the Mac sleeps on the spot.
        decision.disableLidSleep = profile.runWithLidClosed
        decision.darkeningNeedsLidSleepDisabled = profile.darkenDisplaysWhenLidClosed
            && profile.runWithLidClosed && !now.isLidSleepDisabled

        if goDark, now.externalDisplayCount > 0, !now.areDisplaysAsleep {
            let lidJustClosed = previousSnapshot.map { !$0.isLidClosed } ?? false
            let idleLongEnough = now.secondsSinceUserInput >= settings.redarkenAfterIdleSeconds
            decision.darkenDisplaysNow = lidJustClosed || idleLongEnough
        }

        return finish(decision, now: now, previousDecision: previousDecision)
    }

    /// If the Mac was being kept running with the lid closed and no longer is, put it to sleep
    /// now instead of relying on macOS to notice, so it never keeps running inside a bag.
    private static func finish(
        _ decision: PowerDecision,
        now: SystemSnapshot,
        previousDecision: PowerDecision?
    ) -> PowerDecision {
        var decision = decision
        let wasRunningWithLidClosed = previousDecision?.disableLidSleep ?? false
        decision.sleepSystemNow = now.isLidClosed && wasRunningWithLidClosed && !decision.disableLidSleep
        if decision.sleepSystemNow {
            decision.darkenDisplaysNow = false
        }
        return decision
    }
}
