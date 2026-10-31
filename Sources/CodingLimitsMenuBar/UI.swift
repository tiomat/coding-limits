import AppKit
import Foundation

func result<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
  do { return .success(try await operation()) } catch { return .failure(error) }
}

final class LimitRowView: NSView {
  private let limit: UsageWindow

  init(limit: UsageWindow) {
    self.limit = limit
    super.init(frame: NSRect(x: 0, y: 0, width: 390, height: 58))
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let remaining = limit.remainingPercent
    let labelAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
      .foregroundColor: NSColor.labelColor,
    ]
    let detailAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: NSColor.secondaryLabelColor,
    ]
    limit.title.draw(at: NSPoint(x: 14, y: 12), withAttributes: labelAttributes)
    "\(remaining)%".draw(at: NSPoint(x: 136, y: 12), withAttributes: labelAttributes)
    "left".draw(at: NSPoint(x: 174, y: 13), withAttributes: detailAttributes)
    if let resetsAt = limit.resetsAt {
      let text = "reset \(Self.resetDescription(resetsAt))"
      let size = text.size(withAttributes: detailAttributes)
      text.draw(at: NSPoint(x: bounds.width - size.width - 14, y: 13), withAttributes: detailAttributes)
    }

    let bar = NSRect(x: 14, y: 36, width: bounds.width - 28, height: 8)
    NSColor.tertiaryLabelColor.withAlphaComponent(0.34).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
    let width = bar.width * CGFloat(remaining) / 100
    if width > 0 {
      let colors: [NSColor] = remaining <= 10 ? [.systemRed, .systemPink]
        : remaining <= 20 ? [.systemOrange, .systemYellow] : [.systemTeal, .systemCyan]
      NSGradient(colors: colors)!.draw(
        in: NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: width, height: bar.height),
                         xRadius: 4, yRadius: 4), angle: 0
      )
    }
  }

  private static func resetDescription(_ date: Date) -> String {
    let interval = max(0, date.timeIntervalSinceNow)
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = interval >= 86_400 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: interval) ?? "now"
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var snapshots: [Provider: ProviderSnapshot] = [:]
  private var errors: [Provider: Error] = [:]
  private var fetching = false
  private var refreshTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    statusItem.button?.title = "K …  G …"
    rebuildMenu()
    refresh()
    refreshTimer = Timer.scheduledTimer(
      timeInterval: 120, target: self, selector: #selector(refresh), userInfo: nil, repeats: true
    )
  }

  func applicationWillTerminate(_ notification: Notification) { refreshTimer?.invalidate() }

  @objc private func refresh() {
    guard !fetching else { return }
    fetching = true
    Task { [weak self] in
      async let kimi = result { try await KimiReader.fetch() }
      async let go = result { try await OpenCodeReader.fetch() }
      let results = await [Provider.kimi: kimi, Provider.go: go]
      await MainActor.run {
        guard let self else { return }
        for (provider, result) in results {
          switch result {
          case let .success(snapshot):
            self.snapshots[provider] = snapshot
            self.errors.removeValue(forKey: provider)
          case let .failure(error): self.errors[provider] = error
          }
        }
        self.fetching = false
        self.rebuildMenu()
      }
    }
  }

  private func rebuildMenu() {
    updateTitle()
    let menu = NSMenu()
    statusItem.menu = menu
    for provider in Provider.allCases {
      let heading = provider == .go ? "OpenCode Go" : "Kimi Coding"
      menu.addItem(withTitle: heading, action: nil, keyEquivalent: "")
      if let snapshot = snapshots[provider] {
        if let workspace = snapshot.usage.workspace, !workspace.isEmpty {
          menu.addItem(withTitle: "Workspace: \(workspace)", action: nil, keyEquivalent: "")
        }
        for limit in snapshot.usage.windows {
          let item = NSMenuItem()
          item.view = LimitRowView(limit: limit)
          menu.addItem(item)
        }
        menu.addItem(withTitle: "Обновлено \(freshness(snapshot.timestamp))", action: nil, keyEquivalent: "")
      } else {
        menu.addItem(withTitle: "Нет данных", action: nil, keyEquivalent: "")
      }
      if let error = errors[provider] {
        let item = menu.addItem(withTitle: message(error), action: nil, keyEquivalent: "")
        item.isEnabled = false
      } else if snapshots[provider] == nil {
        menu.addItem(withTitle: "Загрузка…", action: nil, keyEquivalent: "")
      }
      let openAction = provider == .kimi ? #selector(openKimi) : #selector(openGo)
      menu.addItem(withTitle: "Открыть \(heading)", action: openAction, keyEquivalent: "").target = self
      menu.addItem(.separator())
    }
    menu.addItem(withTitle: "Обновить", action: #selector(refresh), keyEquivalent: "r").target = self
    menu.addItem(withTitle: "Закрыть Coding Limits", action: #selector(quit), keyEquivalent: "q").target = self
  }

  private func updateTitle() {
    let all = Provider.allCases.compactMap { snapshots[$0] }
    let stale = !errors.isEmpty ? " ·!" : ""
    let text = Provider.allCases.map { provider -> String in
      guard let snapshot = snapshots[provider] else { return "\(provider.shortTitle) —" }
      let values = snapshot.usage.windows.map { "\($0.remainingPercent)" }.joined(separator: "·")
      return "\(provider.shortTitle) \(values)"
    }.joined(separator: "  ") + stale
    let lowest = all.flatMap { $0.usage.windows.map(\.remainingPercent) }.min() ?? 100
    statusItem.button?.attributedTitle = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: lowest <= 10 ? NSColor.systemRed : lowest <= 20 ? .systemOrange : .labelColor,
      ]
    )
    statusItem.button?.toolTip = "Kimi Coding · OpenCode Go — остаток лимитов, %"
  }

  private func freshness(_ timestamp: Date) -> String {
    Date().timeIntervalSince(timestamp) < 60 ? "только что"
      : RelativeDateTimeFormatter().localizedString(for: timestamp, relativeTo: Date())
  }

  private func message(_ error: Error) -> String {
    (error as? UsageError)?.errorDescription ?? error.localizedDescription
  }

  @objc private func openKimi() { NSWorkspace.shared.open(Provider.kimi.dashboard) }
  @objc private func openGo() { NSWorkspace.shared.open(Provider.go.dashboard) }
  @objc private func quit() { NSApplication.shared.terminate(nil) }
}
