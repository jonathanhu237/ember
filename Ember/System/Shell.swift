import Foundation

/// Runs the few command-line tools Ember needs. Every call is short and finishes at once.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Put every display to sleep. Displays powering the Mac over USB-C keep doing so in standby.
    static func darkenDisplays() {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func sleepSystem() {
        run("/usr/bin/pmset", ["sleepnow"])
    }

    /// Flip `pmset disablesleep` through the narrowly scoped sudoers rule. Never prompts.
    static func setLidSleepDisabled(_ disabled: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]).succeeded
    }

    /// Quote a string for safe use as one `/bin/sh` word.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
