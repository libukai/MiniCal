import Foundation
import SwiftUI
import WidgetKit
import MiniCalCore

/// This extension calculates only public calendar data. It does not share an
/// application group, inspect the original application's defaults, or use EventKit.
struct MonthEntry: TimelineEntry {
    let date: Date
    let title: String
    let days: [CalendarDay]

    init(date: Date) {
        self.date = date
        let engine = CalendarEngine()
        title = engine.monthTitle(date)
        days = engine.monthDays(containing: date, now: date)
    }
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry {
        MonthEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthEntry) -> Void) {
        completion(MonthEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthEntry>) -> Void) {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let midnight = calendar.startOfDay(for: now)
        // Provide future entries as well as asking for a new timeline. This keeps
        // today's marker and month rollover correct even when reloads are deferred.
        var entries = [MonthEntry(date: now)]
        for offset in 1...7 {
            if let nextMidnight = calendar.date(byAdding: .day, value: offset, to: midnight) {
                entries.append(MonthEntry(date: nextMidnight))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private func calendarURL(_ date: Date) -> URL {
    var components = URLComponents()
    components.scheme = "minical"
    components.host = "show"
    components.queryItems = [URLQueryItem(name: "date", value: String(date.timeIntervalSince1970))]
    // The constant scheme, host and numeric query are always a valid URL.
    return components.url!
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MonthEntry
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private var compact: Bool { family == .systemSmall }
    private var roomy: Bool { family == .systemLarge }

    var body: some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = roomy ? 32 : 19
            let weekdayHeight: CGFloat = roomy ? 19 : 12
            let spacing: CGFloat = roomy ? 5 : 2
            let rowHeight = max(12, (geometry.size.height - headerHeight - weekdayHeight - spacing * 3) / 6)
            VStack(spacing: spacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title)
                        .font(.system(size: compact ? 13 : (roomy ? 21 : 16), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    if !compact {
                        Text("农历")
                            .font(.system(size: roomy ? 11 : 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: headerHeight, alignment: .top)
                .accessibilityAddTraits(.isHeader)

                HStack(spacing: 0) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                        Text(weekday)
                            .font(.system(size: roomy ? 11 : 8, weight: .medium))
                            .foregroundStyle(index >= 5 ? Color.secondary : Color.primary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: weekdayHeight)
                .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                let index = row * 7 + column
                                if index < entry.days.count {
                                    let day = entry.days[index]
                                    if compact {
                                        // WidgetKit gives a small widget one tap
                                        // destination; medium/large support each Link.
                                        cell(day, height: rowHeight)
                                    } else {
                                        Link(destination: calendarURL(day.date)) {
                                            cell(day, height: rowHeight)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
        }
        .widgetURL(calendarURL(entry.date))
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func cell(_ day: CalendarDay, height: CGFloat) -> some View {
        let index = entry.days.firstIndex(where: { $0.id == day.id }) ?? 0
        let weekend = index % 7 >= 5
        let caption = day.calendarLabel
        let color: Color = day.isToday ? .white : (weekend ? .secondary : .primary)
        return Group {
            if family == .systemMedium {
                HStack(spacing: 2) {
                    digits(day, size: 9)
                    Text(caption).font(.system(size: 6.5)).lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                VStack(spacing: roomy ? 3 : 0) {
                    digits(day, size: roomy ? 17 : min(10, height * 0.50))
                    Text(caption)
                        .font(.system(size: roomy ? 10 : min(6, height * 0.28)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: max(10, height - (roomy ? 3 : 1)))
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: roomy ? 9 : 5)
                    .fill(Color.red)
                    .widgetAccentable()
                    .padding(.horizontal, roomy ? 4 : 1)
            }
        }
        .opacity(day.isCurrentMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func digits(_ day: CalendarDay, size: CGFloat) -> some View {
        HStack(spacing: 1) {
            Text(String(day.dayNumber))
                .font(.system(size: size, weight: day.isToday ? .bold : .medium, design: .rounded))
                .monospacedDigit().fixedSize()
            if let marker = day.holiday {
                Text(marker.status == .rest ? "休" : "班")
                    .font(.system(size: roomy ? 8 : 5, weight: .semibold))
            }
        }
    }

    private func accessibilityLabel(_ day: CalendarDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let values = calendar.dateComponents([.year, .month, .day], from: day.date)
        var parts = ["\(values.year ?? 0)年\(values.month ?? 0)月\(values.day ?? 0)日", day.lunarLong]
        if day.isToday { parts.append("今天") }
        if let term = day.solarTerm { parts.append(term) }
        if let festival = day.festival { parts.append(festival) }
        if let holiday = day.holiday { parts.append(holiday.status == .rest ? "休假" : "补班") }
        return parts.joined(separator: "，")
    }
}

struct MiniCalMonthWidget: Widget {
    let kind = "MiniCal.MonthCalendar"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonthProvider()) { entry in
            MonthWidgetView(entry: entry)
        }
        .configurationDisplayName("月历与农历")
        .description("查看月历、农历、节气与休假日期，点击打开日历面板。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct MiniCalWidgetBundle: WidgetBundle {
    var body: some Widget {
        MiniCalMonthWidget()
    }
}
