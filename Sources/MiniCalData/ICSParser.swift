import Foundation

public struct ICSImportError: LocalizedError, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var errorDescription: String? { "ICS 导入失败：" + reason }
}

/// Deliberately strict: unsupported recurrence or time-zone definitions are reported instead of flattened.
public enum ICSParser {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }
    public static func parse(data: Data, calendarID: String? = nil) throws -> [EventDraft] {
        guard let text = String(data: data, encoding: .utf8) else { throw ICSImportError("文件不是 UTF-8 文本。") }
        guard data.count <= 10_000_000 else { throw ICSImportError("文件过大。") }
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var lines: [String] = []
        for line in raw {
            if line.first == " " || line.first == "\t" {
                guard !lines.isEmpty else { throw ICSImportError("折叠行缺少前一行。") }
                lines[lines.count - 1] += line.dropFirst()
            } else if !line.isEmpty { lines.append(line) }
        }
        guard lines.first?.uppercased() == "BEGIN:VCALENDAR", lines.last?.uppercased() == "END:VCALENDAR" else { throw ICSImportError("缺少完整的 VCALENDAR 包装。") }
        var events: [EventDraft] = []
        var properties: [Property] = []
        var alarms: [Int] = []
        var stack = ["VCALENDAR"]
        var alarmProperties: [Property] = []
        for line in lines.dropFirst().dropLast() {
            let property = try parseProperty(line)
            if property.name == "BEGIN" {
                let component = property.value.uppercased()
                if component == "VEVENT" && stack == ["VCALENDAR"] { properties = []; alarms = [] }
                else if component == "VALARM" && stack.last == "VEVENT" { alarmProperties = [] }
                else if component == "VTIMEZONE" && stack == ["VCALENDAR"] { }
                else if stack.contains("VTIMEZONE") { }
                else { throw ICSImportError("不支持的组件：\(component)。") }
                stack.append(component)
            } else if property.name == "END" {
                guard stack.last == property.value.uppercased(), stack.count > 1 else { throw ICSImportError("组件嵌套不完整。") }
                if stack.last == "VALARM" { alarms.append(try alarmMinutes(alarmProperties)) }
                if stack.last == "VEVENT" { events.append(try event(properties, alarms: alarms, calendarID: calendarID)) }
                stack.removeLast()
            } else if stack.last == "VEVENT" { properties.append(property) }
            else if stack.last == "VALARM" { alarmProperties.append(property) }
        }
        guard stack == ["VCALENDAR"], !events.isEmpty else { throw ICSImportError("没有完整的日程项目。") }
        return events
    }
    private static func parseProperty(_ line: String) throws -> Property {
        var quoted = false
        var separator: String.Index?
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == ":" && !quoted { separator = index; break }
        }
        guard let separator else { throw ICSImportError("存在无效属性行。") }
        let left = line[..<separator].components(separatedBy: ";")
        guard let name = left.first, !name.isEmpty else { throw ICSImportError("属性名为空。") }
        var parameters: [String: String] = [:]
        for part in left.dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { throw ICSImportError("属性参数无效。") }
            parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: name.uppercased(), parameters: parameters, value: String(line[line.index(after: separator)...]))
    }
    private static func single(_ name: String, in properties: [Property]) throws -> Property? {
        let found = properties.filter { $0.name == name }
        guard found.count <= 1 else { throw ICSImportError("\(name) 重复出现。") }
        return found.first
    }
    private static func event(_ properties: [Property], alarms: [Int], calendarID: String?) throws -> EventDraft {
        for name in ["EXDATE", "RDATE", "EXRULE", "RECURRENCE-ID", "ATTENDEE", "ORGANIZER"] where properties.contains(where: { $0.name == name }) {
            throw ICSImportError("此导入包含尚不支持的 \(name)，无法无损导入。")
        }
        if let status = try single("STATUS", in: properties), status.value.uppercased() == "CANCELLED" {
            throw ICSImportError("日程已取消，不能作为新日程导入。")
        }
        guard let startProperty = try single("DTSTART", in: properties) else { throw ICSImportError("日程缺少开始日期。") }
        let start = try date(startProperty)
        let allDay = startProperty.parameters["VALUE"]?.uppercased() == "DATE" || startProperty.value.count == 8
        let end: Date
        let endProperty = try single("DTEND", in: properties)
        let duration = try single("DURATION", in: properties)
        guard endProperty == nil || duration == nil else { throw ICSImportError("DTEND 与 DURATION 不能同时出现。") }
        if let endProperty {
            let endAllDay = endProperty.parameters["VALUE"]?.uppercased() == "DATE" || endProperty.value.count == 8
            guard endAllDay == allDay else { throw ICSImportError("起止日期类型不一致。") }
            end = try date(endProperty)
        } else if let duration {
            if allDay && duration.value.contains("T") { throw ICSImportError("全天日程的时长必须按天或周指定。") }
            end = try adding(duration: duration.value, to: start, timezone: timezone(startProperty))
        } else if allDay {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try timezone(startProperty)
            guard let value = calendar.date(byAdding: .day, value: 1, to: start) else { throw ICSImportError("全天日期无法计算。") }
            end = value
        } else { throw ICSImportError("带时间的日程缺少结束日期或时长。") }
        let title = try single("SUMMARY", in: properties).map { try unescape($0.value) } ?? "无标题"
        let notes = try single("DESCRIPTION", in: properties).map { try unescape($0.value) }
        let location = try single("LOCATION", in: properties).map { try unescape($0.value) }
        let url: URL?
        if let value = try single("URL", in: properties)?.value {
            guard let parsed = URL(string: value), parsed.scheme != nil else { throw ICSImportError("URL 无效。") }
            url = parsed
        } else { url = nil }
        let recurrence = try single("RRULE", in: properties).map { try recurrence($0.value) } ?? .none
        let draft = EventDraft(calendarID: calendarID, title: title, start: start, end: end, isAllDay: allDay,
                               notes: notes, location: location, url: url, alarmMinutes: alarms, recurrence: recurrence)
        try draft.validate()
        return draft
    }
    private static func timezone(_ property: Property) throws -> TimeZone {
        if property.value.hasSuffix("Z") {
            guard property.parameters["TZID"] == nil else { throw ICSImportError("UTC 日期不能同时指定 TZID。") }
            return TimeZone(secondsFromGMT: 0)!
        }
        if let name = property.parameters["TZID"] {
            guard let zone = TimeZone(identifier: name) else { throw ICSImportError("不识别的时区：\(name)。") }
            return zone
        }
        return .current
    }
    private static func date(_ property: Property) throws -> Date {
        if let value = property.parameters["VALUE"], !["DATE", "DATE-TIME"].contains(value.uppercased()) {
            throw ICSImportError("不支持的日期类型：\(value)。")
        }
        let isDate = property.parameters["VALUE"]?.uppercased() == "DATE" || property.value.count == 8
        let format = isDate ? "yyyyMMdd" : property.value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = try timezone(property)
        formatter.dateFormat = format; formatter.isLenient = false
        guard let parsed = formatter.date(from: property.value), formatter.string(from: parsed) == property.value else { throw ICSImportError("日期无效：\(property.value)。") }
        return parsed
    }
    private static func durationComponents(_ string: String) throws -> DateComponents {
        guard string.first == "P" else { throw ICSImportError("不支持的时长：\(string)。") }
        var number = "", inTime = false, components = DateComponents(), fields = Set<Character>(), lastOrder = -1
        for char in string.dropFirst() {
            if char.isNumber { number.append(char); continue }
            if char == "T", !inTime, number.isEmpty { inTime = true; continue }
            guard let value = Int(number), !fields.contains(char), value <= 5_256_000 else { throw ICSImportError("时长无效。") }
            let order: Int
            switch char { case "W": order = 0; case "D": order = 1; case "H": order = 2; case "M": order = 3; case "S": order = 4; default: throw ICSImportError("时长单位不支持。") }
            guard order > lastOrder else { throw ICSImportError("时长单位顺序无效。") }
            lastOrder = order
            fields.insert(char); number = ""
            switch char {
            case "W" where !inTime: components.day = value * 7
            case "D" where !inTime: components.day = value
            case "H" where inTime: components.hour = value
            case "M" where inTime: components.minute = value
            case "S" where inTime: components.second = value
            default: throw ICSImportError("时长单位不支持。")
            }
        }
        guard number.isEmpty, !fields.isEmpty, string.last != "T", !(fields.contains("W") && fields.count > 1) else { throw ICSImportError("时长无效。") }
        return components
    }
    private static func adding(duration: String, to date: Date, timezone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
        guard let result = calendar.date(byAdding: try durationComponents(duration), to: date) else { throw ICSImportError("时长无法计算。") }
        return result
    }
    private static func recurrence(_ string: String) throws -> EventDraft.Recurrence {
        var dictionary: [String: String] = [:]
        for item in string.uppercased().split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, dictionary[String(pair[0])] == nil else { throw ICSImportError("重复规则无效。") }
            dictionary[String(pair[0])] = String(pair[1])
        }
        guard Set(dictionary.keys).isSubset(of: ["FREQ", "INTERVAL"]), dictionary["INTERVAL"] == nil || dictionary["INTERVAL"] == "1",
              let frequency = dictionary["FREQ"], let result = EventDraft.Recurrence(rawValue: frequency.lowercased()), result != .none else {
            throw ICSImportError("复杂重复规则无法无损转换，请使用系统日历导入。")
        }
        return result
    }
    private static func alarmMinutes(_ properties: [Property]) throws -> Int {
        guard !properties.contains(where: { ["REPEAT", "DURATION", "ATTACH"].contains($0.name) }) else {
            throw ICSImportError("不支持重复或附加动作的提醒。")
        }
        guard let trigger = try single("TRIGGER", in: properties), trigger.parameters["RELATED"] == nil || trigger.parameters["RELATED"] == "START",
              trigger.value.hasPrefix("-P"), try single("ACTION", in: properties)?.value.uppercased() == "DISPLAY" else {
            throw ICSImportError("仅支持开始前的显示提醒。")
        }
        let components = try durationComponents(String(trigger.value.dropFirst()))
        let seconds = (components.day ?? 0) * 86400 + (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
        guard seconds % 60 == 0, seconds / 60 <= 525600 else { throw ICSImportError("提醒时间无法按分钟表示。") }
        return seconds / 60
    }
    private static func unescape(_ text: String) throws -> String {
        var result = "", escaping = false
        for char in text {
            if escaping {
                guard ["n", "N", ",", ";", "\\"].contains(char) else { throw ICSImportError("文本转义无效。") }
                result.append(char == "n" || char == "N" ? "\n" : char); escaping = false
            }
            else if char == "\\" { escaping = true }
            else { result.append(char) }
        }
        guard !escaping else { throw ICSImportError("文本转义不完整。") }
        return result
    }
}
