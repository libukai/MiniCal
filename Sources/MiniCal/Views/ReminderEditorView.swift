import SwiftUI
import MiniCalData
struct ReminderEditorView: View {
    @ObservedObject var data: CalendarDataStore
    @Environment(\.dismiss) private var dismiss
    @UIState private var draft: ReminderDraft
    @UIState private var hasDate: Bool
    @UIState private var error: String?
    @UIState private var removeConfirmation = false
    init(data: CalendarDataStore, initial: ReminderDraft) { self.data = data; var prepared = initial; if prepared.calendarID == nil { prepared.calendarID = data.reminderLists.first(where: \.allowsModifications)?.id }; _draft = UIState(initialValue: prepared); _hasDate = UIState(initialValue: initial.dueDate != nil) }
    var body: some View {
        VStack(spacing: 0) {
            Text(draft.id == nil ? "新建提醒事项" : "编辑提醒事项").font(.headline).padding()
            Form {
                TextField("标题", text: $draft.title)
                Picker("列表", selection: Binding(get: { draft.calendarID ?? data.reminderLists.first(where: \.allowsModifications)?.id ?? "" }, set: { draft.calendarID = $0 })) { ForEach(data.reminderLists.filter(\.allowsModifications)) { Text($0.title).tag($0.id) } }
                Toggle("指定日期", isOn: $hasDate).onChange(of: hasDate) { _, enabled in if enabled && draft.dueDate == nil { draft.dueDate = Date() }; if !enabled { draft.dueDate = nil } }
                if hasDate { DatePicker("到期", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute]) }
                Picker("优先级", selection: $draft.priority) { Text("无").tag(0); Text("高").tag(1); Text("中").tag(5); Text("低").tag(9) }
                TextField("备注", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }), axis: .vertical).lineLimit(3...5)
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { if draft.id != nil { Button("删除", role: .destructive) { removeConfirmation = true } }; Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { Task { do { if !hasDate { draft.dueDate = nil }; try await data.saveReminder(draft); dismiss() } catch { self.error = error.localizedDescription } } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(draft.title.isEmpty) }.padding(16)
        }.frame(width: 420)
        .confirmationDialog("删除提醒事项？", isPresented: $removeConfirmation, titleVisibility: .visible) { Button("删除", role: .destructive) { Task { do { if let id = draft.id { try await data.deleteReminder(id: id) }; dismiss() } catch { self.error = error.localizedDescription } } } }
    }
}
