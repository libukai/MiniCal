import Foundation

public enum HolidayStatus: String, Codable, Sendable { case rest, work }

public struct HolidayMarker: Codable, Equatable, Sendable {
    public let name: String
    public let status: HolidayStatus
    public init(name: String, status: HolidayStatus) { self.name = name; self.status = status }
}

public struct CalendarDay: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let dayNumber: Int
    public let isCurrentMonth: Bool
    public let isToday: Bool
    public let lunarShort: String
    public let lunarLong: String
    public let solarTerm: String?
    /// Full observance labels. Asterisk
    /// markers are stripped here; these historical observance tables are not
    /// an authoritative source of current legal holidays.
    public let solarFestival: String?
    public let lunarFestival: String?
    public let weekFestival: String?
    public let annotations: [String]
    /// Original compact-grid priority: lunar festival, term, major solar/week
    /// festival, then lunar date. Minor observances appear in annotations only.
    public let calendarLabel: String
    public let festival: String?
    public let holiday: HolidayMarker?
    /// ISO 8601 week number, independent of the month-grid week start.
    public let weekNumber: Int
    /// Locale-dependent system week numbering. This value
    /// therefore follows the captured system calendar's first-week rules, not
    /// ISO or strftime %U. Changing the grid's first weekday does not change it.
    public let systemWeekNumber: Int
}

public struct LunarDateInfo: Equatable, Sendable {
    /// Gregorian-numbered lunar year, changing at Chinese New Year.
    public let year: Int
    public let month: Int
    public let day: Int
    public let isLeapMonth: Bool
    public let cyclicalYear: String
    public let zodiac: String
    public let monthName: String
    public let dayName: String
    public var description: String { "\(cyclicalYear)年（\(zodiac)）\(monthName)\(dayName)" }
}

public struct SolarTerm: Identifiable, Sendable {
    public var id: String { "\(name)-\(instant.timeIntervalSince1970)" }
    public let name: String
    /// Estimated astronomical crossing instant; not an almanac-certified exact time.
    public let instant: Date
}

/// All civil days use the selected time zone; arithmetic uses calendar components,
/// never 86,400-second increments, including across daylight-saving transitions.
public struct CalendarEngine: Sendable {
    public let timeZone: TimeZone
    public let firstWeekday: Int
    private let gregorian: Calendar
    private let chinese: Calendar
    private let iso: Calendar
    private let systemWeekCalendar: Calendar
    private let holidays: [String: HolidayMarker]

    public init(timeZone: TimeZone = .current, firstWeekday: Int = 2, systemWeekCalendar: Calendar = .current) {
        self.timeZone = timeZone
        self.firstWeekday = (1...7).contains(firstWeekday) ? firstWeekday : 2
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        gregorian.firstWeekday = self.firstWeekday
        self.gregorian = gregorian
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        self.chinese = chinese
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        self.iso = iso
        var systemWeekCalendar = systemWeekCalendar
        systemWeekCalendar.timeZone = timeZone
        self.systemWeekCalendar = systemWeekCalendar
        self.holidays = Self.loadHolidays()
    }

    /// Stable six-week grid, including adjacent-month days.
    public func monthDays(containing date: Date, now: Date = Date()) -> [CalendarDay] {
        guard let month = gregorian.dateInterval(of: .month, for: date) else { return [] }
        let start = gregorian.startOfDay(for: month.start)
        let offset = (gregorian.component(.weekday, from: start) - firstWeekday + 7) % 7
        guard let gridStart = gregorian.date(byAdding: .day, value: -offset, to: start),
              let gridEnd = gregorian.date(byAdding: .day, value: 41, to: gridStart) else { return [] }
        let years = Set([gregorian.component(.year, from: gridStart), gregorian.component(.year, from: gridEnd)])
        let terms = termDays(years: years)
        return (0..<42).compactMap { index in
            guard let day = gregorian.date(byAdding: .day, value: index, to: gridStart) else { return nil }
            return makeDay(day, now: now, inMonth: gregorian.isDate(day, equalTo: date, toGranularity: .month), terms: terms)
        }
    }

    public func info(for date: Date) -> CalendarDay {
        info(for: date, now: Date())
    }

    public func info(for date: Date, now: Date) -> CalendarDay {
        let terms = termDays(years: [gregorian.component(.year, from: date)])
        return makeDay(date, now: now, inMonth: true, terms: terms)
    }

    /// Preserve day when possible and clamp it at the destination month's end.
    public func movingMonth(_ date: Date, by offset: Int) -> Date {
        guard let monthStart = gregorian.dateInterval(of: .month, for: date)?.start,
              let destination = gregorian.date(byAdding: .month, value: offset, to: monthStart),
              let range = gregorian.range(of: .day, in: .month, for: destination) else { return date }
        let day = min(gregorian.component(.day, from: date), range.count)
        return gregorian.date(byAdding: .day, value: day - 1, to: destination).map { gregorian.startOfDay(for: $0) } ?? date
    }

    public func monthTitle(_ date: Date) -> String {
        let components = gregorian.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }

    /// Uses the system calendar week numbering independently of the grid start day.
    public func systemWeekNumber(for date: Date) -> Int {
        systemWeekCalendar.component(.weekOfYear, from: date)
    }

    /// Invalid dates are rejected rather than normalized into a different month.
    public func date(year: Int, month: Int, day: Int) -> Date? {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        let result = gregorian.dateComponents([.year, .month, .day], from: date)
        guard result.year == year, result.month == month, result.day == day else { return nil }
        return gregorian.startOfDay(for: date)
    }

    public func lunarInfo(for date: Date) -> LunarDateInfo {
        // Noon keeps conversion on the intended civil day around DST changes.
        let noon = gregorian.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let components = chinese.dateComponents([.year, .month, .day], from: noon)
        let cycle = (components.year ?? 1) - 1
        let month = components.month ?? 1
        let day = components.day ?? 1
        let leap = components.isLeapMonth ?? false
        let stems = Array("甲乙丙丁戊己庚辛壬癸")
        let branches = Array("子丑寅卯辰巳午未申酉戌亥")
        let animals = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪")
        let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let gregorianYear = gregorian.component(.year, from: noon)
        let gregorianMonth = gregorian.component(.month, from: noon)
        let year = (gregorianMonth <= 2 && month >= 11) ? gregorianYear - 1 : gregorianYear
        return LunarDateInfo(year: year, month: month, day: day, isLeapMonth: leap,
                             cyclicalYear: "\(stems[cycle % 10])\(branches[cycle % 12])",
                             zodiac: String(animals[cycle % 12]),
                             monthName: (leap ? "闰" : "") + names[max(0, min(11, month - 1))],
                             dayName: Self.lunarDayName(day))
    }

    /// Approximate apparent solar longitude crossings for 1900...2100.
    /// Uses the low-order Meeus solar model published by NOAA, with NASA's
    /// Delta-T polynomial. Iteration converges below one second, but that is
    /// numerical resolution, not astronomical accuracy: omitted perturbations
    /// can move a crossing by tens of minutes and its civil date near midnight.
    /// Sources: gml.noaa.gov/grad/solcalc/ and
    /// eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html.
    public func solarTerms(in year: Int) -> [SolarTerm] {
        guard (1900...2100).contains(year) else { return [] }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = utc.date(from: DateComponents(year: year, month: 1, day: 5, hour: 12)) else { return [] }
        let names = ["小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"]
        return names.enumerated().map { index, name in
            var instant = start.addingTimeInterval(Double(index) * 15.22 * 86_400)
            let target = Double((285 + index * 15) % 360)
            for _ in 0..<8 {
                let difference = Self.signedAngle(Self.solarLongitude(at: instant, year: year) - target)
                let speed = Self.signedAngle(Self.solarLongitude(at: instant.addingTimeInterval(3600), year: year) - Self.solarLongitude(at: instant.addingTimeInterval(-3600), year: year)) / 7200
                instant = instant.addingTimeInterval(-difference / speed)
            }
            return SolarTerm(name: name, instant: instant)
        }
    }

    private func makeDay(_ input: Date, now: Date, inMonth: Bool, terms: [Date: String]) -> CalendarDay {
        let date = gregorian.startOfDay(for: input)
        let lunar = lunarInfo(for: date)
        let short = lunar.day == 1 ? lunar.monthName : lunar.dayName
        let solarKey = String(format: "d%02d%02d", gregorian.component(.month, from: date), gregorian.component(.day, from: date))
        let solar = Self.solarObservances[solarKey]
        let lunarFestival = lunarFestival(for: date, lunar: lunar)
        let weekKey = String(format: "%02d%d%d", gregorian.component(.month, from: date), (gregorian.component(.day, from: date) - 1) / 7 + 1, gregorian.component(.weekday, from: date))
        let week = Self.weekObservances[weekKey]
        let majorSolar = solar.flatMap { $0.hasPrefix("*") ? nil : Self.compactFestival($0) }
        let majorWeek = week.flatMap { $0.hasPrefix("*") ? nil : Self.compactFestival($0) }
        let festival = lunarFestival ?? majorSolar ?? majorWeek
        let solarDetail = solar.map(Self.fullFestival)
        let weekDetail = week.map(Self.fullFestival)
        return CalendarDay(date: date, dayNumber: gregorian.component(.day, from: date),
                           isCurrentMonth: inMonth, isToday: gregorian.isDate(date, inSameDayAs: now),
                           lunarShort: short,
                           lunarLong: lunar.description, solarTerm: terms[date],
                           solarFestival: solarDetail, lunarFestival: lunarFestival, weekFestival: weekDetail,
                           annotations: [terms[date], solarDetail, lunarFestival, weekDetail].compactMap { $0 },
                           calendarLabel: lunarFestival ?? terms[date] ?? majorSolar ?? majorWeek ?? short,
                           festival: festival, holiday: holidays[dayKey(date)],
                           weekNumber: iso.component(.weekOfYear, from: date),
                           systemWeekNumber: systemWeekNumber(for: date))
    }

    private func lunarFestival(for date: Date, lunar: LunarDateInfo) -> String? {
        // New Year's Eve is the actual last day, which may be the 29th or 30th.
        if let next = gregorian.date(byAdding: .day, value: 1, to: date) {
            let tomorrow = lunarInfo(for: next)
            if tomorrow.month == 1 && tomorrow.day == 1 && !tomorrow.isLeapMonth { return "除夕" }
        }
        if !lunar.isLeapMonth {
            let festivals = ["1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头节", "5-5": "端午节", "7-7": "七夕节", "7-15": "中元节", "8-15": "中秋节", "9-9": "重阳节", "10-1": "寒衣节", "10-15": "下元节", "12-8": "腊八节", "12-23": "小年"]
            if let name = festivals["\(lunar.month)-\(lunar.day)"] { return name }
        }
        return nil
    }

    private static func compactFestival(_ raw: String) -> String {
        if let separator = raw.firstIndex(of: "-") { return String(raw[..<separator]) }
        if let separator = raw.firstIndex(of: " ") { return String(raw[..<separator]) }
        return raw
    }

    private static func fullFestival(_ raw: String) -> String {
        let value = raw.hasPrefix("*") ? String(raw.dropFirst()) : raw
        return value.replacingOccurrences(of: "-", with: " · ")
    }

    // Week observance keys encode month, occurrence and Foundation weekday (Sunday=1).
    // Preserve original major/minor markers and historical dates; these
    // observances must not be used as modern official/legal holiday data.
    private static let solarObservances: [String: String] = [
        "d0101": "元旦节",
        "d0120": "水瓶",
        "d0202": "湿地日-世界湿地日",
        "d0210": "*国际气象节",
        "d0214": "情人节",
        "d0219": "双鱼",
        "d0301": "*国际海豹日",
        "d0303": "*全国爱耳日",
        "d0305": "学雷锋-学雷锋纪念日",
        "d0308": "妇女节",
        "d0312": "植树节 孙中山逝世纪念日",
        "d0314": "*国际警察日",
        "d0315": "消费者-消费者权益日",
        "d0317": "*中国国医节 国际航海日",
        "d0321": "白羊 世界森林日 消除种族歧视国际日 世界儿歌日",
        "d0322": "*世界水日",
        "d0323": "*世界气象日",
        "d0324": "*世界防治结核病日",
        "d0325": "*全国中小学生安全教育日",
        "d0330": "*巴勒斯坦国土日",
        "d0401": "愚人节 全国爱国卫生运动月 税收宣传月",
        "d0407": "*世界卫生日",
        "d0420": "金牛",
        "d0422": "地球日-世界地球日",
        "d0423": "*世界图书和版权日",
        "d0424": "*亚非新闻工作者日",
        "d0501": "劳动节",
        "d0504": "青年节",
        "d0505": "*碘缺乏病防治日",
        "d0508": "*世界红十字日",
        "d0512": "护士节-国际护士节",
        "d0515": "*国际家庭日",
        "d0517": "*世界电信日",
        "d0518": "博物馆-国际博物馆日",
        "d0520": "*全国学生营养日",
        "d0521": "双子",
        "d0522": "*国际生物多样性日",
        "d0531": "*世界无烟日",
        "d0601": "儿童节-国际儿童节",
        "d0605": "环境日-世界环境日",
        "d0606": "*全国爱眼日",
        "d0617": "*防治荒漠化和干旱日",
        "d0622": "巨蟹",
        "d0623": "奥林匹克-国际奥林匹克日",
        "d0625": "*全国土地日",
        "d0626": "*国际禁毒日",
        "d0701": "建党节 香港回归纪念日 中共诞辰 世界建筑日",
        "d0702": "*国际体育记者日",
        "d0707": "*抗日战争纪念日",
        "d0711": "*世界人口日",
        "d0723": "狮子",
        "d0730": "*非洲妇女日",
        "d0801": "建军节",
        "d0808": "*中国男子节(爸爸节)",
        "d0823": "处女",
        "d0903": "抗日战争-抗日战争胜利纪念",
        "d0908": "*国际扫盲日 国际新闻工作者日",
        "d0909": "*毛泽东逝世纪念",
        "d0910": "教师节-中国教师节",
        "d0914": "*世界清洁地球日",
        "d0916": "*国际臭氧层保护日",
        "d0918": "*九一八事变纪念日",
        "d0920": "*国际爱牙日",
        "d0923": "天秤",
        "d0927": "*世界旅游日",
        "d0928": "*孔子诞辰",
        "d1001": "国庆节 世界音乐日 国际老人节",
        "d1002": "*国际和平与民主自由斗争日",
        "d1004": "*世界动物日",
        "d1006": "*老人节",
        "d1008": "*全国高血压日",
        "d1009": "*世界邮政日 万国邮联日",
        "d1010": "*辛亥革命纪念日 世界精神卫生日",
        "d1013": "*世界保健日 国际教师节",
        "d1014": "*世界标准日",
        "d1015": "*国际盲人节(白手杖节)",
        "d1016": "*世界粮食日",
        "d1017": "*世界消除贫困日",
        "d1022": "*世界传统医药日",
        "d1024": "天蝎 联合国日 世界发展信息日",
        "d1031": "万圣节 世界勤俭日",
        "d1107": "*十月社会主义革命纪念日",
        "d1108": "*中国记者日",
        "d1109": "*全国消防安全宣传教育日",
        "d1110": "*世界青年节",
        "d1111": "光棍节 国际科学与和平周(本日所属的一周)",
        "d1112": "*孙中山诞辰纪念日",
        "d1114": "*世界糖尿病日",
        "d1117": "*国际大学生节 世界学生节",
        "d1121": "*世界问候日 世界电视日",
        "d1123": "射手",
        "d1129": "*国际声援巴勒斯坦人民国际日",
        "d1201": "艾滋病-世界艾滋病日",
        "d1203": "*世界残疾人日",
        "d1205": "*国际经济和社会发展志愿人员日",
        "d1208": "*国际儿童电视日",
        "d1209": "*世界足球日",
        "d1210": "*世界人权日",
        "d1212": "*西安事变纪念日",
        "d1213": "*南京大屠杀国家公祭日",
        "d1220": "*澳门回归纪念",
        "d1221": "*国际篮球日",
        "d1222": "摩羯",
        "d1224": "平安夜",
        "d1225": "圣诞节",
        "d1226": "*毛泽东诞辰纪念",
    ]
    private static let weekObservances: [String: String] = [
        "0513": "*世界哮喘日",
        "0521": "母亲节-国际母亲节 救助贫困母亲日",
        "0531": "*全国助残日",
        "0533": "*国际牛奶日",
        "0627": "*中国文化遗产日",
        "0631": "父亲节",
        "0717": "*国际合作节",
        "0731": "*被奴役国家周",
        "0933": "*国际和平日",
        "0937": "*全民国防教育日",
        "0941": "*国际聋人节 世界儿童日",
        "0951": "*世界海事日 世界心脏病日",
        "1012": "*国际住房日 世界建筑日 世界人居日",
        "1024": "*国际减灾日",
        "1025": "*世界视觉日",
        "1145": "感恩节",
        "1221": "*国际儿童电视广播日",
    ]

    private func termDays(years: Set<Int>) -> [Date: String] {
        var result: [Date: String] = [:]
        for year in years { for term in solarTerms(in: year) { result[gregorian.startOfDay(for: term.instant)] = term.name } }
        return result
    }

    private func dayKey(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func loadHolidays() -> [String: HolidayMarker] {
        struct Payload: Decodable { let years: [String: [String: HolidayMarker]] }
        guard let url = Bundle.module.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [:] }
        return payload.years.keys.sorted().reduce(into: [:]) { result, year in
            for (key, value) in payload.years[year] ?? [:] where key.hasPrefix(year + "-") { result[key] = value }
        }
    }

    private static func lunarDayName(_ day: Int) -> String {
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        switch day {
        case 1...10: return "初" + digits[day - 1]
        case 11...19: return "十" + digits[day - 11]
        case 20: return "二十"
        case 21...29: return "廿" + digits[day - 21]
        case 30: return "三十"
        default: return String(day)
        }
    }

    private static func signedAngle(_ degrees: Double) -> Double {
        let value = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (value < 0 ? value + 360 : value) - 180
    }

    private static func solarLongitude(at instant: Date, year: Int) -> Double {
        let jd = instant.timeIntervalSince1970 / 86_400 + 2_440_587.5 + deltaT(year: Double(year)) / 86_400
        let t = (jd - 2_451_545) / 36_525
        let l0 = 280.46646 + t * (36_000.76983 + 0.0003032 * t)
        let m = (357.52911 + t * (35_999.05029 - 0.0001537 * t)) * .pi / 180
        let equation = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        return l0 + equation - 0.00569 - 0.00478 * sin(omega)
    }

    private static func deltaT(year y: Double) -> Double {
        if y < 1920 { let t = y - 1900; return -2.79 + 1.494119*t - 0.0598939*t*t + 0.0061966*pow(t, 3) - 0.000197*pow(t, 4) }
        if y < 1941 { let t = y - 1920; return 21.20 + 0.84493*t - 0.076100*t*t + 0.0020936*pow(t, 3) }
        if y < 1961 { let t = y - 1950; return 29.07 + 0.407*t - t*t/233 + pow(t, 3)/2547 }
        if y < 1986 { let t = y - 1975; return 45.45 + 1.067*t - t*t/260 - pow(t, 3)/718 }
        if y < 2005 { let t = y - 2000; return 63.86 + 0.3345*t - 0.060374*t*t + 0.0017275*pow(t, 3) + 0.000651814*pow(t, 4) + 0.00002373599*pow(t, 5) }
        if y < 2050 { let t = y - 2000; return 62.92 + 0.32217*t + 0.005589*t*t }
        return -20 + 32*pow((y - 1820)/100, 2) - 0.5628*(2150 - y)
    }
}
