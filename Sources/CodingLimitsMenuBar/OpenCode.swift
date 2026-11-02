import Foundation

enum OpenCodeReader {
  private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

  static func fetch() async throws -> ProviderSnapshot {
    let data = try await request(key: credential())
    let root = try jsonObject(data)
    guard let usage = root["usage"] as? [String: Any] else {
      throw UsageError.malformed(.go, "нет usage")
    }
    let windows = [
      ("5h", "rolling"), ("Week", "weekly"), ("Month", "monthly"),
    ].compactMap { title, key -> UsageWindow? in
      guard let meter = usage[key] as? [String: Any],
            let percent = (meter["percent"] as? NSNumber)?.doubleValue else { return nil }
      return UsageWindow(title: title, usedPercent: percent, resetsAt: parseDate(meter["resetsAt"]))
    }
    guard !windows.isEmpty else { throw UsageError.malformed(.go, "нет окон usage") }
    return ProviderSnapshot(provider: .go, usage: ProviderUsage(windows: windows, workspace: nil))
  }

  static func raw() async throws -> String {
    String(decoding: try await request(key: credential()), as: UTF8.self)
  }

  /// The Go API key stays in OpenCode's own sqlite store; we only borrow it in
  /// memory to call the usage API, so this app never writes tokens to disk.
  private static func credential() async throws -> String {
    try await Task.detached(priority: .utility) {
      let database = Self.databaseURL()
      guard FileManager.default.fileExists(atPath: database.path) else {
        throw UsageError.noCredentials("OpenCode CLI не найден. Установите и подключите OpenCode Go.")
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
      process.arguments = [
        database.path,
        "select value from credential where integration_id='opencode-go' order by active desc, time_updated desc limit 1;",
      ]
      let output = Pipe()
      let errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      do { try process.run() } catch { throw UsageError.command(error.localizedDescription) }
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { throw UsageError.command("sqlite3: код \(process.terminationStatus)") }
      guard let row = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: row) as? [String: Any],
            let key = object["key"] as? String, !key.isEmpty else {
        throw UsageError.noCredentials("OpenCode Go не подключён. Выполните /connect в OpenCode.")
      }
      return key
    }.value
  }

  private static func databaseURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
      .flatMap { $0.isEmpty ? nil : $0 }
      .map(URL.init(fileURLWithPath:))
      ?? home.appending(path: ".local/share")
    return base.appending(path: "opencode/opencode.db")
  }

  private static func request(key: String) async throws -> Data {
    var request = URLRequest(url: usageURL)
    request.timeoutInterval = 15
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("CodingLimits/1.0", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
    case 200: return data
    case 401, 403: throw UsageError.unauthorized(.go)
    case let code: throw UsageError.http(.go, code)
    }
  }
}
