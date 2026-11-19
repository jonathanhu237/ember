import Testing
@testable import EmberCore

@Suite("disablesleep flag ownership")
struct LidSleepFlagTests {
    private func action(
        wanted: Bool,
        isDisabled: Bool,
        ownsFlag: Bool,
        supportInstalled: Bool = true
    ) -> LidSleepFlagAction {
        LidSleepFlag.action(
            wanted: wanted,
            isDisabled: isDisabled,
            ownsFlag: ownsFlag,
            supportInstalled: supportInstalled
        )
    }

    @Test("Wanted and off: turn it on")
    func turnOn() {
        #expect(action(wanted: true, isDisabled: false, ownsFlag: false) == .turnOn)
    }

    @Test("Wanted and already on without a record: claim it so it is turned off later")
    func claimExistingFlag() {
        #expect(action(wanted: true, isDisabled: true, ownsFlag: false) == .claim)
        #expect(action(wanted: true, isDisabled: true, ownsFlag: true) == .none)
    }

    // Regression: the record was lost across a restart while macOS kept the flag on, and the
    // old logic refused to touch a flag it had no record of.
    @Test("Not wanted, flag on, no record: turn it off anyway")
    func turnOffWithoutRecord() {
        #expect(action(wanted: false, isDisabled: true, ownsFlag: false) == .turnOff)
    }

    @Test("Not wanted, record says on but the read says off: turn it off to be sure")
    func turnOffWhenReadDisagrees() {
        #expect(action(wanted: false, isDisabled: false, ownsFlag: true) == .turnOff)
    }

    @Test("Not wanted and nothing on: nothing to do")
    func nothingToDo() {
        #expect(action(wanted: false, isDisabled: false, ownsFlag: false) == .none)
    }

    @Test("Without closed-lid support Ember never runs pmset, only drops a stale record")
    func withoutSupport() {
        #expect(action(wanted: true, isDisabled: false, ownsFlag: false, supportInstalled: false) == .none)
        #expect(action(wanted: false, isDisabled: true, ownsFlag: false, supportInstalled: false) == .none)
        #expect(action(wanted: false, isDisabled: false, ownsFlag: true, supportInstalled: false) == .forget)
    }
}
