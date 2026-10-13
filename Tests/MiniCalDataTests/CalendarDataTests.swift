import Foundation
import Testing
@testable import MiniCalData

@Suite struct CalendarDataTests {
    @Test func testDraftValidationAndExplicitEditFlags() throws {
        #expect(throws: CalendarDataError.emptyTitle) { try EventDraft(title: "  ").validate() }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(throws: CalendarDataError.invalidDateRange) { try EventDraft(title: "bad", start: start, end: start).validate() }
        #expect(throws: CalendarDataError.invalidAlarm) { try EventDraft(title: "bad", alarmMinutes: [-1]).validate() }
        #expect(throws: CalendarDataError.invalidPriority) { try ReminderDraft(title: "bad", priority: 10).validate() }
        let entry = CalendarEntry(id: "existing", title: "existing", start: start, end: start.addingTimeInterval(3600),
                                  calendarID: "calendar", calendarName: "calendar", colorHex: "#112233", hasRecurrence: true, alarmMinutes: [15])
        var draft = EventDraft(entry: entry)
        #expect(!(draft.recurrenceChanged))
        #expect(!(draft.alarmsChanged))
        draft.title = "new title"
        #expect(!(draft.recurrenceChanged))
        draft.recurrence = .none
        draft.alarmMinutes = []
        #expect(draft.recurrenceChanged)
        #expect(draft.alarmsChanged)
        try draft.validate()
        let roundTrip = try JSONDecoder().decode(EventDraft.self, from: JSONEncoder().encode(draft))
        #expect(roundTrip.recurrenceChanged)
    }

    @MainActor
    @Test func testFixtureEventCRUDAndExclusiveRange() async throws {
        let store = CalendarDataStore(useFixtures: true)
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        await store.refresh(from: start, to: start.addingTimeInterval(86400))
        #expect(store.events.isEmpty)
        let before = EventDraft(title: "before", start: start.addingTimeInterval(-3600), end: start)
        try await store.saveEvent(before)
        #expect(store.events.isEmpty , "An event ending exactly at the range start is outside the range")
        try await store.saveEvent(EventDraft(title: "created", start: start, end: start.addingTimeInterval(3600), recurrence: .weekly))
        let entry = try #require(store.events.first)
        #expect(entry.title ==  "created")
        #expect(entry.hasRecurrence)
        var edit = EventDraft(entry: entry)
        edit.title = "updated"
        try await store.saveEvent(edit)
        #expect(try #require(store.events.first).hasRecurrence , "A title edit must preserve recurrence")
        edit.recurrence = .none
        try await store.saveEvent(edit)
        #expect(!(try #require(store.events.first).hasRecurrence))
        try await store.deleteEvent(id: entry.id)
        #expect(store.events.isEmpty)
        do { try await store.deleteEvent(id: entry.id); Issue.record("Expected missing item") }
        catch { #expect(error as? CalendarDataError ==  .itemNotFound) }
    }

    @MainActor
    @Test func testFixtureReminderCRUDAndCalendarDeletion() async throws {
        let store = CalendarDataStore(useFixtures: true)
        try await store.saveReminder(ReminderDraft(title: "created", priority: 1))
        let entry = try #require(store.reminders.first { $0.title == "created" })
        try await store.setReminderCompleted(id: entry.id, completed: true)
        var edit = ReminderDraft(entry: entry); edit.title = "updated"
        try await store.saveReminder(edit)
        #expect(try #require(store.reminders.first { $0.id == entry.id }).isCompleted)
        try await store.deleteReminder(id: entry.id)
        #expect(!(store.reminders.contains { $0.id == entry.id }))
        try await store.createCalendar(title: "import destination")
        let calendar = try #require(store.calendars.first { $0.title == "import destination" })
        try await store.saveEvent(EventDraft(calendarID: calendar.id, title: "delete with calendar"))
        try await store.deleteCalendar(id: calendar.id)
        #expect(!(store.calendars.contains { $0.id == calendar.id }))
        #expect(!(store.events.contains { $0.calendarID == calendar.id }))
        #expect(store.eventAccess ==  .authorized)
    }

    @Test func testICSUnfoldingUTCAllDayAndTimezone() throws {
        let data = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        DTSTART:20261012T010000Z
        DTEND:20261012T020000Z
        SUMMARY:Hello\\, world
         folded
        DESCRIPTION:line 1\\nline 2
        RRULE:FREQ=WEEKLY;INTERVAL=1
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT15M
        END:VALARM
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261013
        SUMMARY:全天
        END:VEVENT
        BEGIN:VEVENT
        DTSTART;TZID=Asia/Shanghai:20261012T090000
        DURATION:PT1H
        SUMMARY:上海时间
        END:VEVENT
        END:VCALENDAR
        """.data(using: .utf8)!
        let entries = try ICSParser.parse(data: data)
        #expect(entries.count ==  3)
        #expect(entries[0].title ==  "Hello, worldfolded")
        #expect(entries[0].notes ==  "line 1\nline 2")
        #expect(entries[0].recurrence ==  .weekly)
        #expect(entries[0].alarmMinutes ==  [15])
        #expect(entries[1].isAllDay)
        #expect(entries[0].start ==  entries[2].start)
        #expect(entries[2].end.timeIntervalSince(entries[2].start) ==  3600)
    }

    @Test func testICSRejectsUnsafeGuessing() {
        let examples = [
            "DTSTART;TZID=Unknown/Zone:20261012T090000\nDTEND:20261012T100000",
            "DTSTART:20260230T090000Z\nDTEND:20261012T100000Z",
            "DTSTART:20261012T090000Z\nDTEND:20261012T100000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE",
            "DTSTART:20261012T090000Z"
        ]
        for example in examples {
            let data = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Test\n\(example)\nEND:VEVENT\nEND:VCALENDAR".data(using: .utf8)!
            #expect(throws: (any Error).self) { try ICSParser.parse(data: data) }
        }
    }

    @MainActor
    @Test func testICSPreviewHasNoSideEffectsAndImportRollsBack() async throws {
        let store = CalendarDataStore(useFixtures: true)
        let data = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:ICS imported\nDTSTART:20261012T090000Z\nDTEND:20261012T100000Z\nEND:VEVENT\nEND:VCALENDAR".data(using: .utf8)!
        let initial = store.events
        _ = try await store.importICS(data: data)
        #expect(store.events ==  initial)
        do { _ = try await store.importICS(data: data, calendarID: "missing", previewOnly: false); Issue.record("Expected unavailable calendar") }
        catch { #expect(error as? CalendarDataError ==  .calendarUnavailable) }
        await store.refresh(from: .distantPast, to: .distantFuture)
        #expect(store.events.count ==  initial.count)
        _ = try await store.importICS(data: data, previewOnly: false)
        #expect(store.events.contains { $0.title == "ICS imported" })
    }

    @MainActor
    @Test func testReadOnlyCalendarRefusesWritesAndDeletes() async throws {
        let store = CalendarDataStore(useFixtures: true)
        let original = try #require(store.events.first)
        let index = try #require(store.calendars.firstIndex { $0.id == original.calendarID })
        store.calendars[index].allowsModifications = false
        do { try await store.deleteEvent(id: original.id); Issue.record("Expected read-only refusal") }
        catch { #expect(error as? CalendarDataError == .readOnlyCalendar) }
        do { try await store.saveEvent(EventDraft(entry: original)); Issue.record("Expected read-only refusal") }
        catch { #expect(error as? CalendarDataError == .readOnlyCalendar) }
        do { try await store.deleteCalendar(id: original.calendarID); Issue.record("Expected read-only refusal") }
        catch { #expect(error as? CalendarDataError == .readOnlyCalendar) }
        #expect(store.events.contains { $0.id == original.id })
    }
}
