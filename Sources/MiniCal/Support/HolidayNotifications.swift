import Foundation
import UserNotifications
import MiniCalCore
@MainActor final class HolidayNotifications {
    static func setEnabled(_ enabled: Bool) async throws {
        let center = UNUserNotificationCenter.current()
        if !enabled {
            let own = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("minical.holiday.") }
            center.removePendingNotificationRequests(withIdentifiers: own)
            return
        }
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw NotificationFailure.denied }
        try await schedule()
    }
    static func refreshIfAuthorized() async {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        try? await schedule()
    }
    private static func schedule() async throws {
        let center = UNUserNotificationCenter.current(), calendar = Calendar.current, engine = CalendarEngine()
        let now = Date()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("minical.holiday.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for offset in 0..<366 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now),
                  let holiday = engine.info(for: date).holiday, holiday.status == .rest,
                  let previous = calendar.date(byAdding: .day, value: -1, to: date) else { continue }
            let previousHoliday = engine.info(for: previous).holiday
            guard previousHoliday?.name != holiday.name || previousHoliday?.status != .rest else { continue }
            var components = calendar.dateComponents([.year,.month,.day], from: date); components.hour = 8; components.minute = 0
            guard let fire = calendar.date(from: components), fire > now else { continue }
            let content = UNMutableNotificationContent(); content.title = "\(holiday.name)假期开始"; content.body = "祝你假期愉快。打开MiniCal查看日程。"; content.sound = .default
            let request = UNNotificationRequest(identifier: "minical.holiday.\(date.formatted("yyyy-MM-dd"))", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
        }
    }
}
enum NotificationFailure: LocalizedError {
    case denied
    var errorDescription: String? { "通知权限未授权。可以在系统设置的通知页面中为MiniCal 启用。" }
}
