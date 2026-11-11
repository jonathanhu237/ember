import Foundation
import IOKit.pwr_mgt

/// One IOKit power assertion that can be switched on and off. Visible in `pmset -g assertions`.
@MainActor
final class SleepAssertion {
    static let preventIdleSystemSleep = "PreventUserIdleSystemSleep"
    static let preventIdleDisplaySleep = "PreventUserIdleDisplaySleep"

    private let type: String
    private let reason: String
    private var assertionID: IOPMAssertionID = 0
    private(set) var isHeld = false

    init(type: String, reason: String) {
        self.type = type
        self.reason = reason
    }

    func set(_ held: Bool) {
        guard held != isHeld else { return }
        if held {
            var newID: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &newID
            )
            if result == kIOReturnSuccess {
                assertionID = newID
                isHeld = true
            }
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isHeld = false
        }
    }
}
