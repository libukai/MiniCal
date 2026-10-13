import AppKit
import MiniCalData
@main struct MiniCalMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let fixtures = CommandLine.arguments.contains("--fixtures")
        let settings = SettingsStore(inMemory: fixtures)
        let data = CalendarDataStore(useFixtures: fixtures)
        let model = CalendarModel(settings: settings, data: data)
        let delegate = AppDelegate(settings: settings, model: model, data: data, fixtures: fixtures)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
