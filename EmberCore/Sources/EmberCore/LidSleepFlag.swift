/// What to do with the system-wide `pmset disablesleep` flag on this tick.
public enum LidSleepFlagAction: Equatable, Sendable {
    case none
    /// Run `pmset -a disablesleep 1`, then record that Ember owns the flag.
    case turnOn
    /// Run `pmset -a disablesleep 0`, then forget the ownership record.
    case turnOff
    /// The flag is already on: record that Ember owns it, so it gets turned off later.
    case claim
    /// The flag is off but a stale ownership record says otherwise: drop the record.
    case forget
}

/// Keeps the `disablesleep` flag in line with what the policy wants.
///
/// While closed-lid support is installed, Ember owns the flag outright. It does not trust its
/// own record of having set it: the record and the real flag can disagree, for example after
/// a restart where macOS restored the flag while Ember's record was already cleared. Trusting
/// the record left a Mac unable to sleep with its lid closed on battery.
public enum LidSleepFlag {
    public static func action(
        wanted: Bool,
        isDisabled: Bool,
        ownsFlag: Bool,
        supportInstalled: Bool
    ) -> LidSleepFlagAction {
        guard supportInstalled else {
            // Without the sudoers rule Ember cannot change the flag at all.
            return ownsFlag && !isDisabled ? .forget : .none
        }
        if wanted {
            if !isDisabled { return .turnOn }
            return ownsFlag ? .none : .claim
        }
        // Not wanted. Turn it off if it is on, whoever set it, and also when only the record
        // says it is on, in case the read is the one that is wrong. Turning it off is idempotent.
        return isDisabled || ownsFlag ? .turnOff : .none
    }
}
