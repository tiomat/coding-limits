import Foundation

private struct KimiCredentials: Codable {
  var accessToken: String
  var refreshToken: String?
  var expiresAt: TimeInterval?
  var scope: String?
  var tokenType: String?
  var expiresIn: Double?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case scope
    case tokenType = "token_type"
    case expiresIn = "expires_in"
  }

  var needsRefresh: Bool {
    guard let expiresAt, expiresAt > 0 else { return false }
    return expiresAt <= Date().timeIntervalSince1970 + 300
  }
}

enum KimiReader {
  private static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!
  private static let tokenEndpoint = URL(string: "https://auth.kimi.com/api/oauth/token")!
  private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
  private static let credentialFile = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".kimi/credentials/kimi-code.json")

  static func fetch() async throws -> ProviderSnapshot {
    let (data, status) = try await call()
    switch status {
    case 200: break
    case 401, 403: throw UsageError.unauthorized(.kimi)
    default: throw UsageError.http(.kimi, status)
    }
    let root = try jsonObject(data)
    var windows = [UsageWindow]()
    if let usages = root["usages"] as? [String: Any] {
      // Kimi Code 2.x reports ratios here; the older Python CLI used the
      // usage/limits shape handled below.
      let labels = [
        "limit_5h": "5h",
        "limit_month_total": "Month total",
        "limit_month_code": "Month code",
      ]
      for (key, value) in usages {
        guard let data = value as? [String: Any],
              let ratio = number(data["used_ratio"]) else { continue }
        windows.append(UsageWindow(
          title: labels[key] ?? key,
          usedPercent: ratio * 100,
          resetsAt: resetDate(data)
        ))
      }
    } else {
      if let summary = root["usage"] as? [String: Any], let row = window(summary, fallback: "Week") {
        windows.append(row)
      }
      if let entries = root["limits"] as? [[String: Any]] {
        for (index, entry) in entries.enumerated() {
          let detail = entry["detail"] as? [String: Any] ?? entry
          let descriptor = entry["window"] as? [String: Any] ?? entry
          let label = limitLabel(entry, detail: detail, descriptor: descriptor, index: index)
          if let row = window(detail, fallback: label) { windows.append(row) }
        }
      }
    }
    windows.sort { windowOrder($0.title) < windowOrder($1.title) }
    guard !windows.isEmpty else { throw UsageError.malformed(.kimi, "нет usage/limits") }
    return ProviderSnapshot(provider: .kimi, usage: ProviderUsage(windows: windows, workspace: nil))
  }

  static func raw() async throws -> String {
    let (data, status) = try await call()
    return "HTTP \(status)\n" + (String(data: data, encoding: .utf8) ?? "<binary>")
  }

  private static func call() async throws -> (Data, Int) {
    var credentials = try loadCredentials()
    if credentials.needsRefresh, let refreshToken = credentials.refreshToken, !refreshToken.isEmpty {
      credentials = try await refresh(refreshToken)
      try save(credentials)
    }
    return try await request(token: credentials.accessToken)
  }

  private static func request(token: String) async throws -> (Data, Int) {
    var request = URLRequest(url: endpoint)
    request.timeoutInterval = 15
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  private static func loadCredentials() throws -> KimiCredentials {
    let environment = ProcessInfo.processInfo.environment
    if let token = environment["KIMI_LIMITS_TOKEN"] ?? environment["KIMI_API_KEY"], !token.isEmpty {
      return KimiCredentials(
        accessToken: token, refreshToken: nil, expiresAt: nil, scope: nil, tokenType: nil, expiresIn: nil
      )
    }
    guard let data = try? Data(contentsOf: credentialFile),
          let credentials = try? JSONDecoder().decode(KimiCredentials.self, from: data),
          !credentials.accessToken.isEmpty else {
      throw UsageError.noCredentials("Kimi Code не авторизован. Выполните /login в Kimi Code CLI.")
    }
    return credentials
  }

  private static func refresh(_ token: String) async throws -> KimiCredentials {
    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let fields = [
      "client_id": clientID,
      "grant_type": "refresh_token",
      "refresh_token": token,
    ]
    request.httpBody = fields.map { key, value in
      let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
      return "\(key)=\(escaped)"
    }.joined(separator: "&").data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      if status == 401 || status == 403 { throw UsageError.unauthorized(.kimi) }
      throw UsageError.http(.kimi, status)
    }
    var refreshed = try JSONDecoder().decode(KimiCredentials.self, from: data)
    if refreshed.refreshToken == nil { refreshed.refreshToken = token }
    return refreshed
  }

  private static func save(_ credentials: KimiCredentials) throws {
    let directory = credentialFile.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    try JSONEncoder().encode(credentials).write(to: credentialFile, options: [.atomic, .completeFileProtection])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialFile.path())
  }

  private static func window(_ data: [String: Any], fallback: String) -> UsageWindow? {
    let limit = number(data["limit"])
    var used = number(data["used"])
    if used == nil, let limit, let remaining = number(data["remaining"]) {
      used = limit - remaining
    }
    guard let limit, limit > 0 else { return nil }
    let title = (data["name"] as? String) ?? (data["title"] as? String) ?? fallback
    return UsageWindow(title: title, usedPercent: max(0, (used ?? 0) / limit * 100), resetsAt: resetDate(data))
  }

  private static func limitLabel(
    _ item: [String: Any], detail: [String: Any], descriptor: [String: Any], index: Int
  ) -> String {
    for object in [item, detail] {
      for key in ["name", "title", "scope"] {
        if let value = object[key] as? String, !value.isEmpty { return value }
      }
    }
    let duration = (descriptor["duration"] as? NSNumber)?.intValue
      ?? (item["duration"] as? NSNumber)?.intValue
      ?? (detail["duration"] as? NSNumber)?.intValue
    let unit = (descriptor["timeUnit"] as? String) ?? (item["timeUnit"] as? String)
      ?? (detail["timeUnit"] as? String) ?? ""
    if let duration {
      if unit.contains("MINUTE") {
        return duration % 60 == 0 ? "\(duration / 60)h" : "\(duration)m"
      }
      if unit.contains("HOUR") { return "\(duration)h" }
      if unit.contains("DAY") { return duration == 7 ? "Week" : "\(duration)d" }
    }
    return "Limit \(index + 1)"
  }

  private static func number(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let text = value as? String { return Double(text) }
    return nil
  }

  private static func windowOrder(_ title: String) -> Int {
    let lower = title.lowercased()
    if lower.contains("5h") || lower.contains("300m") { return 0 }
    if lower.contains("week") || lower.contains("7d") { return 1 }
    if lower.contains("month") || lower.contains("30d") { return 2 }
    return 3
  }
}
