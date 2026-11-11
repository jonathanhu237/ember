import EmberCore
import Foundation

enum SettingsStore {
    private static let key = "settings.v1"

    static func load() -> EmberSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let settings = try? JSONDecoder().decode(EmberSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: EmberSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
