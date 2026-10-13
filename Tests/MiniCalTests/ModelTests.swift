import Testing
import Foundation
import MiniCalCore
import MiniCalData
@testable import MiniCal
@Suite struct ModelTests {
    @Test @MainActor func dailyMarkersRespectExclusiveEndAndFilters() async throws {
        let settings = SettingsStore(inMemory: true), data = CalendarDataStore(useFixtures: true)
        let model = CalendarModel(settings: settings, data: data), calendar = Calendar.current
        let date = CalendarEngine().date(year: 2026, month: 10, day: 5)!
        let end = calendar.date(byAdding: .day, value: 2, to: date)!
        try await data.saveEvent(EventDraft(calendarID: data.calendars.first!.id, title: "跨日边界测试", start: date, end: end, isAllDay: true))
        await data.refresh(from: date, to: calendar.date(byAdding: .day, value: 4, to: date)!)
        #expect(model.events(on: date).contains { $0.title == "跨日边界测试" })
        #expect(model.events(on: calendar.date(byAdding: .day, value: 1, to: date)!).contains { $0.title == "跨日边界测试" })
        #expect(!model.events(on: end).contains { $0.title == "跨日边界测试" })
        let noonAfter = calendar.date(byAdding: .hour, value: 12, to: end)!
        #expect(!model.events(on: noonAfter).contains { $0.title == "跨日边界测试" })
        settings.config.hiddenCalendarIDs = [data.calendars.first!.id]
        #expect(model.events(on: date).isEmpty)
    }
    @Test @MainActor func sectionResetPreservesUnrelatedPreferences() {
        let settings = SettingsStore(inMemory: true)
        settings.config.customFormat = "yyyy MMMM dd"; settings.config.hideLunar = true
        settings.config.theme = .dark; settings.config.widthScale = 0.9
        settings.reset(section: "general")
        #expect(!settings.config.hideLunar)
        #expect(settings.config.customFormat == "yyyy MMMM dd")
        #expect(settings.config.theme == .dark)
        settings.reset(section: "style")
        #expect(settings.config.theme == .system)
        #expect(settings.config.widthScale == 0.5)
        #expect(settings.config.customFormat == "yyyy MMMM dd")
    }
}

@Suite struct RenameMigrationTests {
    @Test @MainActor func legacyPreferencesMigrateWithoutEnablingSystemServices() throws {
        let domain = "minical.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var legacy = SettingsConfig(); legacy.theme = .dark; legacy.customFormat = "HH:mm"
        legacy.launchAtLogin = true; legacy.notifyHolidays = true
        let data = try JSONEncoder().encode(legacy)
        let settings = SettingsStore(defaults: defaults, legacySettings: data)
        #expect(settings.config.theme == .dark)
        #expect(settings.config.customFormat == "HH:mm")
        #expect(!settings.config.launchAtLogin && !settings.config.notifyHolidays)
        #expect(defaults.data(forKey: SettingsStore.persistenceKey) != nil)
    }
    @Test @MainActor func existingMiniCalPreferencesTakePriority() throws {
        let domain = "minical.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var current = SettingsConfig(); current.firstWeekday = 1
        defaults.set(try JSONEncoder().encode(current), forKey: SettingsStore.persistenceKey)
        var legacy = SettingsConfig(); legacy.firstWeekday = 2
        let settings = SettingsStore(defaults: defaults, legacySettings: try JSONEncoder().encode(legacy))
        #expect(settings.config.firstWeekday == 1)
    }
}
