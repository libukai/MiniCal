import Foundation

public enum AccessState: String, Codable, Sendable {
    case notDetermined, denied, restricted, writeOnly, authorized
    public var labelString: String {
        switch self {
        case .notDetermined: return "未授权"
        case .denied: return "已拒绝"
        case .restricted: return "系统限制"
        case .writeOnly: return "仅可添加"
        case .authorized: return "已授权"
        }
    }
}

public struct CalendarList: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var colorHex: String
    public var allowsModifications: Bool
    public init(id: String, title: String, colorHex: String, allowsModifications: Bool = true) {
        self.id = id; self.title = title; self.colorHex = colorHex; self.allowsModifications = allowsModifications
    }
}

public struct CalendarEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarName: String
    public var colorHex: String
    public var notes: String?
    public var location: String?
    public var url: URL?
    public var hasRecurrence: Bool
    public var alarmMinutes: [Int]
    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendarID: String, calendarName: String, colorHex: String, notes: String? = nil,
                location: String? = nil, url: URL? = nil, hasRecurrence: Bool = false, alarmMinutes: [Int] = []) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.calendarID = calendarID; self.calendarName = calendarName; self.colorHex = colorHex
        self.notes = notes; self.location = location; self.url = url; self.hasRecurrence = hasRecurrence
        self.alarmMinutes = alarmMinutes
    }
}

public struct ReminderEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var dueDate: Date?
    public var isCompleted: Bool
    public var calendarID: String
    public var calendarName: String
    public var colorHex: String
    public var notes: String?
    public var priority: Int
    public init(id: String, title: String, dueDate: Date? = nil, isCompleted: Bool = false,
                calendarID: String, calendarName: String, colorHex: String, notes: String? = nil, priority: Int = 0) {
        self.id = id; self.title = title; self.dueDate = dueDate; self.isCompleted = isCompleted
        self.calendarID = calendarID; self.calendarName = calendarName; self.colorHex = colorHex
        self.notes = notes; self.priority = priority
    }
}

public enum CalendarDataError: LocalizedError, Equatable {
    case emptyTitle, invalidDateRange, invalidAlarm, invalidPriority, accessRequired(String), calendarUnavailable, readOnlyCalendar, itemNotFound, reminderQueryFailed
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "请输入标题。"
        case .invalidDateRange: return "结束时间必须晚于开始时间。"
        case .invalidAlarm: return "提醒时间必须为 0 至 525600 分钟前。"
        case .invalidPriority: return "提醒事项优先级必须为 0 至 9。"
        case .accessRequired(let kind): return "请在设置中授予\(kind)完整访问权限。"
        case .calendarUnavailable: return "未找到可用的日历或提醒事项列表。"
        case .readOnlyCalendar: return "此日历或列表为只读，无法修改。"
        case .itemNotFound: return "此项目已删除或发生变化，请刷新后重试。"
        case .reminderQueryFailed: return "无法读取提醒事项，请检查权限后重试。"
        }
    }
}

public struct EventDraft: Codable, Sendable {
    public enum Recurrence: String, CaseIterable, Codable, Sendable {
        case none, daily, weekly, monthly, yearly
        public var labelString: String {
            switch self { case .none: return "不重复"; case .daily: return "每天"; case .weekly: return "每周"; case .monthly: return "每月"; case .yearly: return "每年" }
        }
    }
    public var id: String?
    public var calendarID: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var notes: String?
    public var location: String?
    public var url: URL?
    public var alarmMinutes: [Int] { didSet { alarmsChanged = true } }
    /// Editing an existing event keeps its complete rules until the user explicitly changes this field.
    public var recurrence: Recurrence { didSet { recurrenceChanged = true } }
    public var recurrenceChanged: Bool
    public var alarmsChanged: Bool
    public init(id: String? = nil, calendarID: String? = nil, title: String = "", start: Date = Date(),
                end: Date? = nil, isAllDay: Bool = false, notes: String? = nil, location: String? = nil,
                url: URL? = nil, alarmMinutes: [Int] = [], recurrence: Recurrence? = nil) {
        self.id = id; self.calendarID = calendarID; self.title = title; self.start = start
        self.end = end ?? start.addingTimeInterval(3600); self.isAllDay = isAllDay
        self.notes = notes; self.location = location; self.url = url; self.alarmMinutes = alarmMinutes
        self.recurrence = recurrence ?? .none; self.recurrenceChanged = recurrence != nil
        self.alarmsChanged = id == nil
    }
    public init(entry: CalendarEntry) {
        self.init(id: entry.id, calendarID: entry.calendarID, title: entry.title, start: entry.start,
                  end: entry.end, isAllDay: entry.isAllDay, notes: entry.notes, location: entry.location,
                  url: entry.url, alarmMinutes: entry.alarmMinutes)
    }
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarDataError.emptyTitle }
        guard end > start else { throw CalendarDataError.invalidDateRange }
        guard alarmMinutes.allSatisfy({ (0...525600).contains($0) }) else { throw CalendarDataError.invalidAlarm }
    }
}

public struct ReminderDraft: Codable, Sendable {
    public var id: String?
    public var title: String
    public var dueDate: Date?
    public var calendarID: String?
    public var notes: String?
    public var priority: Int
    public init(id: String? = nil, title: String = "", dueDate: Date? = nil, calendarID: String? = nil,
                notes: String? = nil, priority: Int = 0) {
        self.id = id; self.title = title; self.dueDate = dueDate; self.calendarID = calendarID
        self.notes = notes; self.priority = priority
    }
    public init(entry: ReminderEntry) {
        self.init(id: entry.id, title: entry.title, dueDate: entry.dueDate, calendarID: entry.calendarID,
                  notes: entry.notes, priority: entry.priority)
    }
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarDataError.emptyTitle }
        guard (0...9).contains(priority) else { throw CalendarDataError.invalidPriority }
    }
}
