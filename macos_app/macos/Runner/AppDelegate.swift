import Cocoa
import FlutterMacOS

final class IncomingFileCoordinator {
  static let shared = IncomingFileCoordinator()

  private weak var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []

  private init() {}

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    deliverPendingPaths()
  }

  func enqueue(paths: [String]) {
    for path in paths where !pendingPaths.contains(path) {
      pendingPaths.append(path)
    }
    deliverPendingPaths()
  }

  func takePendingPaths() -> [String] {
    let paths = pendingPaths
    pendingPaths.removeAll()
    return paths
  }

  private func deliverPendingPaths() {
    guard let channel, !pendingPaths.isEmpty else { return }
    let paths = pendingPaths
    channel.invokeMethod("openFiles", arguments: paths) { [weak self] response in
      guard response as? Bool == true else { return }
      self?.pendingPaths.removeAll { paths.contains($0) }
    }
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFileCoordinator.shared.enqueue(
      paths: urls.filter { $0.isFileURL }.map(\.path))
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    IncomingFileCoordinator.shared.enqueue(paths: filenames)
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
