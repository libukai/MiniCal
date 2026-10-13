import SwiftUI
import MiniCalData
struct DayDetailsView: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var data: CalendarDataStore
    let date: Date
    let openSettings: () -> Void
    @UIState private var eventSheet: EventSheet?
    @UIState private var reminderSheet: ReminderSheet?
    @UIState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(date.formatted("M月d日 EEEE")).font(.headline); Text(model.engine.info(for: date).lunarLong).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button("新建事件") { eventSheet = newEventSheet() }; Button("新建提醒事项") { reminderSheet = ReminderSheet(draft: ReminderDraft(dueDate: date)) } } label: { Image(systemName: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("新建事项")
            }
            let annotations = model.engine.info(for: date).annotations
            if !annotations.isEmpty { Text(annotations.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if data.eventAccess != .authorized { permissionRow("日历", state: data.eventAccess) }
                    ForEach(model.events(on: date)) { event in
                        Button { eventSheet = EventSheet(draft: EventDraft(entry: event), hasRecurrence: event.hasRecurrence) } label: {
                            HStack(alignment: .top, spacing: 8) { RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.colorHex)).frame(width: 3); VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.system(size: 13, weight: .medium)); Text(event.isAllDay ? "全天 · \(event.calendarName)" : "\(event.start.formatted("HH:mm"))–\(event.end.formatted("HH:mm")) · \(event.calendarName)").font(.caption).foregroundStyle(.secondary); if let location = event.location, !location.isEmpty { Text(location).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(6).frame(minHeight: 38)
                        }.buttonStyle(.plain).accessibilityLabel("编辑事件 \(event.title)")
                    }
                    if data.eventAccess == .authorized && model.events(on: date).isEmpty { Text("这一天没有日历事件").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6) }
                    if model.settings.config.showReminders {
                        Divider(); Text("提醒事项").font(.caption).foregroundStyle(.secondary)
                        if data.reminderAccess != .authorized { permissionRow("提醒事项", state: data.reminderAccess) }
                        ForEach(model.reminders(on: date)) { r in reminderRow(r) }
                        let unscheduled = data.reminders.filter { !$0.isCompleted && $0.dueDate == nil && !model.settings.config.hiddenCalendarIDs.contains($0.calendarID) }
                        if !unscheduled.isEmpty { Text("未指定日期").font(.caption2).foregroundStyle(.secondary); ForEach(unscheduled) { r in reminderRow(r) } }
                    }
                }
            }.frame(maxHeight: 300)
            HStack { Button("在系统日历中打开") { let seconds = date.timeIntervalSinceReferenceDate; if let url = URL(string: "calshow:\(seconds)") { NSWorkspace.shared.open(url) } }; Spacer(); Button("新建事件") { eventSheet = newEventSheet() }.buttonStyle(.borderedProminent) }.controlSize(.small)
        }
        .padding(16).frame(width: 345)
        .sheet(item: $eventSheet) { payload in EventEditorView(data: data, initial: payload.draft, existingRecurrence: payload.hasRecurrence).id(payload.id) }
        .sheet(item: $reminderSheet) { payload in ReminderEditorView(data: data, initial: payload.draft).id(payload.id) }
        .alert("无法完成操作", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    func newEventSheet() -> EventSheet { EventSheet(draft: EventDraft(start: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date), hasRecurrence: false) }
    func permissionRow(_ title: String, state: AccessState) -> some View {
        HStack { Text("\(title)：\(state.labelString)").font(.caption).foregroundStyle(.secondary); Spacer(); Button("管理权限", action: openSettings).controlSize(.small) }
    }
    func reminderRow(_ r: ReminderEntry) -> some View {
        HStack(alignment: .top) {
            Button { Task { do { try await data.setReminderCompleted(id: r.id, completed: true) } catch { self.error = error.localizedDescription } } } label: { Image(systemName: "circle").foregroundStyle(Color(hex: r.colorHex)) }.buttonStyle(.plain).accessibilityLabel("完成提醒 \(r.title)")
            Button { reminderSheet = ReminderSheet(draft: ReminderDraft(entry: r)) } label: { VStack(alignment: .leading, spacing: 2) { Text(r.title).font(.system(size: 13)); Text(r.calendarName).font(.caption2).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            Spacer()
        }.padding(.vertical, 4)
    }
}

struct EventSheet: Identifiable { let id = UUID(); var draft: EventDraft; var hasRecurrence: Bool }
struct ReminderSheet: Identifiable { let id = UUID(); var draft: ReminderDraft }
