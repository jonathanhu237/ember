import AppKit
import Foundation

/// Keeping a Mac running with the lid closed and no external display needs the system-wide
/// `pmset disablesleep` flag, which only root can change. Ember installs:
///
/// 1. A sudoers rule that lets this user run exactly `pmset -a disablesleep 0` and `... 1`
///    without a password, nothing else. Installing and removing it asks for the admin password.
/// 2. A user-level watchdog (launchd agent, no root) that turns the flag back off if Ember
///    stops running while it had the flag on, so a crash never leaves the Mac unable to sleep.
///
/// Ember records that it owns the flag in a marker file; it never resets a flag another tool set.
@MainActor
enum ClosedLidSupport {
    enum SetupError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: String(localized: "Cancelled.")
            case .failed(let message): message
            }
        }
    }

    static let watchdogLabel = "dev.ember.watchdog"

    static var sudoersPath: String { "/etc/sudoers.d/ember-\(getuid())" }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ember", isDirectory: true)
    }

    static var ownershipMarker: URL {
        supportDirectory.appendingPathComponent("lid-sleep-disabled-by-ember")
    }

    static var watchdogPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(watchdogLabel).plist")
    }

    // MARK: Status

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
            && Shell.run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]).succeeded
    }

    static var ownsLidSleepFlag: Bool {
        FileManager.default.fileExists(atPath: ownershipMarker.path)
    }

    static func setOwnsLidSleepFlag(_ owns: Bool) {
        if owns {
            try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: ownershipMarker.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: ownershipMarker)
        }
    }

    // MARK: Install / remove

    static func install() throws {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        let draft = FileManager.default.temporaryDirectory.appendingPathComponent("ember-sudoers-\(UUID().uuidString)")
        do {
            try rule.write(to: draft, atomically: true, encoding: .utf8)
        } catch {
            throw SetupError.failed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: draft) }

        let draftPath = Shell.quote(draft.path)
        let command = "/usr/sbin/visudo -cf \(draftPath) >/dev/null"
            + " && /usr/bin/install -m 0440 -o root -g wheel \(draftPath) \(Shell.quote(sudoersPath))"
        try runAsAdministrator(
            command,
            prompt: String(localized: "Ember needs your password once so it can keep your Mac running with the lid closed.")
        )
        try installWatchdog()
    }

    static func uninstall() throws {
        if ownsLidSleepFlag, SystemReader.isLidSleepDisabled() {
            _ = Shell.setLidSleepDisabled(false)
        }
        setOwnsLidSleepFlag(false)
        removeWatchdog()
        try runAsAdministrator(
            "/bin/rm -f \(Shell.quote(sudoersPath))",
            prompt: String(localized: "Ember needs your password to remove its closed-lid permission.")
        )
    }

    // MARK: Watchdog

    static func installWatchdog() throws {
        let marker = Shell.quote(ownershipMarker.path)
        let script = "if [ -e \(marker) ] && ! /usr/bin/pgrep -x Ember >/dev/null; then"
            + " /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /bin/rm -f \(marker); fi; exit 0"
        let plist: [String: Any] = [
            "Label": watchdogLabel,
            "ProgramArguments": ["/bin/sh", "-c", script],
            "StartInterval": 30,
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(
                at: watchdogPlist.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: watchdogPlist, options: .atomic)
        } catch {
            throw SetupError.failed(error.localizedDescription)
        }
        let domain = "gui/\(getuid())"
        Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(watchdogLabel)"])
        let result = Shell.run("/bin/launchctl", ["bootstrap", domain, watchdogPlist.path])
        guard result.succeeded else {
            throw SetupError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func removeWatchdog() {
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(watchdogLabel)"])
        try? FileManager.default.removeItem(at: watchdogPlist)
    }

    // MARK: Admin prompt

    private static func runAsAdministrator(_ command: String, prompt: String) throws {
        func appleScriptString(_ value: String) -> String {
            "\"" + value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "do shell script \(appleScriptString(command))"
            + " with prompt \(appleScriptString(prompt)) with administrator privileges"
        var errorInfo: NSDictionary?
        NSApp.activate(ignoringOtherApps: true)
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 {
            throw SetupError.cancelled
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? String(localized: "Unknown error.")
        throw SetupError.failed(message)
    }
}
