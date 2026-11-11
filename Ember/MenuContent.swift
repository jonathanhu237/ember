import EmberCore
import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(model.statusTitle)
        Text(model.statusDetail)
        if model.decision.darkeningNeedsLidSleepDisabled, !model.closedLidSupportReady {
            Text("Displays stay on with the lid closed until closed-lid support is set up.")
        }
        if let error = model.errorMessage {
            Text(error)
        }

        Divider()

        Toggle("Enable Ember", isOn: $model.settings.isEnabled)

        Divider()

        Section("When on Power") {
            ProfileToggles(profile: $model.settings.onPower)
        }

        Section("When on Battery") {
            ProfileToggles(profile: $model.settings.onBattery)
            Menu("Stop on Battery Below") {
                Picker("Stop on Battery Below", selection: $model.settings.batteryFloorPercent) {
                    Text("Off").tag(Int?.none)
                    ForEach([10, 20, 30], id: \.self) { percent in
                        Text(percent.formatted(.percent)).tag(Int?.some(percent))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }

        Divider()

        Button("Turn Displays Off Now") {
            model.darkenDisplaysNow()
        }

        Divider()

        if model.closedLidSupportReady {
            Text("Closed-lid support: ready")
            Button("Remove Closed-Lid Support…") {
                model.removeClosedLidSupport()
            }
        } else {
            Text("Closed-lid support: not set up")
            Text("Needed to turn displays off with the lid closed, and to keep running without an external display.")
            Button("Set Up Closed-Lid Support…") {
                model.setUpClosedLidSupport()
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("Quit Ember") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct ProfileToggles: View {
    @Binding var profile: PowerProfile

    var body: some View {
        Toggle("Keep Mac awake", isOn: $profile.keepAwake)
        Toggle("Keep display on", isOn: $profile.keepDisplayOn)
        Toggle("Keep running with lid closed", isOn: $profile.runWithLidClosed)
        Toggle("Turn displays off when lid closes", isOn: $profile.darkenDisplaysWhenLidClosed)
    }
}
