import Combine
import Foundation

enum AppTheme: String, Codable, CaseIterable {
    case system, light, dark
    var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}

struct StatusModule: Identifiable, Codable, Equatable {
    var id: String
    var enabled: Bool
    var format: Int
    var title: String { ["icon": "日历图标", "solar": "公历", "lunar": "农历", "week": "星期", "time": "时间", "custom": "自定义" ][id] ?? id }
}

struct SettingsConfig: Codable {
    var theme: AppTheme = .system
    var hideLunar = false
    var hideFooter = false
    var showEventDots = true
    var showHolidayBadges = true
    var notifyHolidays = false
    var hoverOpen = false
    var animate = true
    var firstWeekday = 2
    var widthScale = 0.5
    var heightScale = 0.5
    var fontScale = 0.5
    var showWeekNumbers = false
    var useISOWeekNumbers = false
    var statusModules: [StatusModule] = ["icon", "solar", "lunar", "week", "time", "custom"].map { StatusModule(id: $0, enabled: $0 == "icon", format: 0) }
    var showSeconds = false
    var timeFormat = 0
    var customFormat = "yyyy-MM-dd"
    var shortcutEnabled = false
    var shortcutKeyCode: UInt32 = 7
    var shortcutModifiers: UInt32 = 4352
    var palette: [String: String] = [:]
    var hiddenCalendarIDs: [String] = []
    var showReminders = true
    var launchAtLogin = false
}

@MainActor final class SettingsStore: ObservableObject {
    static let persistenceKey = "MiniCal.settings.v1"
    @Published var config: SettingsConfig { didSet { persist() } }
    @Published var loginError: String?
    @Published var shortcutError: String?
    @Published var notificationError: String?
    private let inMemory: Bool
    private let defaults: UserDefaults

    init(inMemory: Bool = false, defaults: UserDefaults = .standard, legacySettings: Data? = nil) {
        self.inMemory = inMemory
        self.defaults = defaults
        let existing = inMemory ? nil : defaults.data(forKey: Self.persistenceKey)
        let legacy = inMemory ? nil : (legacySettings ?? (defaults === UserDefaults.standard ? UserDefaults.standard.persistentDomain(forName: "com.libukai.TinyCalARM")?["TinyCalARM.settings.v1"] as? Data : nil))
        let migrating = existing == nil && legacy != nil
        let fallback = SettingsConfig()
        // Merge stored keys into fresh defaults so adding a preference does not
        // discard existing settings. Never read the original TinyCal domain.
        if !inMemory, let stored = (existing ?? legacy),
           let original = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
           let defaultData = try? JSONEncoder().encode(fallback),
           var merged = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any] {
            for (key, value) in original { merged[key] = value }
            if let data = try? JSONSerialization.data(withJSONObject: merged),
               var decoded = try? JSONDecoder().decode(SettingsConfig.self, from: data) {
                decoded.widthScale = Self.clamp(decoded.widthScale)
                decoded.heightScale = Self.clamp(decoded.heightScale)
                decoded.fontScale = Self.clamp(decoded.fontScale)
                if !(1...7).contains(decoded.firstWeekday) { decoded.firstWeekday = 2 }
                let known = Set(fallback.statusModules.map(\.id))
                var seen: Set<String> = []
                decoded.statusModules = decoded.statusModules.filter { known.contains($0.id) && seen.insert($0.id).inserted }
                for item in fallback.statusModules where !seen.contains(item.id) { decoded.statusModules.append(item) }
                if migrating { decoded.launchAtLogin = false; decoded.notifyHolidays = false }
                config = decoded
            } else { config = fallback }
        } else { config = fallback }
        if migrating && !inMemory { persist() }
    }

    var panelWidth: Double { 396 * (0.5 + Self.clamp(config.widthScale)) }
    var panelHeight: Double { 356 * (0.5 + Self.clamp(config.heightScale)) }
    var fontMultiplier: Double { 0.65 + 0.7 * Self.clamp(config.fontScale) }

    func colorHex(for key: String, dark: Bool) -> String {
        if dark, let override = config.palette["dark." + key] { return override }
        if let override = config.palette[key] { return override }
        let shared = ["festival": "#78909c", "today": "#f44336", "holiday": "#4dd0e1", "workday": "#ff8a65", "event": "#9575cd"]
        if let value = shared[key] { return value }
        let colors = dark
            ? ["window": "#394147", "title": "#9e9e9e", "date": "#ffffff", "weekend": "#ffffff8c"]
            : ["window": "#eeeeee", "title": "#757575", "date": "#37474f", "weekend": "#37474f8c"]
        return colors[key] ?? (dark ? "#ffffff" : "#37474f")
    }

    func reset(section: String? = nil) {
        let defaults = SettingsConfig()
        switch section {
        case "general", "通用":
            config.hideLunar = defaults.hideLunar; config.hideFooter = defaults.hideFooter
            config.showEventDots = defaults.showEventDots; config.showHolidayBadges = defaults.showHolidayBadges
            config.notifyHolidays = defaults.notifyHolidays; config.hoverOpen = defaults.hoverOpen
            config.animate = defaults.animate; config.firstWeekday = defaults.firstWeekday
            config.showWeekNumbers = defaults.showWeekNumbers
            config.useISOWeekNumbers = defaults.useISOWeekNumbers; config.launchAtLogin = defaults.launchAtLogin
            config.shortcutEnabled = defaults.shortcutEnabled; config.shortcutKeyCode = defaults.shortcutKeyCode
            config.shortcutModifiers = defaults.shortcutModifiers
            loginError = nil; shortcutError = nil; notificationError = nil
        case "events", "事件":
            config.hiddenCalendarIDs = []; config.showReminders = defaults.showReminders
        case "appearance", "style", "样式":
            config.theme = defaults.theme; config.palette = [:]
            config.widthScale = defaults.widthScale; config.heightScale = defaults.heightScale; config.fontScale = defaults.fontScale
        case "status", "状态栏":
            config.statusModules = defaults.statusModules; config.showSeconds = defaults.showSeconds
            config.timeFormat = defaults.timeFormat; config.customFormat = defaults.customFormat
        default: config = defaults; loginError = nil; shortcutError = nil; notificationError = nil
        }
    }

    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1, max(0.2, value)) : 0.5 }
    private func persist() {
        guard !inMemory, let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
    }
}
