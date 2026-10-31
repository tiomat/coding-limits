import Foundation

enum OpenCodeReader {
  static func fetch() async throws -> ProviderSnapshot {
    let data = try await request()
    let root = try jsonObject(data)
    guard let info = root["data"] as? [String: Any] else {
      throw UsageError.noCredentials("OpenCode Go не подключён. Выполните /connect в OpenCode.")
    }
    guard let go = info["go"] as? [String: Any] else {
      throw UsageError.noCredentials("У рабочего пространства OpenCode нет активной подписки Go.")
    }
    let workspace = (info["workspace"] as? [String: Any])?["name"] as? String
    let windows = [
      ("5h", "rolling"), ("Week", "weekly"), ("Month", "monthly"),
    ].compactMap { title, key -> UsageWindow? in
      guard let meter = go[key] as? [String: Any],
            let percent = (meter["percent"] as? NSNumber)?.doubleValue else { return nil }
      return UsageWindow(title: title, usedPercent: percent, resetsAt: parseDate(meter["resetsAt"]))
    }
    guard !windows.isEmpty else { throw UsageError.malformed(.go, "нет окон go") }
    return ProviderSnapshot(provider: .go, usage: ProviderUsage(windows: windows, workspace: workspace))
  }

  static func raw() async throws -> String {
    String(decoding: try await request(), as: UTF8.self)
  }

  /// Uses OpenCode's own API client and credential store. This neither starts a
  /// second daemon nor copies OAuth tokens into this application's files.
  private static func request() async throws -> Data {
    try await Task.detached(priority: .utility) {
      let executable = ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
      guard let executable else {
        throw UsageError.noCredentials("OpenCode CLI не найден. Установите и подключите OpenCode Go.")
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = ["api", "GET", "/api/experimental/usage/limits"]
      let output = Pipe()
      let errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      do { try process.run() } catch { throw UsageError.command(error.localizedDescription) }
      let data = output.fileHandleForReading.readDataToEndOfFile()
      let errorData = errors.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let detail = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw UsageError.command("OpenCode API: \(detail.isEmpty ? "код \(process.terminationStatus)" : detail)")
      }
      return data
    }.value
  }
}
