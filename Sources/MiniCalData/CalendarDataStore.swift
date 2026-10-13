import AppKit
import Combine
import EventKit
import Foundation

@MainActor
public final class CalendarDataStore: ObservableObject {
    @Published public var events: [CalendarEntry] = []
    @Published public var reminders: [ReminderEntry] = []
    @Published public var calendars: [CalendarList] = []
    @Published public var reminderLists: [CalendarList] = []
    @Published public var eventAccess: AccessState
    @Published public var reminderAccess: AccessState
    @Published public var errorMessage: String?
    public let useFixtures: Bool
    private lazy var eventStore = EKEventStore()
    private var observer: NSObjectProtocol?
    private var lastRange: (Date, Date)?
    private var refreshRevision = 0
    private var eventObjects: [String: EKEvent] = [:]
    private var fixtureEvents: [CalendarEntry] = []
    private var fixtureReminders: [ReminderEntry] = []

    public init(useFixtures: Bool = false) {
        self.useFixtures = useFixtures
        eventAccess = useFixtures ? .authorized : Self.accessState(for: .event)
        reminderAccess = useFixtures ? .authorized : Self.accessState(for: .reminder)
        if useFixtures { loadFixtures() }
        else {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let range = self.lastRange else { return }
                    await self.refresh(from: range.0, to: range.1)
                }
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    public func requestEventAccess() async {
        guard !useFixtures else { eventAccess = .authorized; return }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            eventAccess = Self.accessState(for: .event)
            errorMessage = granted ? nil : CalendarDataError.accessRequired("日历").localizedDescription
            if granted { await refreshLastRange() }
        } catch { errorMessage = error.localizedDescription; eventAccess = Self.accessState(for: .event) }
    }

    public func requestReminderAccess() async {
        guard !useFixtures else { reminderAccess = .authorized; return }
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            reminderAccess = Self.accessState(for: .reminder)
            errorMessage = granted ? nil : CalendarDataError.accessRequired("提醒事项").localizedDescription
            if granted { await refreshLastRange() }
        } catch { errorMessage = error.localizedDescription; reminderAccess = Self.accessState(for: .reminder) }
    }

    /// The caller controls the first read; initialization never requests access or reads private items.
    public func refresh(from: Date, to: Date) async {
        guard to > from else { errorMessage = CalendarDataError.invalidDateRange.localizedDescription; return }
        lastRange = (from, to)
        refreshRevision += 1
        let revision = refreshRevision
        errorMessage = nil
        if useFixtures {
            events = fixtureEvents.filter { $0.start < to && $0.end > from }.sorted { $0.start < $1.start }
            reminders = sortedReminders(fixtureReminders)
            return
        }
        eventAccess = Self.accessState(for: .event)
        reminderAccess = Self.accessState(for: .reminder)
        if eventAccess == .authorized {
            calendars = eventStore.calendars(for: .event).map(Self.calendarList)
            let found = eventStore.events(matching: eventStore.predicateForEvents(withStart: from, end: to, calendars: nil))
            eventObjects.removeAll()
            events = found.map { event in
                let entry = Self.entry(event)
                eventObjects[entry.id] = event
                return entry
            }.sorted { $0.start < $1.start }
        } else { calendars = []; events = []; eventObjects = [:] }
        if reminderAccess == .authorized {
            reminderLists = eventStore.calendars(for: .reminder).map(Self.calendarList)
            let predicate = eventStore.predicateForReminders(in: nil)
            let found: [EKReminder]? = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
            }
            guard revision == refreshRevision else { return }
            // Access may have been revoked while the asynchronous query ran.
            reminderAccess = Self.accessState(for: .reminder)
            guard reminderAccess == .authorized else { reminders = []; reminderLists = []; return }
            if let found { reminders = sortedReminders(found.map(Self.entry)) }
            else { reminders = []; errorMessage = CalendarDataError.reminderQueryFailed.localizedDescription }
        } else { reminderLists = []; reminders = [] }
    }

    public func saveEvent(_ draft: EventDraft) async throws {
        do {
            try draft.validate()
            if useFixtures { try saveFixtureEvent(draft) }
            else {
                try requireEventAccess()
                let event: EKEvent
                if let id = draft.id { event = try findEvent(id) }
                else { event = EKEvent(eventStore: eventStore) }
                let calendar = try resolveCalendar(id: draft.calendarID, existing: event.calendar, type: .event)
                event.calendar = calendar
                event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                event.startDate = draft.start; event.endDate = draft.end; event.isAllDay = draft.isAllDay
                event.notes = draft.notes; event.location = draft.location; event.url = draft.url
                if draft.id == nil || draft.alarmsChanged {
                    event.alarms = Array(Set(draft.alarmMinutes)).sorted().map { EKAlarm(relativeOffset: -Double($0) * 60) }
                }
                if draft.id == nil || draft.recurrenceChanged {
                    event.recurrenceRules = Self.recurrenceRule(draft.recurrence).map { [$0] }
                }
                try eventStore.save(event, span: draft.recurrenceChanged && draft.id != nil ? .futureEvents : .thisEvent, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func deleteEvent(id: String, futureOccurrences: Bool = false) async throws {
        do {
            if useFixtures {
                guard let event = fixtureEvents.first(where: { $0.id == id }) else { throw CalendarDataError.itemNotFound }
                _ = try fixtureCalendar(id: event.calendarID, existing: nil, lists: calendars)
                fixtureEvents.removeAll { $0.id == id }
            } else {
                try requireEventAccess()
                let event = try findEvent(id)
                guard event.calendar.allowsContentModifications else { throw CalendarDataError.readOnlyCalendar }
                try eventStore.remove(event, span: futureOccurrences ? .futureEvents : .thisEvent, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func saveReminder(_ draft: ReminderDraft) async throws {
        do {
            try draft.validate()
            if useFixtures { try saveFixtureReminder(draft) }
            else {
                try requireReminderAccess()
                let reminder: EKReminder
                if let id = draft.id { reminder = try findReminder(id) }
                else { reminder = EKReminder(eventStore: eventStore) }
                reminder.calendar = try resolveCalendar(id: draft.calendarID, existing: reminder.calendar, type: .reminder)
                reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                reminder.notes = draft.notes; reminder.priority = draft.priority
                if let due = draft.dueDate {
                    var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                    components.timeZone = TimeZone.current
                    reminder.dueDateComponents = components
                } else { reminder.dueDateComponents = nil }
                try eventStore.save(reminder, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func setReminderCompleted(id: String, completed: Bool) async throws {
        do {
            if useFixtures {
                guard let index = fixtureReminders.firstIndex(where: { $0.id == id }) else { throw CalendarDataError.itemNotFound }
                _ = try fixtureCalendar(id: fixtureReminders[index].calendarID, existing: nil, lists: reminderLists)
                fixtureReminders[index].isCompleted = completed
            } else {
                try requireReminderAccess()
                let reminder = try findReminder(id)
                guard reminder.calendar.allowsContentModifications else { throw CalendarDataError.readOnlyCalendar }
                reminder.isCompleted = completed
                try eventStore.save(reminder, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func deleteReminder(id: String) async throws {
        do {
            if useFixtures {
                guard let reminder = fixtureReminders.first(where: { $0.id == id }) else { throw CalendarDataError.itemNotFound }
                _ = try fixtureCalendar(id: reminder.calendarID, existing: nil, lists: reminderLists)
                fixtureReminders.removeAll { $0.id == id }
            } else {
                try requireReminderAccess()
                let reminder = try findReminder(id)
                guard reminder.calendar.allowsContentModifications else { throw CalendarDataError.readOnlyCalendar }
                try eventStore.remove(reminder, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    public func createCalendar(title: String) async throws {
        do {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw CalendarDataError.emptyTitle }
            if useFixtures {
                calendars.append(CalendarList(id: UUID().uuidString, title: title, colorHex: "#467BEA"))
            } else {
                try requireEventAccess()
                let calendar = EKCalendar(for: .event, eventStore: eventStore)
                guard let source = eventStore.defaultCalendarForNewEvents?.source ?? eventStore.sources.first(where: { $0.sourceType == .local }) else { throw CalendarDataError.calendarUnavailable }
                calendar.source = source; calendar.title = title
                calendar.cgColor = NSColor.systemBlue.cgColor
                try eventStore.saveCalendar(calendar, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    /// Removes a writable event calendar and its contents. The UI must obtain deletion confirmation first.
    public func deleteCalendar(id: String) async throws {
        do {
            if useFixtures {
                let calendar = try fixtureCalendar(id: id, existing: nil, lists: calendars)
                guard calendar.allowsModifications else { throw CalendarDataError.readOnlyCalendar }
                calendars.removeAll { $0.id == id }; fixtureEvents.removeAll { $0.calendarID == id }
            } else {
                try requireEventAccess()
                let calendar = try resolveCalendar(id: id, existing: nil, type: .event)
                try eventStore.removeCalendar(calendar, commit: true)
            }
            await refreshLastRange()
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    /// Parses local bytes only. Passing false is an explicit instruction to save the entire validated import.
    public func importICS(data: Data, calendarID: String? = nil, previewOnly: Bool = true) async throws -> [EventDraft] {
        do {
            let drafts = try ICSParser.parse(data: data, calendarID: calendarID)
            guard !previewOnly else { return drafts }
            if useFixtures {
                let snapshot = fixtureEvents
                do { for draft in drafts { try saveFixtureEvent(draft) } }
                catch { fixtureEvents = snapshot; throw error }
            } else {
                try requireEventAccess()
                let calendar = try resolveCalendar(id: calendarID, existing: nil, type: .event)
                do {
                    for draft in drafts {
                        let event = EKEvent(eventStore: eventStore)
                        event.calendar = calendar; event.title = draft.title
                        event.startDate = draft.start; event.endDate = draft.end; event.isAllDay = draft.isAllDay
                        event.notes = draft.notes; event.location = draft.location; event.url = draft.url
                        event.alarms = draft.alarmMinutes.map { EKAlarm(relativeOffset: -Double($0) * 60) }
                        event.recurrenceRules = Self.recurrenceRule(draft.recurrence).map { [$0] }
                        try eventStore.save(event, span: .thisEvent, commit: false)
                    }
                    try eventStore.commit()
                } catch { eventStore.reset(); throw error }
            }
            await refreshLastRange()
            return drafts
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    private func refreshLastRange() async {
        let range = lastRange ?? (Calendar.current.date(byAdding: .month, value: -1, to: Date())!, Calendar.current.date(byAdding: .month, value: 2, to: Date())!)
        await refresh(from: range.0, to: range.1)
    }
    private func requireEventAccess() throws {
        eventAccess = Self.accessState(for: .event)
        guard eventAccess == .authorized else { throw CalendarDataError.accessRequired("日历") }
    }
    private func requireReminderAccess() throws {
        reminderAccess = Self.accessState(for: .reminder)
        guard reminderAccess == .authorized else { throw CalendarDataError.accessRequired("提醒事项") }
    }
    private func findEvent(_ id: String) throws -> EKEvent {
        if let event = eventObjects[id], event.refresh() { return event }
        // Repeating occurrences use a composite display ID; never fall back to the first occurrence.
        if !id.contains("|occurrence|") , let event = eventStore.event(withIdentifier: id) { return event }
        throw CalendarDataError.itemNotFound
    }
    private func findReminder(_ id: String) throws -> EKReminder {
        guard let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { throw CalendarDataError.itemNotFound }
        return item
    }
    private func resolveCalendar(id: String?, existing: EKCalendar?, type: EKEntityType) throws -> EKCalendar {
        let calendar: EKCalendar?
        if let id { calendar = eventStore.calendar(withIdentifier: id) }
        else { calendar = existing ?? (type == .event ? eventStore.defaultCalendarForNewEvents : eventStore.defaultCalendarForNewReminders()) }
        guard let calendar, calendar.allowedEntityTypes.contains(type == .event ? .event : .reminder) else { throw CalendarDataError.calendarUnavailable }
        guard calendar.allowsContentModifications else { throw CalendarDataError.readOnlyCalendar }
        return calendar
    }
    private static func accessState(for type: EKEntityType) -> AccessState {
        switch EKEventStore.authorizationStatus(for: type) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .writeOnly: return .writeOnly
        case .fullAccess: return .authorized
        @unknown default: return .restricted
        }
    }
    private static func calendarList(_ calendar: EKCalendar) -> CalendarList {
        CalendarList(id: calendar.calendarIdentifier, title: calendar.title, colorHex: colorHex(calendar), allowsModifications: calendar.allowsContentModifications)
    }
    private static func colorHex(_ calendar: EKCalendar) -> String {
        let color = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.deviceRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    private static func entry(_ event: EKEvent) -> CalendarEntry {
        let recurring = event.hasRecurrenceRules
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let id = recurring ? identifier + "|occurrence|" + String(event.startDate.timeIntervalSince1970) : identifier
        return CalendarEntry(id: id, title: event.title ?? "无标题", start: event.startDate, end: event.endDate,
                             isAllDay: event.isAllDay, calendarID: event.calendar.calendarIdentifier,
                             calendarName: event.calendar.title, colorHex: colorHex(event.calendar), notes: event.notes,
                             location: event.location, url: event.url, hasRecurrence: recurring,
                             alarmMinutes: (event.alarms ?? []).compactMap { $0.absoluteDate == nil && $0.relativeOffset <= 0 ? Int(-$0.relativeOffset / 60) : nil })
    }
    private static func entry(_ reminder: EKReminder) -> ReminderEntry {
        let due = reminder.dueDateComponents.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) }
        return ReminderEntry(id: reminder.calendarItemIdentifier, title: reminder.title ?? "无标题", dueDate: due,
                             isCompleted: reminder.isCompleted, calendarID: reminder.calendar.calendarIdentifier,
                             calendarName: reminder.calendar.title, colorHex: colorHex(reminder.calendar),
                             notes: reminder.notes, priority: reminder.priority)
    }
    private static func recurrenceRule(_ recurrence: EventDraft.Recurrence) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch recurrence { case .none: return nil; case .daily: frequency = .daily; case .weekly: frequency = .weekly; case .monthly: frequency = .monthly; case .yearly: frequency = .yearly }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
    }
    private func sortedReminders(_ entries: [ReminderEntry]) -> [ReminderEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
    }

    private func loadFixtures() {
        calendars = [CalendarList(id: "fixture-work", title: "工作 · 演示", colorHex: "#467BEA"), CalendarList(id: "fixture-personal", title: "生活 · 演示", colorHex: "#E69E32")]
        reminderLists = [CalendarList(id: "fixture-tasks", title: "提醒事项 · 演示", colorHex: "#AF63D6")]
        let today = Calendar.current.startOfDay(for: Date())
        fixtureEvents = [
            CalendarEntry(id: "fixture-meeting", title: "产品讨论", start: today.addingTimeInterval(10 * 3600), end: today.addingTimeInterval(11 * 3600), calendarID: "fixture-work", calendarName: calendars[0].title, colorHex: calendars[0].colorHex, notes: "这些是虚拟数据，不读取或写入系统日历。", location: "会议室", alarmMinutes: [15]),
            CalendarEntry(id: "fixture-walk", title: "傍晚散步", start: today.addingTimeInterval(18 * 3600), end: today.addingTimeInterval(19 * 3600), calendarID: "fixture-personal", calendarName: calendars[1].title, colorHex: calendars[1].colorHex),
            CalendarEntry(id: "fixture-all-day", title: "阅读日", start: today.addingTimeInterval(86400), end: today.addingTimeInterval(172800), isAllDay: true, calendarID: "fixture-personal", calendarName: calendars[1].title, colorHex: calendars[1].colorHex)
        ]
        fixtureReminders = [
            ReminderEntry(id: "fixture-review", title: "整理本周计划", dueDate: today.addingTimeInterval(17 * 3600), calendarID: "fixture-tasks", calendarName: reminderLists[0].title, colorHex: reminderLists[0].colorHex, priority: 1),
            ReminderEntry(id: "fixture-book", title: "读完一章书", calendarID: "fixture-tasks", calendarName: reminderLists[0].title, colorHex: reminderLists[0].colorHex),
            ReminderEntry(id: "fixture-done", title: "完成环境检查", isCompleted: true, calendarID: "fixture-tasks", calendarName: reminderLists[0].title, colorHex: reminderLists[0].colorHex)
        ]
        events = fixtureEvents; reminders = fixtureReminders
    }
    private func fixtureCalendar(id: String?, existing: String?, lists: [CalendarList]) throws -> CalendarList {
        guard let calendar = lists.first(where: { $0.id == (id ?? existing ?? lists.first?.id) }) else { throw CalendarDataError.calendarUnavailable }
        guard calendar.allowsModifications else { throw CalendarDataError.readOnlyCalendar }
        return calendar
    }
    private func saveFixtureEvent(_ draft: EventDraft) throws {
        let previous = draft.id.flatMap { id in fixtureEvents.first { $0.id == id } }
        if draft.id != nil && previous == nil { throw CalendarDataError.itemNotFound }
        let calendar = try fixtureCalendar(id: draft.calendarID, existing: previous?.calendarID, lists: calendars)
        let entry = CalendarEntry(id: draft.id ?? UUID().uuidString, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  start: draft.start, end: draft.end, isAllDay: draft.isAllDay, calendarID: calendar.id,
                                  calendarName: calendar.title, colorHex: calendar.colorHex, notes: draft.notes,
                                  location: draft.location, url: draft.url,
                                  hasRecurrence: draft.recurrenceChanged || previous == nil ? draft.recurrence != .none : previous!.hasRecurrence,
                                  alarmMinutes: draft.alarmsChanged || previous == nil ? Array(Set(draft.alarmMinutes)).sorted() : previous!.alarmMinutes)
        fixtureEvents.removeAll { $0.id == entry.id }; fixtureEvents.append(entry)
    }
    private func saveFixtureReminder(_ draft: ReminderDraft) throws {
        let previous = draft.id.flatMap { id in fixtureReminders.first { $0.id == id } }
        if draft.id != nil && previous == nil { throw CalendarDataError.itemNotFound }
        let calendar = try fixtureCalendar(id: draft.calendarID, existing: previous?.calendarID, lists: reminderLists)
        let entry = ReminderEntry(id: draft.id ?? UUID().uuidString, title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  dueDate: draft.dueDate, isCompleted: previous?.isCompleted ?? false, calendarID: calendar.id,
                                  calendarName: calendar.title, colorHex: calendar.colorHex, notes: draft.notes, priority: draft.priority)
        fixtureReminders.removeAll { $0.id == entry.id }; fixtureReminders.append(entry)
    }
}
