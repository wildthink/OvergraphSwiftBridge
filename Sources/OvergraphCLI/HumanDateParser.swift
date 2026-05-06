import Foundation

struct HumanDateParser {
  private let calendar: Calendar
  private let localTimeZone: TimeZone
  private let iso8601Formatters: [ISO8601DateFormatter]
  private let localFormatters: [DateFormatter]

  init(
    calendar: Calendar = .current,
    localTimeZone: TimeZone = .current
  ) {
    var calendar = calendar
    calendar.timeZone = localTimeZone
    self.calendar = calendar
    self.localTimeZone = localTimeZone

    let isoWithFractional = ISO8601DateFormatter()
    isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]

    self.iso8601Formatters = [isoWithFractional, iso]

    self.localFormatters = [
      Self.makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS", timeZone: localTimeZone),
      Self.makeFormatter("yyyy-MM-dd'T'HH:mm:ss", timeZone: localTimeZone),
      Self.makeFormatter("yyyy-MM-dd'T'HH:mm", timeZone: localTimeZone),
      Self.makeFormatter("yyyy-MM-dd HH:mm:ss", timeZone: localTimeZone),
      Self.makeFormatter("yyyy-MM-dd HH:mm", timeZone: localTimeZone),
      Self.makeFormatter("yyyy-MM-dd", timeZone: localTimeZone),
      Self.makeFormatter("yyyy/MM/dd", timeZone: localTimeZone),
    ]
  }

  func parseEpochMilliseconds(_ text: String) throws -> Int64 {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw CLIError.usage("Expected a date or epoch value")
    }

    let lowered = trimmed.lowercased()
    switch lowered {
    case "now":
      return Int64(Date().timeIntervalSince1970 * 1000)
    case "today":
      return try startOfDay(forDayOffset: 0)
    case "yesterday":
      return try startOfDay(forDayOffset: -1)
    case "tomorrow":
      return try startOfDay(forDayOffset: 1)
    default:
      break
    }

    if let raw = Int64(trimmed) {
      return normalizeEpoch(raw)
    }

    for formatter in iso8601Formatters {
      if let date = formatter.date(from: trimmed) {
        return Int64(date.timeIntervalSince1970 * 1000)
      }
    }

    for formatter in localFormatters {
      if let date = formatter.date(from: trimmed) {
        return Int64(date.timeIntervalSince1970 * 1000)
      }
    }

    throw CLIError.usage(
      """
      Invalid date '\(text)'. Use epoch ms, epoch seconds, `now`, `today`, \
      `yesterday`, `tomorrow`, `YYYY-MM-DD`, or an ISO timestamp.
      """
    )
  }

  private func startOfDay(forDayOffset offset: Int) throws -> Int64 {
    let now = Date()
    guard let shifted = calendar.date(byAdding: .day, value: offset, to: now) else {
      throw CLIError.usage("Could not compute date for '\(offset)'")
    }
    let start = calendar.startOfDay(for: shifted)
    return Int64(start.timeIntervalSince1970 * 1000)
  }

  private func normalizeEpoch(_ raw: Int64) -> Int64 {
    if abs(raw) < 100_000_000_000 {
      return raw * 1000
    }
    return raw
  }

  private static func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter
  }
}
