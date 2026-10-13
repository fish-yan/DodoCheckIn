import Foundation

struct HolidayCalendar: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        var name: String
        var date: String
        var isOffDay: Bool
    }

    var year: Int
    var papers: [String]
    var days: [Day]

    static func validated(_ data: Data, year: Int) throws -> HolidayCalendar {
        guard data.count < 1_000_000 else { throw HolidayError.invalid }
        let calendar = try JSONDecoder().decode(HolidayCalendar.self, from: data)
        guard calendar.year == year, !calendar.days.isEmpty, !calendar.papers.isEmpty,
              calendar.papers.allSatisfy({
                  guard let url = URL(string: $0), let host = url.host else { return false }
                  return url.scheme == "https" && (host == "www.gov.cn" || host.hasSuffix(".gov.cn"))
              }),
              Set(calendar.days.map(\.date)).count == calendar.days.count,
              calendar.days.allSatisfy({
                  guard let date = BeijingCalendar.date($0.date) else { return false }
                  return BeijingCalendar.calendar.component(.year, from: date) == year
              }) else { throw HolidayError.invalid }
        return calendar
    }

    func isRestDay(_ date: Date) -> Bool {
        if let day = days.first(where: { $0.date == BeijingCalendar.key(date) }) { return day.isOffDay }
        return BeijingCalendar.calendar.isDateInWeekend(date)
    }

    static func bundled(year: Int) -> HolidayCalendar? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: String(year), withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? validated(data, year: year)
    }

    static func download(year: Int) async throws -> HolidayCalendar {
        let url = URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HolidayError.unavailable }
        return try validated(data, year: year)
    }
}

enum HolidayError: Error {
    case invalid, unavailable
}
