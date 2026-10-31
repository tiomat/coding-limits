import Foundation

struct UsageWindow {
  let title: String
  let usedPercent: Double
  let resetsAt: Date?

  var remainingPercent: Int {
    max(0, min(100, 100 - Int(usedPercent.rounded())))
  }
}

struct ProviderUsage {
  let windows: [UsageWindow]
  let workspace: String?
}

struct ProviderSnapshot {
  let provider: Provider
  let usage: ProviderUsage
  let timestamp = Date()
}

enum Provider: String, CaseIterable {
  case kimi = "Kimi"
  case go = "Go"

  var shortTitle: String { self == .kimi ? "K" : "G" }
  var dashboard: URL {
    switch self {
    case .kimi: URL(string: "https://www.kimi.com/code")!
    case .go: URL(string: "https://opencode.ai/auth")!
    }
  }
}

enum UsageError: LocalizedError {
  case noCredentials(String)
  case unauthorized(Provider)
  case http(Provider, Int)
  case malformed(Provider, String)
  case command(String)

  var errorDescription: String? {
    switch self {
    case let .noCredentials(message): message
    case let .unauthorized(provider):
      "\(provider.rawValue) отклонил авторизацию. Войдите заново в CLI."
    case let .http(provider, code): "\(provider.rawValue) вернул HTTP \(code)."
    case let .malformed(provider, detail): "\(provider.rawValue): не удалось разобрать ответ (\(detail))."
    case let .command(message): message
    }
  }
}

func parseDate(_ value: Any?) -> Date? {
  if let milliseconds = value as? NSNumber {
    return Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
  }
  guard let text = value as? String else { return nil }
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = fractional.date(from: text) { return date }
  let plain = ISO8601DateFormatter()
  plain.formatOptions = [.withInternetDateTime]
  return plain.date(from: text)
}

func resetDate(_ object: [String: Any]) -> Date? {
  for key in ["reset_at", "resetAt", "reset_time", "resetTime", "resetsAt"] {
    if let date = parseDate(object[key]) { return date }
  }
  for key in ["reset_in", "resetIn", "ttl"] {
    if let seconds = (object[key] as? NSNumber)?.doubleValue {
      return Date().addingTimeInterval(seconds)
    }
  }
  return nil
}

func jsonObject(_ data: Data) throws -> [String: Any] {
  guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw UsageError.malformed(.kimi, "ожидался JSON-объект")
  }
  return object
}
