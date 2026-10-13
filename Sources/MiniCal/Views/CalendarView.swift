import SwiftUI
import MiniCalCore
import MiniCalData
struct CalendarView: View {
    @ObservedObject var model: CalendarModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var data: CalendarDataStore
    let openSettings: () -> Void
    let close: () -> Void
    let pin: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @UIState private var jumpDate = Date()
    @UIState private var hoverDate: Date?
    var dark: Bool { settings.config.theme == .dark || (settings.config.theme == .system && colorScheme == .dark) }
    func color(_ key: String) -> Color { Color(hex: settings.colorHex(for: key, dark: dark)) }
    var body: some View {
        let days = model.engine.monthDays(containing: model.month)
        VStack(spacing: 0) {
            HStack {
                Button { model.moveMonth(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? -12 : -1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 28) }.help("上一月（←），Shift 点击上一年").accessibilityLabel("上一月")
                Spacer()
                Button { jumpDate = model.month; model.jumpPresented = true } label: { Text(model.month.formatted("yyyy / MM")).font(.system(size: 21 * settings.fontMultiplier, weight: .semibold, design: .rounded)) }
                    .accessibilityLabel("选择年月").popover(isPresented: $model.jumpPresented) {
                        VStack(spacing: 14) { Text("跳转到日期").font(.headline); DatePicker("日期", selection: $jumpDate, displayedComponents: .date); HStack { Button("今天") { model.today(); model.jumpPresented = false }; Button("跳转") { model.go(to: jumpDate); model.jumpPresented = false }.keyboardShortcut(.defaultAction) } }.padding(20)
                    }
                Spacer()
                Button { model.moveMonth(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? 12 : 1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 28) }.help("下一月（→）").accessibilityLabel("下一月")
            }.foregroundStyle(color("title")).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 0) {
                if settings.config.showWeekNumbers { Text("周").frame(width: 25) }
                ForEach(0..<7, id: \.self) { offset in
                    let i = (settings.config.firstWeekday - 1 + offset) % 7
                    Text(["周日","周一","周二","周三","周四","周五","周六"][i]).frame(maxWidth: .infinity)
                }
            }.font(.system(size: 14 * settings.fontMultiplier, weight: .semibold)).foregroundStyle(color("title")).padding(.bottom, 8).padding(.horizontal, 12)
            VStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 1) {
                        if settings.config.showWeekNumbers { Text("\(weekNumber(days[row * 7]))").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 25) }
                        ForEach(Array(days.dropFirst(row * 7).prefix(7))) { day in dayView(day) }
                    }
                }
            }.padding(.horizontal, 12)
            if !settings.config.hideFooter {
                HStack(spacing: 7) {
                    Button(action: openSettings) { Image(systemName: "slider.horizontal.3") }.help("偏好设置（⌘,）").accessibilityLabel("偏好设置")
                    let info = model.engine.info(for: hoverDate ?? model.selection)
                    Text("\(info.date.formatted("M月d日")) 第\(weekNumber(info))周 \(settings.config.hideLunar ? "" : model.engine.lunarInfo(for: info.date).monthName + model.engine.lunarInfo(for: info.date).dayName)").lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Button(action: pin) { Image(systemName: model.pinned ? "pin.fill" : "pin") }.help("固定为独立窗口").accessibilityLabel("固定日历窗口")
                    Button(action: close) { Image(systemName: "xmark.circle") }.help("关闭").accessibilityLabel("关闭日历")
                }.font(.system(size: 12 * settings.fontMultiplier)).foregroundStyle(color("title")).padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .buttonStyle(.plain)
        .frame(width: settings.panelWidth)
        .background(color("window"))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .preferredColorScheme(settings.config.theme == .system ? nil : settings.config.theme == .dark ? .dark : .light)
        .popover(isPresented: $model.showDetails) { DayDetailsView(model: model, data: data, date: model.selection, openSettings: openSettings) }
        .onKeyPress(.leftArrow) { model.moveMonth(-1); return .handled }
        .onKeyPress(.rightArrow) { model.moveMonth(1); return .handled }
        .onKeyPress(.upArrow) { model.moveMonth(-12); return .handled }
        .onKeyPress(.downArrow) { model.moveMonth(12); return .handled }
        .onKeyPress(.space) { model.today(); return .handled }
        .onKeyPress(.escape) { if model.showDetails { model.showDetails = false } else if model.jumpPresented { model.jumpPresented = false } else { close() }; return .handled }
        .task { await model.refresh() }
    }
    func weekNumber(_ day: CalendarDay) -> Int { settings.config.useISOWeekNumbers ? day.weekNumber : day.systemWeekNumber }
    @ViewBuilder func dayView(_ day: CalendarDay) -> some View {
        let selected = Calendar.current.isDate(day.date, inSameDayAs: model.selection)
        let weekend = Calendar.current.isDateInWeekend(day.date)
        let label = day.calendarLabel
        let eventCount = model.events(on: day.date).count + model.reminders(on: day.date).count
        Button { model.select(day.date) } label: {
            VStack(spacing: 0) {
                Text("\(day.dayNumber)").font(.system(size: 17 * settings.fontMultiplier, weight: .semibold, design: .rounded))
                if !settings.config.hideLunar {
                    Text(label).font(.system(size: 11 * settings.fontMultiplier, weight: .medium)).lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(day.isToday ? Color.white : day.solarTerm != nil || day.festival != nil ? color("festival") : color(weekend ? "weekend" : "date"))
                }
                if settings.config.showEventDots {
                    Circle().fill(color("event")).frame(width: 3.5, height: 3.5).opacity(eventCount > 0 ? 1 : 0).padding(.top, 1)
                }
            }
            .foregroundStyle(day.isToday ? .white : color(weekend ? "weekend" : "date"))
            .frame(maxWidth: .infinity).frame(height: max(27, settings.panelHeight / 8.4))
            .background { if day.isToday { Circle().fill(color("today")).padding(.horizontal, 4) } else if selected && model.showDetails { RoundedRectangle(cornerRadius: 7).stroke(color("today").opacity(0.5), lineWidth: 1) } }
            .overlay(alignment: .topTrailing) { if settings.config.showHolidayBadges, let h = day.holiday { Text(h.status == .rest ? "休" : "班").font(.system(size: 7 * settings.fontMultiplier)).foregroundStyle(color(h.status == .rest ? "holiday" : "workday")).padding(.trailing, 2) } }
            .opacity(day.isCurrentMonth ? 1 : 0.38)
            .contentShape(Rectangle())
        }
        .onHover { inside in hoverDate = inside ? day.date : nil }
        .help("\(day.date.formatted("M月d日")) 第\(weekNumber(day))周\n\(day.lunarLong)\n\(day.solarTerm ?? day.festival ?? "")")
        .accessibilityLabel("\(day.date.formatted("yyyy年M月d日")) \(day.lunarLong) \(day.solarTerm ?? day.festival ?? "") \(eventCount > 0 ? "有\(eventCount)个事项" : "")")
        .contextMenu { Button("新建事件") { model.select(day.date) }; Button("复制日期") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(day.date.formatted("yyyy-MM-dd"), forType: .string) }; Button("回到今天") { model.today() } }
    }
}
