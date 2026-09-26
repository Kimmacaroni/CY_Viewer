import Cocoa
import FlutterMacOS
import PDFKit
import Vision
import CryptoKit

class MainFlutterWindow: NSWindow {
  private var securityScopedURLs: [URL] = []
  private var fileAccessChannel: FlutterMethodChannel?
  private var commandChannel: FlutterMethodChannel?
  private var updateController: MacUpdateController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    commandChannel = FlutterMethodChannel(
      name: "com.kimmacaroni.cyviewer/commands",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    let ocrChannel = FlutterMethodChannel(
      name: "com.kimmacaroni.cyviewer/ocr",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    ocrChannel.setMethodCallHandler { call, result in
      guard call.method == "recognizePdf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "PDF 경로가 없습니다.",
          details: nil))
        return
      }
      Self.recognizePdf(path: path, result: result)
    }

    let fileAccessChannel = FlutterMethodChannel(
      name: "com.kimmacaroni.cyviewer/file_access",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    self.fileAccessChannel = fileAccessChannel
    fileAccessChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "window_closed",
          message: "앱 창이 닫혀 파일 접근 권한을 처리할 수 없습니다.",
          details: nil))
        return
      }
      self.handleFileAccess(call: call, result: result)
    }
    IncomingFileCoordinator.shared.attach(channel: fileAccessChannel)

    super.awakeFromNib()
    let updater = MacUpdateController(window: self)
    updateController = updater
    let updateChannel = FlutterMethodChannel(name: "com.kimmacaroni.cyviewer/updates", binaryMessenger: flutterViewController.engine.binaryMessenger)
    updateChannel.setMethodCallHandler { call, result in
      guard call.method == "check" else { result(FlutterMethodNotImplemented); return }
      updater.check(manual: true)
      result(nil)
    }
  }

  private func sendCommand(_ command: String) {
    commandChannel?.invokeMethod(command, arguments: nil)
  }

  @objc func openPdf(_ sender: Any?) { sendCommand("open") }
  @objc func savePdfCopy(_ sender: Any?) { sendCommand("saveCopy") }
  @objc func printPdf(_ sender: Any?) { sendCommand("print") }
  @objc func findInPdf(_ sender: Any?) { sendCommand("find") }
  @objc func findNextInPdf(_ sender: Any?) { sendCommand("findNext") }
  @objc func findPreviousInPdf(_ sender: Any?) { sendCommand("findPrevious") }
  @objc func zoomInPdf(_ sender: Any?) { sendCommand("zoomIn") }
  @objc func zoomOutPdf(_ sender: Any?) { sendCommand("zoomOut") }
  @objc func showActualSizePdf(_ sender: Any?) { sendCommand("actualSize") }
  @objc func togglePdfBookmark(_ sender: Any?) { sendCommand("bookmark") }
  @objc func goToPdfPage(_ sender: Any?) { sendCommand("goToPage") }

  deinit {
    for url in securityScopedURLs {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func handleFileAccess(call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "takePendingFiles":
        result(IncomingFileCoordinator.shared.takePendingPaths())
      case "createBookmark":
        guard let arguments = call.arguments as? [String: Any] else {
          throw FileAccessError.invalidArguments
        }
        guard let path = arguments["path"] as? String else {
          throw FileAccessError.invalidPath
        }
        let data = try URL(fileURLWithPath: path).bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        result(FlutterStandardTypedData(bytes: data))
      case "resolveBookmark":
        guard let arguments = call.arguments as? [String: Any] else {
          throw FileAccessError.invalidArguments
        }
        guard let typedData = arguments["bookmark"] as? FlutterStandardTypedData else {
          throw FileAccessError.invalidBookmark
        }
        var isStale = false
        let url = try URL(
          resolvingBookmarkData: typedData.data,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale)
        if url.startAccessingSecurityScopedResource() {
          securityScopedURLs.append(url)
        }
        var response: [String: Any] = ["path": url.path]
        if isStale {
          let refreshed = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
          response["bookmark"] = FlutterStandardTypedData(bytes: refreshed)
        }
        result(response)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "file_access_failed",
        message: "파일 접근 권한을 저장할 수 없습니다: \(error.localizedDescription)",
        details: nil))
    }
  }

  private static func recognizePdf(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "open_failed",
            message: "PDF를 열 수 없습니다.",
            details: nil))
        }
        return
      }

      guard document.pageCount > 0 else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "empty_document",
            message: "페이지가 없는 PDF 문서입니다.",
            details: nil))
        }
        return
      }

      do {
        var pages: [String] = []
        for index in 0..<document.pageCount {
          try autoreleasepool {
            guard let page = document.page(at: index) else { return }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { return }

            // 비정상적으로 큰 페이지나 장문 PDF에서도 메모리 사용량이
            // 폭증하지 않도록 OCR 이미지를 긴 변 기준 2200px로 제한한다.
            let scale = min(2.0, 2200.0 / max(bounds.width, bounds.height))
            let thumbnail = page.thumbnail(
              of: NSSize(
                width: max(bounds.width * scale, 1),
                height: max(bounds.height * scale, 1)),
              for: .mediaBox)
            var imageRect = NSRect(origin: .zero, size: thumbnail.size)
            guard let image = thumbnail.cgImage(
              forProposedRect: &imageRect,
              context: nil,
              hints: nil)
            else { return }

            var recognized: [String] = []
            let request = VNRecognizeTextRequest { request, _ in
              recognized = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            }
            request.recognitionLevel = .accurate
            let supportedLanguages = try request.supportedRecognitionLanguages()
            let preferredLanguages = ["ko-KR", "en-US"].filter {
              supportedLanguages.contains($0)
            }
            if !preferredLanguages.isEmpty {
              request.recognitionLanguages = preferredLanguages
            }
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            pages.append(
              "--- \(index + 1) 페이지 ---\n" + recognized.joined(separator: "\n"))
          }
        }
        let text = pages.joined(separator: "\n\n")
        DispatchQueue.main.async { result(text) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "ocr_failed",
            message: "OCR 처리에 실패했습니다: \(error.localizedDescription)",
            details: nil))
        }
      }
    }
  }
}

private enum FileAccessError: LocalizedError {
  case invalidArguments
  case invalidPath
  case invalidBookmark

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "파일 접근 정보가 없습니다."
    case .invalidPath:
      return "파일 경로가 올바르지 않습니다."
    case .invalidBookmark:
      return "저장된 파일 접근 정보가 올바르지 않습니다."
    }
  }
}

// 배포본의 샌드박스와 파일 접근 권한을 유지하는 업데이트 다운로드 도우미.
private struct MacUpdateInfo {
  let version: String
  let fileName: String
  let url: URL
  let checksumURL: URL
  let size: Int64

  static func versionParts(_ version: String) -> [Int]? {
    guard version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { return nil }
    let values = version.split(separator: ".").compactMap { Int($0) }
    return values.count == 3 && values.allSatisfy { $0 >= 0 } ? values : nil
  }

  static func newest(_ releases: [[String: Any]], current: String) -> MacUpdateInfo? {
    guard let installed = versionParts(current) else { return nil }
    return releases.compactMap { release -> MacUpdateInfo? in
      guard release["draft"] as? Bool == false,
            release["prerelease"] as? Bool == false,
            let tag = release["tag_name"] as? String,
            tag.range(of: "^macos-v[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil
      else { return nil }
      let version = String(tag.dropFirst(7))
      guard let parts = versionParts(version), installed.lexicographicallyPrecedes(parts),
            let assets = release["assets"] as? [[String: Any]] else { return nil }
      let filename = "CYViewer-macOS-v\(version).dmg"
      let checksum = "SHA256SUMS-macOS-v\(version).txt"
      let prefix = "https://github.com/Kimmacaroni/CY_Viewer/releases/download/\(tag)/"
      guard let binary = assets.first(where: { $0["name"] as? String == filename }),
            let sums = assets.first(where: { $0["name"] as? String == checksum }),
            binary["browser_download_url"] as? String == prefix + filename,
            sums["browser_download_url"] as? String == prefix + checksum,
            let size = binary["size"] as? Int64, size > 0, size <= 250 * 1024 * 1024,
            let url = URL(string: prefix + filename), let checksumURL = URL(string: prefix + checksum)
      else { return nil }
      return MacUpdateInfo(version: version, fileName: filename, url: url, checksumURL: checksumURL, size: size)
    }.max { (versionParts($0.version) ?? []).lexicographicallyPrecedes(versionParts($1.version) ?? []) }
  }

  static func checksum(_ text: String, fileName: String) -> String? {
    for line in text.split(whereSeparator: \.isNewline) {
      let pieces = line.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: \.isWhitespace)
      guard pieces.count == 2 else { continue }
      let hash = String(pieces[0]).lowercased()
      let name = pieces[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
      if name == fileName && hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil { return hash }
    }
    return nil
  }
}

private final class MacUpdateController {
  private weak var window: NSWindow?
  private var busy = false
  private var timer: Timer?
  private var progressWindow: NSWindow?
  private var progressLabel: NSTextField?
  private var downloaded: URL?
  private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

  init(window: NSWindow) {
    self.window = window
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check(manual: false) }
    timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.check(manual: false) }
  }
  deinit { timer?.invalidate() }

  func check(manual: Bool) {
    if busy {
      if manual { progressWindow?.makeKeyAndOrderFront(nil) }
      return
    }
    if let downloaded {
      openInstaller(downloaded)
      return
    }
    busy = true
    if manual { showProgress("새 버전을 확인하고 있습니다…") }
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/Kimmacaroni/CY_Viewer/releases?per_page=100")!)
    request.timeoutInterval = 20
    request.setValue("CYViewer/\(version)", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      let releases: [[String: Any]]?
      if error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 4 * 1024 * 1024 {
        releases = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
      } else { releases = nil }
      DispatchQueue.main.async {
        self.busy = false
        self.closeProgress()
        guard let releases else {
          if manual { self.notice("업데이트 확인 실패", "인터넷 연결을 확인하고 다시 시도해 주세요.") }
          return
        }
        guard let update = MacUpdateInfo.newest(releases, current: self.version) else {
          if manual { self.notice("최신 버전입니다", "현재 CY뷰어 \(self.version)을 사용하고 있습니다.") }
          return
        }
        let alert = NSAlert()
        alert.messageText = "CY뷰어 \(update.version) 업데이트"
        alert.informativeText = "현재 버전: \(self.version)\n\n설치 파일을 다운로드하고 검증한 뒤 엽니다. 마지막으로 CYViewer.app을 Applications로 옮겨 기존 앱을 교체해 주세요."
        alert.addButton(withTitle: "다운로드")
        alert.addButton(withTitle: "나중에")
        self.present(alert) { response in
          if response == .alertFirstButtonReturn { self.download(update) }
        }
      }
    }.resume()
  }

  private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window, completionHandler: completion) }
    else { completion(alert.runModal()) }
  }
  private func notice(_ title: String, _ message: String) {
    let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
    alert.addButton(withTitle: "확인"); present(alert) { _ in }
  }
  private func showProgress(_ message: String) {
    if progressWindow == nil {
      let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
      panel.title = "CY뷰어 업데이트"
      panel.isReleasedWhenClosed = false
      let label = NSTextField(wrappingLabelWithString: message)
      label.frame = NSRect(x: 24, y: 50, width: 332, height: 44)
      let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 24, width: 332, height: 16))
      progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
      panel.contentView?.addSubview(label); panel.contentView?.addSubview(progress)
      panel.center(); progressWindow = panel; progressLabel = label
    }
    progressLabel?.stringValue = message
    progressWindow?.orderFront(nil)
  }
  private func closeProgress() { progressWindow?.orderOut(nil) }
  private func fail(_ message: String) {
    DispatchQueue.main.async { self.busy = false; self.closeProgress(); self.notice("업데이트를 완료하지 못했습니다", message) }
  }

  private func download(_ update: MacUpdateInfo) {
    busy = true
    showProgress("설치 파일을 다운로드하고 검증합니다…")
    var request = URLRequest(url: update.checksumURL); request.timeoutInterval = 30
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
            let data, data.count <= 65536, let text = String(data: data, encoding: .utf8),
            let expected = MacUpdateInfo.checksum(text, fileName: update.fileName)
      else { self.fail("설치 파일의 검증 정보를 받지 못했습니다. 다시 시도해 주세요."); return }
      var packageRequest = URLRequest(url: update.url); packageRequest.timeoutInterval = 300
      URLSession.shared.downloadTask(with: packageRequest) { [weak self] temporary, response, error in
        guard let self else { return }
        guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
              response?.url?.scheme == "https", let temporary
        else { self.fail("설치 파일을 다운로드하지 못했습니다. 다시 시도해 주세요."); return }
        do {
          let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
          guard (attributes[.size] as? NSNumber)?.int64Value == update.size else { throw UpdateError.invalidFile }
          let handle = try FileHandle(forReadingFrom: temporary)
          defer { try? handle.close() }
          var hash = SHA256()
          while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
          let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
          guard actual == expected else { throw UpdateError.invalidFile }
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CYViewer-update-" + UUID().uuidString)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let target = directory.appendingPathComponent(update.fileName)
          try FileManager.default.moveItem(at: temporary, to: target)
          DispatchQueue.main.async {
            self.downloaded = target; self.busy = false; self.closeProgress(); self.openInstaller(target)
          }
        } catch { self.fail("설치 파일 검증에 실패했습니다. 다시 다운로드해 주세요.") }
      }.resume()
    }.resume()
  }

  private func openInstaller(_ url: URL) {
    let alert = NSAlert()
    alert.messageText = "설치 파일이 준비되었습니다"
    alert.informativeText = "작업한 문서를 저장하세요. DMG를 연 뒤 CY뷰어를 종료하고 CYViewer.app을 Applications로 옮겨 교체합니다. 앱을 자동으로 종료하거나 문서를 닫지 않습니다."
    alert.addButton(withTitle: "설치 파일 열기"); alert.addButton(withTitle: "나중에")
    present(alert) { response in
      if response == .alertFirstButtonReturn && !NSWorkspace.shared.open(url) {
        self.notice("설치 파일을 열 수 없습니다", "배포 사이트에서 설치 파일을 받아 주세요.\nhttps://kimmacaroni.github.io/CY_Viewer/download/")
      }
    }
  }
  private enum UpdateError: Error { case invalidFile }
}
