import CoreGraphics
import EmberCore
import Foundation
import IOKit
import IOKit.ps

/// Reads the current power, lid, display and idle state from public macOS APIs.
enum SystemReader {
    static func snapshot() -> SystemSnapshot {
        let (source, percent) = power()
        let displays = onlineDisplays()
        let externalCount = displays.filter { CGDisplayIsBuiltin($0) == 0 }.count
        let allAsleep = displays.allSatisfy { CGDisplayIsAsleep($0) != 0 }
        return SystemSnapshot(
            powerSource: source,
            batteryPercent: percent,
            isLidClosed: isLidClosed(),
            externalDisplayCount: externalCount,
            areDisplaysAsleep: allAsleep,
            secondsSinceUserInput: idleSeconds(),
            isLidSleepDisabled: isLidSleepDisabled()
        )
    }

    /// Current power source and internal battery charge. Anything other than wall power
    /// (battery, UPS) counts as battery, which is the safe side.
    static func power() -> (PowerSource, Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (.ac, nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let source: PowerSource = (providing == nil || providing == kIOPMACPowerKey) ? .ac : .battery

        var percent: Int?
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [AnyObject]? ?? []
        for powerSource in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, powerSource)?
                    .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }
            percent = current * 100 / maximum
        }
        return (source, percent)
    }

    static func isLidClosed() -> Bool {
        rootDomainFlag("AppleClamshellState") ?? false
    }

    /// The system-wide `pmset disablesleep` flag.
    static func isLidSleepDisabled() -> Bool {
        rootDomainFlag("SleepDisabled") ?? false
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func idleSeconds() -> Double {
        guard let value = registryProperty(service: "IOHIDSystem", key: "HIDIdleTime") as? NSNumber else {
            return 0
        }
        return value.doubleValue / 1_000_000_000
    }

    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func rootDomainFlag(_ key: String) -> Bool? {
        switch registryProperty(service: "IOPMrootDomain", key: key) {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        default: nil
        }
    }

    private static func registryProperty(service name: String, key: String) -> Any? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
