import Foundation
import Testing
@testable import MiniCalCore

@Suite struct CalendarEngineTests {
    let beijing = CalendarEngine(timeZone: TimeZone(identifier: "Asia/Shanghai")!)

    @Test func testChineseNewYearAndActualNewYearsEve() throws {
        let newYear = try #require(beijing.date(year: 2026, month: 2, day: 17))
        let lunar = beijing.lunarInfo(for: newYear)
        #expect(lunar.year == 2026)
        #expect(lunar.month == 1)
        #expect(lunar.day == 1)
        #expect(lunar.cyclicalYear == "丙午")
        #expect(lunar.zodiac == "马")
        #expect(beijing.info(for: newYear).festival == "春节")
        let eve = try #require(beijing.date(year: 2026, month: 2, day: 16))
        #expect(beijing.lunarInfo(for: eve).day == 29)
        #expect(beijing.lunarInfo(for: eve).year == 2025)
        #expect(beijing.info(for: eve).festival == "除夕")
        let previous = try #require(beijing.date(year: 2026, month: 2, day: 15))
        #expect(beijing.info(for: previous).festival != "除夕")
    }

    @Test func testLeapSixthMonthDoesNotRepeatFestivals() throws {
        let leapStart = try #require(beijing.date(year: 2025, month: 7, day: 25))
        let lunar = beijing.lunarInfo(for: leapStart)
        #expect(lunar.isLeapMonth)
        #expect(lunar.month == 6)
        #expect(lunar.day == 1)
        #expect(lunar.monthName == "闰六月")
        #expect(beijing.info(for: leapStart).lunarShort == "闰六月")
        let lastDay = try #require(beijing.date(year: 2025, month: 8, day: 22))
        #expect(beijing.lunarInfo(for: lastDay).isLeapMonth)
        let nextMonth = try #require(beijing.date(year: 2025, month: 8, day: 23))
        #expect(beijing.lunarInfo(for: nextMonth).isLeapMonth == false)
        #expect(beijing.lunarInfo(for: nextMonth).month == 7)
    }

    @Test func testMonthMovementClampsAndCrossesYear() throws {
        let january31 = try #require(beijing.date(year: 2026, month: 1, day: 31))
        #expect(beijing.movingMonth(january31, by: 1) == beijing.date(year: 2026, month: 2, day: 28))
        #expect(beijing.movingMonth(january31, by: -1) == beijing.date(year: 2025, month: 12, day: 31))
        let leapJanuary = try #require(beijing.date(year: 2024, month: 1, day: 31))
        #expect(beijing.movingMonth(leapJanuary, by: 1) == beijing.date(year: 2024, month: 2, day: 29))
        #expect(beijing.date(year: 2026, month: 2, day: 29) == nil)
        #expect(beijing.date(year: 2026, month: 13, day: 1) == nil)
    }

    @Test func testGridWeekStartTodayAndISOWeekYear() throws {
        let selected = try #require(beijing.date(year: 2026, month: 2, day: 17))
        let mondayDays = beijing.monthDays(containing: selected, now: selected)
        #expect(mondayDays.count == 42)
        #expect(Set(mondayDays.map(\.id)).count == 42)
        #expect(mondayDays.first?.date == beijing.date(year: 2026, month: 1, day: 26))
        #expect(mondayDays.filter(\.isCurrentMonth).count == 28)
        #expect(mondayDays.filter(\.isToday).map(\.date) == [selected])
        let sunday = CalendarEngine(timeZone: beijing.timeZone, firstWeekday: 1)
        #expect(sunday.monthDays(containing: selected).first?.date == beijing.date(year: 2026, month: 2, day: 1))
        let january1 = try #require(beijing.date(year: 2021, month: 1, day: 1))
        #expect(beijing.info(for: january1).weekNumber == 53)
    }

    @Test func testDSTKeepsUniqueCivilDaysInBothTransitions() throws {
        let engine = CalendarEngine(timeZone: TimeZone(identifier: "America/New_York")!)
        for month in [3, 11] {
            let date = try #require(engine.date(year: 2026, month: month, day: 15))
            let days = engine.monthDays(containing: date)
            #expect(days.count == 42)
            #expect(Set(days.map(\.id)).count == 42)
            let intervals = zip(days, days.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
            #expect(intervals.contains(month == 3 ? 23 * 3600 : 25 * 3600))
            #expect(intervals.allSatisfy { [23.0, 24.0, 25.0].contains($0 / 3600) })
        }
    }

    @Test func testSolarTermsDatesAndSupportedRange() throws {
        let terms = beijing.solarTerms(in: 2026)
        #expect(terms.count == 24)
        #expect(Set(terms.map(\.name)).count == 24)
        #expect(zip(terms, terms.dropFirst()).allSatisfy { $0.instant < $1.instant })
        let knownDates: [(String, Int, Int)] = [("小寒", 1, 5), ("立春", 2, 4), ("春分", 3, 20), ("清明", 4, 5), ("夏至", 6, 21), ("秋分", 9, 23), ("冬至", 12, 22)]
        for (name, month, day) in knownDates {
            let civilDate = try #require(beijing.date(year: 2026, month: month, day: day))
            #expect(beijing.info(for: civilDate).solarTerm == name)
        }
        #expect(beijing.solarTerms(in: 1899).count == 0)
        #expect(beijing.solarTerms(in: 2101).count == 0)
        // A crossing maps to different civil dates across time zones.
        let losAngeles = CalendarEngine(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let winter = try #require(terms.first { $0.name == "冬至" })
        var local = Calendar(identifier: .gregorian)
        local.timeZone = losAngeles.timeZone
        #expect(local.component(.day, from: winter.instant) == 21)
        #expect(losAngeles.info(for: winter.instant).solarTerm == "冬至")
    }

    @Test func testUnsupportedHolidayYearIsUnknown() throws {
        let future = try #require(beijing.date(year: 2035, month: 1, day: 1))
        #expect(beijing.info(for: future).holiday == nil)
        #expect(beijing.info(for: future).festival == "元旦节")
    }

    @Test func testRestoredSolarLabelsAndMinorObservances() throws {
        let halloween = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 31)))
        #expect(halloween.festival == "万圣节")
        #expect(halloween.calendarLabel == "万圣节")
        #expect(halloween.solarFestival == "万圣节 世界勤俭日")
        let scorpio = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 24)))
        #expect(scorpio.festival == "天蝎")
        #expect(scorpio.calendarLabel == "天蝎")
        let nextDay = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 25)))
        #expect(nextDay.solarFestival == nil)
        let earthDay = beijing.info(for: try #require(beijing.date(year: 2026, month: 4, day: 22)))
        #expect(earthDay.festival == "地球日")
        #expect(earthDay.solarFestival == "地球日 · 世界地球日")
        let minor = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 22)))
        #expect(minor.solarFestival == "世界传统医药日")
        #expect(minor.annotations.contains("世界传统医药日"))
        #expect(minor.festival == nil)
        #expect(minor.calendarLabel == minor.lunarShort)
    }

    @Test func testRestoredWeekFestivalsDoNotDependOnWeekStart() throws {
        for engine in [beijing, CalendarEngine(timeZone: beijing.timeZone, firstWeekday: 1)] {
            let mother = engine.info(for: try #require(engine.date(year: 2026, month: 5, day: 10)))
            #expect(mother.festival == "母亲节")
            #expect(mother.weekFestival == "母亲节 · 国际母亲节 救助贫困母亲日")
            let father = engine.info(for: try #require(engine.date(year: 2026, month: 6, day: 21)))
            #expect(father.festival == "父亲节")
            #expect(father.weekFestival == "父亲节")
            #expect(father.solarTerm == "夏至")
            #expect(father.calendarLabel == "夏至")
            #expect(father.annotations.contains("父亲节"))
            let thanksgiving = engine.info(for: try #require(engine.date(year: 2026, month: 11, day: 26)))
            #expect(thanksgiving.weekFestival == "感恩节")
            #expect(thanksgiving.festival == "感恩节")
            let previousThursday = engine.info(for: try #require(engine.date(year: 2026, month: 11, day: 19)))
            #expect(previousThursday.weekFestival != "感恩节")
        }
        let libra = beijing.info(for: try #require(beijing.date(year: 2026, month: 9, day: 23)))
        #expect(libra.solarFestival == "天秤")
        #expect(libra.solarTerm == "秋分")
        #expect(libra.calendarLabel == "秋分")
    }

    @Test func testRestoredLunarFestivalsAndLeapMonthExclusion() throws {
        let coldClothing = beijing.info(for: try #require(beijing.date(year: 2026, month: 11, day: 9)))
        #expect(coldClothing.lunarFestival == "寒衣节")
        let xiaoyuan = beijing.info(for: try #require(beijing.date(year: 2026, month: 11, day: 23)))
        #expect(xiaoyuan.lunarFestival == "下元节")
        #expect(xiaoyuan.solarFestival == "射手")
        #expect(xiaoyuan.calendarLabel == "下元节")
        let littleNewYear = beijing.info(for: try #require(beijing.date(year: 2026, month: 2, day: 10)))
        #expect(littleNewYear.lunarFestival == "小年")
        let leapDragonDay = try #require(beijing.date(year: 2023, month: 3, day: 23))
        #expect(beijing.lunarInfo(for: leapDragonDay).isLeapMonth)
        #expect(beijing.lunarInfo(for: leapDragonDay).month == 2)
        #expect(beijing.lunarInfo(for: leapDragonDay).day == 2)
        #expect(beijing.info(for: leapDragonDay).lunarFestival == nil)
    }

    @Test func testOfficial2026HolidayMarkers() throws {
        let nationalDay = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 1)))
        #expect(nationalDay.holiday?.name == "国庆节")
        #expect(nationalDay.holiday?.status == .rest)
        let octoberMakeup = beijing.info(for: try #require(beijing.date(year: 2026, month: 10, day: 10)))
        #expect(octoberMakeup.holiday?.status == .work)
        let februaryMakeup = beijing.info(for: try #require(beijing.date(year: 2026, month: 2, day: 14)))
        #expect(februaryMakeup.holiday?.status == .work)
        #expect(februaryMakeup.calendarLabel == "情人节")
    }

    @Test func testOriginalWeekRuleAndISOStayIndependent() throws {
        // Static implementation uses the current system calendar. The original
        // screenshot's host has Sunday-first, minimumDaysInFirstWeek=5. Inject
        // those settings so this test stays valid on hosts with other locales.
        var original = Calendar(identifier: .gregorian)
        original.firstWeekday = 1
        original.minimumDaysInFirstWeek = 5
        let monday = CalendarEngine(timeZone: beijing.timeZone, firstWeekday: 2, systemWeekCalendar: original)
        let sunday = CalendarEngine(timeZone: beijing.timeZone, firstWeekday: 1, systemWeekCalendar: original)
        for (day, originalWeek, isoWeek) in [(1, 39, 40), (4, 40, 40), (12, 41, 42)] {
            let date = try #require(monday.date(year: 2026, month: 10, day: day))
            #expect(monday.systemWeekNumber(for: date) == originalWeek)
            #expect(monday.info(for: date).systemWeekNumber == originalWeek)
            #expect(sunday.info(for: date).systemWeekNumber == originalWeek)
            #expect(monday.info(for: date).weekNumber == isoWeek)
        }
        let january1 = try #require(monday.date(year: 2026, month: 1, day: 1))
        // %U would return zero: the actual Calendar rule carries the prior
        // year's final week, which prevents a falsely inferred %U clone.
        #expect(monday.systemWeekNumber(for: january1) == 52)
        #expect(monday.info(for: january1).weekNumber == 1)
        var system = Calendar.current
        system.timeZone = beijing.timeZone
        let defaultEngine = CalendarEngine(timeZone: beijing.timeZone)
        #expect(defaultEngine.systemWeekNumber(for: january1) == system.component(.weekOfYear, from: january1))
    }
}
