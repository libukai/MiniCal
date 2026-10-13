import SwiftUI
import MiniCalData
struct EventEditorView: View {
    @ObservedObject var data: CalendarDataStore
    let existingRecurrence: Bool
    @Environment(\.dismiss) private var dismiss
    @UIState private var draft: EventDraft
    @UIState private var urlText: String
    @UIState private var error: String?
    @UIState private var deleteConfirmation = false
    @UIState private var saving = false
    init(data: CalendarDataStore, initial: EventDraft, existingRecurrence: Bool = false) {
        self.data = data; self.existingRecurrence = existingRecurrence; var prepared = initial; if prepared.calendarID == nil { prepared.calendarID = data.calendars.first(where: \.allowsModifications)?.id }; _draft = UIState(initialValue: prepared); _urlText = UIState(initialValue: initial.url?.absoluteString ?? "")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(draft.id == nil ? "新建事件" : "编辑事件").font(.headline); Spacer(); if data.eventAccess != .authorized { Text(data.eventAccess.labelString).font(.caption).foregroundStyle(.secondary) } }.padding(18)
            Form {
                TextField("标题", text: $draft.title).accessibilityIdentifier("event-title")
                Picker("日历", selection: Binding(get: { draft.calendarID ?? data.calendars.first(where: \.allowsModifications)?.id ?? "" }, set: { draft.calendarID = $0 })) { ForEach(data.calendars.filter(\.allowsModifications)) { c in Text(c.title).tag(c.id) } }
                Toggle("全天", isOn: $draft.isAllDay).onChange(of: draft.isAllDay) { _, allDay in if allDay { draft.start = Calendar.current.startOfDay(for: draft.start); draft.end = Calendar.current.date(byAdding: .day, value: 1, to: draft.start)! } }
                DatePicker("开始", selection: $draft.start, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                if draft.isAllDay {
                    DatePicker("结束（包含当天）", selection: Binding(get: { Calendar.current.date(byAdding: .day, value: -1, to: draft.end)! }, set: { draft.end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0))! }), displayedComponents: .date)
                } else { DatePicker("结束", selection: $draft.end, displayedComponents: [.date, .hourAndMinute]) }
                TextField("地点", text: Binding(get: { draft.location ?? "" }, set: { draft.location = $0.isEmpty ? nil : $0 }))
                TextField("链接", text: $urlText)
                Picker("重复", selection: Binding(get: { existingRecurrence && !draft.recurrenceChanged ? "keep" : draft.recurrence.rawValue }, set: { choice in if choice == "keep" { draft.recurrenceChanged = false } else if let value = EventDraft.Recurrence(rawValue: choice) { draft.recurrence = value } })) { if existingRecurrence { Text("保留现有重复规则").tag("keep") }; ForEach(EventDraft.Recurrence.allCases, id: \.self) { Text($0.labelString).tag($0.rawValue) } }
                if existingRecurrence && !draft.recurrenceChanged { Text("保留原事件的完整重复规则；更改此选项才会替换规则。").font(.caption).foregroundStyle(.secondary) }
                Picker("提醒", selection: Binding(get: { draft.alarmMinutes.first ?? -1 }, set: { draft.alarmMinutes = $0 < 0 ? [] : [$0] })) { Text("无").tag(-1); Text("事件开始时").tag(0); Text("提前5分钟").tag(5); Text("提前15分钟").tag(15); Text("提前30分钟").tag(30); Text("提前1小时").tag(60); Text("提前1天").tag(1440) }
                if !draft.alarmsChanged && draft.id != nil { Text("未修改提醒时，保留原事件的全部提醒。").font(.caption).foregroundStyle(.secondary) }
                TextField("备注", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...5)
            }.formStyle(.grouped).frame(maxHeight: 540)
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                if draft.id != nil { Button("删除", role: .destructive) { deleteConfirmation = true } }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "保存中…" : "保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }.frame(width: 460)
        .confirmationDialog("删除此事件？", isPresented: $deleteConfirmation, titleVisibility: .visible) { Button(existingRecurrence ? "只删除这一次" : "删除事件", role: .destructive) { remove(false) }; if existingRecurrence { Button("删除本次及未来重复事件", role: .destructive) { remove(true) } } } message: { Text("此操作会同步到所选系统日历。") }
    }
    func save() {
        saving = true; error = nil
        Task { do {
            let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { guard let url = URL(string: text), let scheme = url.scheme, ["http","https","mailto","tel"].contains(scheme.lowercased()) else { throw EditorError.invalidURL }; draft.url = url } else { draft.url = nil }
            try await data.saveEvent(draft); dismiss()
        } catch { self.error = error.localizedDescription; saving = false } }
    }
    func remove(_ future: Bool) { Task { do { if let id = draft.id { try await data.deleteEvent(id: id, futureOccurrences: future) }; dismiss() } catch { self.error = error.localizedDescription } } }
}
enum EditorError: LocalizedError { case invalidURL; var errorDescription: String? { "请输入有效的网页、邮件或电话链接。" } }
