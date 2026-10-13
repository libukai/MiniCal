import SwiftUI
import MiniCalCore
import MiniCalData
@MainActor final class CalendarModel: ObservableObject {
    @Published var month = Date()
    @Published var selection = Calendar.current.startOfDay(for: Date())
    @Published var showDetails = false
    @Published var jumpPresented = false
    @Published var pinned = false
    let settings: SettingsStore
    let data: CalendarDataStore
    var engine: CalendarEngine { CalendarEngine(firstWeekday: settings.config.firstWeekday) }
    init(settings: SettingsStore, data: CalendarDataStore) { self.settings = settings; self.data = data }
    func moveMonth(_ offset: Int) { month = engine.movingMonth(month, by: offset); Task { await refresh() } }
    func select(_ date: Date, details: Bool = true) { selection = Calendar.current.startOfDay(for: date); showDetails = details }
    func today() { month = Date(); select(Date(), details: false); Task { await refresh() } }
    func go(to date: Date) { month = date; select(date, details: false); Task { await refresh() } }
    func refresh() async {
        let days = engine.monthDays(containing: month)
        guard let from = days.first?.date, let last = days.last?.date, let to = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        await data.refresh(from: from, to: to)
    }
    func events(on date: Date) -> [CalendarEntry] {
        let start = Calendar.current.startOfDay(for: date), end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return data.events.filter { !settings.config.hiddenCalendarIDs.contains($0.calendarID) && $0.start < end && $0.end > start }
    }
    func reminders(on date: Date) -> [ReminderEntry] {
        guard settings.config.showReminders else { return [] }
        return data.reminders.filter { !$0.isCompleted && !settings.config.hiddenCalendarIDs.contains($0.calendarID) && ($0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false) }
    }
}
