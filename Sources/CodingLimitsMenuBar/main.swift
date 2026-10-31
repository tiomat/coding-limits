import AppKit
import Foundation

func runSynchronously(_ body: @escaping @Sendable () async -> Int32) -> Never {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var code: Int32 = 0
  Task.detached {
    code = await body()
    semaphore.signal()
  }
  semaphore.wait()
  exit(code)
}

func snapshotText(_ snapshot: ProviderSnapshot) -> String {
  let windows = snapshot.usage.windows.map {
    "\($0.title): \($0.remainingPercent)% left (used=\($0.usedPercent), reset=\($0.resetsAt?.ISO8601Format() ?? "—"))"
  }.joined(separator: "; ")
  return "\(snapshot.provider.rawValue): \(windows)"
}

let arguments = CommandLine.arguments
if arguments.contains("--raw") {
  runSynchronously {
    async let kimi = try? KimiReader.raw()
    async let go = try? OpenCodeReader.raw()
    print("--- Kimi ---\n\(await kimi ?? "unavailable")")
    print("--- OpenCode Go ---\n\(await go ?? "unavailable")")
    return 0
  }
} else if arguments.contains("--snapshot") {
  runSynchronously {
    var failed = false
    for provider in Provider.allCases {
      do {
        let snapshot = try await provider == .kimi ? KimiReader.fetch() : OpenCodeReader.fetch()
        print(snapshotText(snapshot))
      } catch {
        failed = true
        print("\(provider.rawValue): error=\((error as? UsageError)?.errorDescription ?? error.localizedDescription)")
      }
    }
    return failed ? 1 : 0
  }
} else {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()
}
