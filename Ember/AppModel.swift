import AppKit
import EmberCore
import Observation

/// The part of the system state the menu shows. Idle time is left out on purpose: it changes
/// on every tick and would make the open menu redraw for nothing.
struct StatusSnapshot: Equatable {
    var powerSource: PowerSource
    var batteryPercent: Int?
    var isLidClosed: Bool
    var externalDisplayCount: Int

    init(_ snapshot: SystemSnapshot) {
        powerSource = snapshot.powerSource
        batteryPercent = snapshot.batteryPercent
        isLidClosed = snapshot.isLidClosed
        externalDisplayCount = snapshot.externalDisplayCount
    }
}

/// Reads the system every couple of seconds (and on display/wake changes), asks `Policy` what
/// to hold, and applies the difference.
@MainActor
@Observable
final class AppModel {
    var settings: EmberSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            tick()
        }
    }

    private(set) var status: StatusSnapshot
    private(set) var decision: PowerDecision = .inactive
    private(set) var closedLidSupportReady: Bool
    private(set) var launchAtLogin: Bool
    private(set) var errorMessage: String?

    @ObservationIgnored private let systemAssertion = SleepAssertion(
        type: SleepAssertion.preventIdleSystemSleep,
        reason: "Ember is keeping the Mac awake"
    )
    @ObservationIgnored private let displayAssertion = SleepAssertion(
        type: SleepAssertion.preventIdleDisplaySleep,
        reason: "Ember is keeping the display on"
    )
    @ObservationIgnored private var previousSnapshot: SystemSnapshot?
    @ObservationIgnored private var lastDarkenedAt = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var loop: Task<Void, Never>?

    init() {
        settings = SettingsStore.load()
        status = StatusSnapshot(SystemReader.snapshot())
        closedLidSupportReady = ClosedLidSupport.isInstalled()
        launchAtLogin = LoginItem.isEnabled
        start()
    }

    // MARK: Loop

    private func start() {
        tick()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.tick()
            }
        }

        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Closing or opening the lid reconfigures the displays; react at once instead of
        // waiting for the next tick.
        observe(center, NSApplication.didChangeScreenParametersNotification) { $0.tick() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.tick() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.tick() }
        observe(center, NSApplication.willTerminateNotification) { $0.shutdown() }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ action: @escaping @MainActor (AppModel) -> Void
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        })
    }

    func tick() {
        let now = SystemReader.snapshot()
        let next = Policy.decide(
            now,
            settings: settings,
            previousSnapshot: previousSnapshot,
            previousDecision: decision
        )
        apply(next)
        previousSnapshot = now

        let newStatus = StatusSnapshot(now)
        if status != newStatus { status = newStatus }
        if decision != next { decision = next }
    }

    private func apply(_ decision: PowerDecision) {
        systemAssertion.set(decision.preventIdleSystemSleep)
        displayAssertion.set(decision.preventIdleDisplaySleep)
        applyLidSleepFlag(wanted: decision.disableLidSleep)

        if decision.sleepSystemNow {
            Shell.sleepSystem()
        } else if decision.darkenDisplaysNow, Date().timeIntervalSince(lastDarkenedAt) > 5 {
            lastDarkenedAt = Date()
            Shell.darkenDisplays()
        }
    }

    /// Turn `pmset disablesleep` on or off. Only ever turns off a flag Ember itself turned on.
    private func applyLidSleepFlag(wanted: Bool) {
        let isDisabled = SystemReader.isLidSleepDisabled()
        if wanted {
            guard !isDisabled, closedLidSupportReady else { return }
            if Shell.setLidSleepDisabled(true) {
                ClosedLidSupport.setOwnsLidSleepFlag(true)
            } else {
                closedLidSupportReady = ClosedLidSupport.isInstalled()
            }
        } else if ClosedLidSupport.ownsLidSleepFlag {
            if !isDisabled || Shell.setLidSleepDisabled(false) {
                ClosedLidSupport.setOwnsLidSleepFlag(false)
            }
        }
    }

    private func shutdown() {
        loop?.cancel()
        systemAssertion.set(false)
        displayAssertion.set(false)
        applyLidSleepFlag(wanted: false)
    }

    // MARK: Actions

    func darkenDisplaysNow() {
        lastDarkenedAt = Date()
        Shell.darkenDisplays()
    }

    func setUpClosedLidSupport() {
        do {
            try ClosedLidSupport.install()
            errorMessage = nil
        } catch ClosedLidSupport.SetupError.cancelled {
            // The user closed the password prompt; nothing to report.
        } catch {
            errorMessage = String(localized: "Couldn't set up closed-lid support: \(error.localizedDescription)")
        }
        closedLidSupportReady = ClosedLidSupport.isInstalled()
        tick()
    }

    func removeClosedLidSupport() {
        do {
            try ClosedLidSupport.uninstall()
            errorMessage = nil
        } catch ClosedLidSupport.SetupError.cancelled {
        } catch {
            errorMessage = String(localized: "Couldn't remove closed-lid support: \(error.localizedDescription)")
        }
        closedLidSupportReady = ClosedLidSupport.isInstalled()
        tick()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't change Launch at Login: \(error.localizedDescription)")
        }
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: Presentation

    var menuBarSymbol: String {
        guard settings.isEnabled else { return "moon.zzz" }
        return decision.isKeepingAwake ? "flame.fill" : "flame"
    }

    var statusTitle: String {
        guard settings.isEnabled else { return String(localized: "Ember is off") }
        if decision.stoppedByBatteryFloor, let floor = settings.batteryFloorPercent {
            return String(localized: "Stopped: battery below \(floor.formatted(.percent))")
        }
        return decision.isKeepingAwake
            ? String(localized: "Keeping your Mac awake")
            : String(localized: "Sleeping normally")
    }

    var statusDetail: String {
        var parts = [
            status.powerSource == .ac ? String(localized: "On power") : String(localized: "On battery"),
            status.isLidClosed ? String(localized: "Lid closed") : String(localized: "Lid open"),
            status.externalDisplayCount == 0
                ? String(localized: "No external display")
                : String(localized: "External displays: \(status.externalDisplayCount)"),
        ]
        if let percent = status.batteryPercent {
            parts.append(String(localized: "Battery \(percent.formatted(.percent))"))
        }
        return parts.joined(separator: " · ")
    }
}
