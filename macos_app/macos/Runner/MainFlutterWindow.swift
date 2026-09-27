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
          message: cyNativeTr("PDF 경로가 없습니다."),
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
          message: cyNativeTr("앱 창이 닫혀 파일 접근 권한을 처리할 수 없습니다."),
          details: nil))
        return
      }
      self.handleFileAccess(call: call, result: result)
    }
    IncomingFileCoordinator.shared.attach(channel: fileAccessChannel)

    super.awakeFromNib()
    let languageChannel = FlutterMethodChannel(name: "com.kimmacaroni.cyviewer/language", binaryMessenger: flutterViewController.engine.binaryMessenger)
    languageChannel.setMethodCallHandler { call, result in
      guard call.method == "set", let mode = call.arguments as? String,
            ["ko", "en", "system"].contains(mode) else { result(FlutterMethodNotImplemented); return }
      UserDefaults.standard.set(mode, forKey: "cy_language")
      cyTranslateMenu(NSApp.mainMenu)
      result(nil)
    }
    cyTranslateMenu(NSApp.mainMenu)
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
        message: cyNativeTr("파일 접근 권한을 저장할 수 없습니다: {0}", [String(describing: error.localizedDescription)]),
        details: nil))
    }
  }

  private static func recognizePdf(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "open_failed",
            message: cyNativeTr("PDF를 열 수 없습니다."),
            details: nil))
        }
        return
      }

      guard document.pageCount > 0 else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "empty_document",
            message: cyNativeTr("페이지가 없는 PDF 문서입니다."),
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
              cyNativeTr("--- {0} 페이지 ---\n", [String(describing: index + 1)]) + recognized.joined(separator: "\n"))
          }
        }
        let text = pages.joined(separator: "\n\n")
        DispatchQueue.main.async { result(text) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "ocr_failed",
            message: cyNativeTr("OCR 처리에 실패했습니다: {0}", [String(describing: error.localizedDescription)]),
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
      return cyNativeTr("파일 접근 정보가 없습니다.")
    case .invalidPath:
      return cyNativeTr("파일 경로가 올바르지 않습니다.")
    case .invalidBookmark:
      return cyNativeTr("저장된 파일 접근 정보가 올바르지 않습니다.")
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
    if manual { showProgress(cyNativeTr("새 버전을 확인하고 있습니다…")) }
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
          if manual { self.notice(cyNativeTr("업데이트 확인 실패"), cyNativeTr("인터넷 연결을 확인하고 다시 시도해 주세요.")) }
          return
        }
        guard let update = MacUpdateInfo.newest(releases, current: self.version) else {
          if manual { self.notice(cyNativeTr("최신 버전입니다"), cyNativeTr("현재 CY뷰어 {0}을 사용하고 있습니다.", [String(describing: self.version)])) }
          return
        }
        let alert = NSAlert()
        alert.messageText = cyNativeTr("CY뷰어 {0} 업데이트", [String(describing: update.version)])
        alert.informativeText = cyNativeTr("현재 버전: {0}\n\n설치 파일을 다운로드하고 검증한 뒤 엽니다. 마지막으로 CYViewer.app을 Applications로 옮겨 기존 앱을 교체해 주세요.", [String(describing: self.version)])
        alert.addButton(withTitle: cyNativeTr("다운로드"))
        alert.addButton(withTitle: cyNativeTr("나중에"))
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
    alert.addButton(withTitle: cyNativeTr("확인")); present(alert) { _ in }
  }
  private func showProgress(_ message: String) {
    if progressWindow == nil {
      let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
      panel.title = cyNativeTr("CY뷰어 업데이트")
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
    DispatchQueue.main.async { self.busy = false; self.closeProgress(); self.notice(cyNativeTr("업데이트를 완료하지 못했습니다"), message) }
  }

  private func download(_ update: MacUpdateInfo) {
    busy = true
    showProgress(cyNativeTr("설치 파일을 다운로드하고 검증합니다…"))
    var request = URLRequest(url: update.checksumURL); request.timeoutInterval = 30
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
            let data, data.count <= 65536, let text = String(data: data, encoding: .utf8),
            let expected = MacUpdateInfo.checksum(text, fileName: update.fileName)
      else { self.fail(cyNativeTr("설치 파일의 검증 정보를 받지 못했습니다. 다시 시도해 주세요.")); return }
      var packageRequest = URLRequest(url: update.url); packageRequest.timeoutInterval = 300
      URLSession.shared.downloadTask(with: packageRequest) { [weak self] temporary, response, error in
        guard let self else { return }
        guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200,
              response?.url?.scheme == "https", let temporary
        else { self.fail(cyNativeTr("설치 파일을 다운로드하지 못했습니다. 다시 시도해 주세요.")); return }
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
        } catch { self.fail(cyNativeTr("설치 파일 검증에 실패했습니다. 다시 다운로드해 주세요.")) }
      }.resume()
    }.resume()
  }

  private func openInstaller(_ url: URL) {
    let alert = NSAlert()
    alert.messageText = cyNativeTr("설치 파일이 준비되었습니다")
    alert.informativeText = cyNativeTr("작업한 문서를 저장하세요. DMG를 연 뒤 CY뷰어를 종료하고 CYViewer.app을 Applications로 옮겨 교체합니다. 앱을 자동으로 종료하거나 문서를 닫지 않습니다.")
    alert.addButton(withTitle: cyNativeTr("설치 파일 열기")); alert.addButton(withTitle: cyNativeTr("나중에"))
    present(alert) { response in
      if response == .alertFirstButtonReturn && !NSWorkspace.shared.open(url) {
        self.notice(cyNativeTr("설치 파일을 열 수 없습니다"), cyNativeTr("배포 사이트에서 설치 파일을 받아 주세요.\nhttps://kimmacaroni.github.io/CY_Viewer/download/"))
      }
    }
  }
  private enum UpdateError: Error { case invalidFile }
}

// Flutter와 같은 언어를 기본 메뉴와 업데이트 알림에도 적용한다.
private var cyOriginalMenuTitles: [ObjectIdentifier: String] = [:]
private func cyTranslateMenu(_ menu: NSMenu?) {
  guard let menu else { return }
  for item in menu.items {
    let key = ObjectIdentifier(item)
    let original = cyOriginalMenuTitles[key] ?? item.title
    cyOriginalMenuTitles[key] = original
    item.title = cyNativeTr(original)
    cyTranslateMenu(item.submenu)
  }
}
private func cyNativeTr(_ source: String, _ args: [String] = []) -> String {
  let mode = UserDefaults.standard.string(forKey: "cy_language") ?? "system"
  let code = mode == "system" ? (Locale.preferredLanguages.first ?? "en") : mode
  let text = code.hasPrefix("ko") ? source : (cyNativeEnglish[source] ?? source)
  let result = NSMutableString(string: text)
  let regex = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
  for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
    let index = Int((text as NSString).substring(with: match.range(at: 1)))!
    if index < args.count { result.replaceCharacters(in: match.range, with: args[index]) }
  }
  return result as String
}
// BEGIN GENERATED TRANSLATIONS
private let cyNativeEnglish: [String: String] = [
  "CY뷰어": "CY Viewer",
  "외부에서 전달한 PDF를 열 수 없습니다: {0}": "Could not open the shared PDF: {0}",
  "문서 목록 형식 오류": "Invalid document list",
  "파일 선택 창을 열 수 없습니다: {0}": "Could not open the file picker: {0}",
  "PDF 파일만 열 수 있습니다.": "Only PDF files can be opened.",
  "파일을 찾을 수 없습니다.": "File not found.",
  "최근 문서 목록을 저장하지 못했습니다: {0}": "Could not save recent documents: {0}",
  "파일이 이동되었거나 삭제되었습니다.": "The file has been moved or deleted.",
  "즐겨찾기를 저장하지 못했습니다: {0}": "Could not save favorites: {0}",
  "문서함": "Library",
  "{0}개의 문서 · 이 기기에 저장됨": "{0} documents · Stored on this device",
  "전체 문서": "All documents",
  "즐겨찾기": "Favorites",
  "즐겨찾는 문서가 없습니다": "No favorite documents",
  "문서 옆의 별을 누르면 여기에 모아 볼 수 있습니다.": "Select the star next to a document to find it here.",
  "전체 문서 보기": "Show all documents",
  "PDF 열기": "Open PDF",
  "{0}페이지에서 이어 읽기 · {1}": "Continue on page {0} · {1}",
  "즐겨찾기 해제": "Remove from favorites",
  "즐겨찾기에 추가": "Add to favorites",
  "업데이트 확인": "Check for updates",
  "업데이트를 확인하지 못했습니다. 다시 시도해 주세요.": "Could not check for updates. Please try again.",
  "PDF 파일을 끌어놓아 주세요.": "Please drop a PDF file.",
  "여기에 PDF를 놓아 열기": "Drop a PDF here to open",
  "페이지로 이동": "Go to page",
  "취소": "Cancel",
  "이동": "Go",
  "축소": "Zoom out",
  "확대": "Zoom in",
  "페이지 이동": "Go to page",
  "빈 PDF 파일입니다.": "This PDF is empty.",
  "PDF를 읽을 수 없습니다": "Cannot read this PDF",
  "파일 접근 권한이 만료되었을 수 있습니다. 다시 시도하거나 문서함에서 PDF를 다시 선택해 주세요.": "File access may have expired. Try again or select the PDF again from your library.",
  "다시 시도": "Try again",
  "문서함으로 돌아가기": "Back to library",
  "책갈피를 불러오지 못했습니다: {0}": "Could not load bookmarks: {0}",
  "책갈피를 저장하지 못했습니다: {0}": "Could not save bookmarks: {0}",
  "저장한 책갈피가 없습니다.": "No saved bookmarks.",
  "{0} 페이지": "Page {0}",
  "삭제": "Delete",
  "먼저 문서의 텍스트를 드래그해 선택해 주세요.": "Select text in the document first.",
  "인쇄할 문서를 준비하고 있습니다…": "Preparing the document for printing…",
  "인쇄 창을 열 수 없습니다: {0}": "Could not open the print dialog: {0}",
  "파일을 준비하고 있습니다…": "Preparing files…",
  "PDF로 저장": "Save as PDF",
  "{0}-복사본.pdf": "{0}-copy.pdf",
  "PDF 복사본을 저장했습니다.": "PDF copy saved.",
  "PNG 저장 폴더 선택": "Choose a folder for PNG files",
  "JPG 저장 폴더 선택": "Choose a folder for JPG files",
  "페이지 {0} / {1} 저장 중…": "Saving page {0} of {1}…",
  "페이지 이미지를 변환할 수 없습니다.": "Could not convert the page image.",
  "{0}개 페이지를 저장했습니다.": "Saved {0} pages.",
  "저장할 수 없습니다: {0}": "Could not save: {0}",
  "문서 전체의 글자를 인식하고 있습니다…": "Recognizing text in the document…",
  "OCR 결과": "OCR results",
  "인식된 텍스트가 없습니다.": "No text was recognized.",
  "전체 복사": "Copy all",
  "닫기": "Close",
  "OCR을 실행할 수 없습니다.": "Could not run OCR.",
  "OCR을 실행할 수 없습니다: {0}": "Could not run OCR: {0}",
  "CY뷰어 사용 방법": "Using CY Viewer",
  "• ⌘O: PDF 열기\n• ⌘F: 문서 검색\n• ⌘G / ⇧⌘G: 다음·이전 검색 결과\n• ⌘+ / ⌘- / ⌘0: 확대·축소·실제 크기\n• ⌘S: PDF 복사본 저장\n• ⌘P: 인쇄\n• 텍스트 드래그 후 하단 도구막대: 복사·형광펜·밑줄·취소선·강조": "• ⌘O: Open PDF\n• ⌘F: Search document\n• ⌘G / ⇧⌘G: Next / previous result\n• ⌘+ / ⌘- / ⌘0: Zoom in / out / actual size\n• ⌘S: Save PDF copy\n• ⌘P: Print\n• Select text, then use the bottom toolbar to copy, highlight, underline, strike through or emphasize",
  "• 돋보기: 문서 텍스트 검색\n• 문서 도구: 책갈피, 확대·축소, 페이지 이동, 인쇄, OCR, 저장\n• 화면을 두 손가락으로 확대·축소\n• 텍스트를 길게 누르거나 드래그한 뒤 하단 도구막대에서 복사·형광펜·밑줄·취소선·강조": "• Search: Find text in the document\n• Document tools: Bookmarks, zoom, go to page, print, OCR and save\n• Pinch with two fingers to zoom\n• Select text, then use the bottom toolbar to copy, highlight, underline, strike through or emphasize",
  "확인": "OK",
  "문서 도구": "Document tools",
  "macOS와 동일한 기능을 사용할 수 있습니다.": "The same features are available on macOS.",
  "책갈피 목록": "Bookmarks",
  "세로": "Vertical",
  "가로": "Horizontal",
  "두 쪽": "Two pages",
  "실제 크기": "Actual size",
  "인쇄": "Print",
  "문서 전체 OCR": "OCR entire document",
  "PDF 복사본 저장": "Save PDF copy",
  "PNG로 저장": "Save as PNG",
  "JPG로 저장": "Save as JPG",
  "이 문서의 표시 지우기": "Clear document annotations",
  "사용 방법": "Help",
  "문서에서 검색": "Search document",
  "이전 결과": "Previous result",
  "다음 결과": "Next result",
  "검색 닫기": "Close search",
  "검색": "Search",
  "책갈피 삭제": "Remove bookmark",
  "이 페이지 책갈피": "Bookmark this page",
  "문구를 드래그해 선택한 뒤 복사하거나 표시하세요.": "Select text to copy or annotate it.",
  "PDF 열기 실패: {0}": "PDF open failed: {0}",
  "PDF를 열 수 없습니다": "Cannot open this PDF",
  "파일이 이동되었거나 접근 권한이 변경되었을 수 있습니다. ": "The file may have moved or its access permissions may have changed. ",
  "문서함으로 돌아가 PDF를 다시 선택해 주세요.": "Go back to the library and select the PDF again.",
  "페이지가 없는 PDF 문서입니다.": "This PDF has no pages.",
  "복사": "Copy",
  "형광펜": "Highlight",
  "밑줄": "Underline",
  "취소선": "Strikethrough",
  "강조": "Emphasize",
  "문서 작업 공간": "Document workspace",
  "문서를 열고,\n바로 읽으세요.": "Open a document.\nStart reading.",
  "설치 없이, 파일 하나로 시작하세요.\n필요한 문구를 찾고 중요한 페이지를 남겨 보세요.": "Start with a file, no installation needed.\nFind text and bookmark important pages.",
  "최근 문서와 읽던 페이지를 한곳에서.\nPDF를 선택하거나 이 창에 끌어놓으세요.": "Recent documents and your reading progress in one place.\nChoose a PDF or drop it into this window.",
  "찾고 읽기": "Find and read",
  "문서 검색 · 확대 · 보기 방식 변경": "Search · Zoom · Reading layouts",
  "중요한 페이지 남기기": "Keep important pages",
  "책갈피로 필요한 곳을 빠르게 찾기": "Find your place with bookmarks",
  "저장하고 공유하기": "Save and share",
  "표시하고 저장하기": "Annotate and save",
  "PDF 사본 저장 · 공유 · 인쇄": "Save PDF copies · Share · Print",
  "텍스트 표시 · OCR · PDF와 이미지 저장": "Annotate · OCR · Export PDF and images",
  "어떤 문서를 읽을까요?": "What would you like to read?",
  "이 기기에 있는 PDF 파일을 선택하세요.": "Choose a PDF file on this device.",
  "파일을 선택하면 문서함에 추가됩니다.": "Choose a file to add it to your library.",
  "문서는 서버로 전송되지 않습니다.\n웹앱을 닫으면 PDF 원본은 남지 않습니다.": "Documents are not uploaded to a server.\nThe PDF is not retained after closing the web app.",
  "문서와 최근 열람 목록은\n이 기기에서만 관리합니다.": "Documents and reading history\nstay on this device.",
  "01  문서 탐색": "01  Navigate",
  "문서 검색": "Search document",
  "보기 방식 · 책갈피 목록": "Reading layout · Bookmarks",
  "02  선택·편집": "02  Select and edit",
  "문구를 드래그해 선택하고 복사하세요.": "Select text to copy it.",
  "03  저장·내보내기": "03  Save and export",
  "선택한 PDF를 읽지 못했습니다.": "Could not read the selected PDF.",
  "PDF를 열 수 없습니다. 다시 선택해 주세요. ({0})": "Could not open the PDF. Please choose it again. ({0})",
  "설치 방법": "How to install",
  "아이폰에 설치하기": "Install on iPhone",
  "Safari 아래쪽의 공유 버튼을 누른 다음 ": "Tap Share in Safari, then ",
  "“홈 화면에 추가”를 선택하세요. 이후 CY뷰어 아이콘으로 실행할 수 있습니다.": "select “Add to Home Screen”. Launch CY Viewer from its home screen icon.",
  "책갈피를 저장했습니다.": "Bookmark saved.",
  "책갈피를 삭제했습니다.": "Bookmark removed.",
  "공유 또는 파일 저장 화면을 열었습니다.": "Opened the share or save dialog.",
  "PDF 복사본을 내보낼 수 없습니다: {0}": "Could not export the PDF copy: {0}",
  "읽기와 저장 기능": "Reading and saving",
  "PDF 복사본 저장·공유": "Save or share a PDF copy",
  "브라우저로 PDF 열기": "Open PDF in browser",
  "웹 버전 안내": "About the web version",
  "OCR과 페이지 이미지 저장은 브라우저 제한으로 제공되지 않습니다.": "OCR and page image export are not available in the web version.",
  "PDF 페이지를 불러오고 있습니다.": "Loading PDF pages…",
  "PDF를 표시할 수 없습니다.": "Cannot display this PDF.",
  "다른 PDF 선택": "Choose another PDF",
  "PDF 읽기를 완료하지 못했습니다.": "Could not finish loading the PDF.",
  "PDF를 준비하고 있습니다.": "Preparing your PDF…",
  "브라우저 기본 뷰어로 열거나 다른 PDF를 선택해 주세요.": "Open it in the browser viewer or choose another PDF.",
  "처음에는 읽기 도구를 내려받는 데 시간이 걸릴 수 있습니다.": "The reader tools may take a moment to download the first time.",
  "PDF 읽는 중": "Reading PDF",
  "PDF 데이터를 읽지 못했습니다.": "Could not read PDF data.",
  "PDF 파일 읽기에 실패했습니다.": "Failed to read the PDF file.",
  "새 문서 없음": "No document",
  "CY뷰어 | 개인용 PDF 뷰어": "CY Viewer | PDF Viewer",
  "◀ 이전": "◀ Previous",
  "다음 ▶": "Next ▶",
  "문구를 드래그해 선택하면\n이곳에서 선택한 내용을\n확인할 수 있어요.": "Select text in the document\nto review your selection\nhere.",
  "PDF를 선택하거나 이 창에 끌어놓으세요.": "Choose a PDF or drop it into this window.",
  "문서는 이 기기에서만 처리합니다.": "Documents are processed only on this device.",
  "저장 필요": "Unsaved changes",
  "  ★ 책갈피": "  ★ Bookmarked",
  "  |  문구 선택됨: 왼쪽에서 표시 또는 수정": "  |  Text selected: annotate or edit in the left panel",
  "  |  저장 필요": "  |  Unsaved changes",
  "선택 종류: {0}": "Selection type: {0}",
  "{0} 표시를 적용했습니다.": "Applied {0}.",
  "굵게 처리": "Make bold",
  "원문을 굵은 글꼴로 교체합니다. 계속할까요?": "Replace the selected text with a bold font? Continue?",
  "문구 수정": "Edit text",
  "새 문구를 입력하세요.": "Enter the new text.",
  "인쇄 미리보기 | CY뷰어": "Print preview | CY Viewer",
  "프린터 설정 및 인쇄": "Printer settings and print",
  "CY뷰어 - {0}": "CY Viewer - {0}",
  "이동할 페이지 번호를 입력하세요. (1~{0})": "Enter a page number. (1–{0})",
  "저장된 페이지: {0}\n이동할 페이지 번호:": "Saved pages: {0}\nPage to open:",
  "선택한 내용": "Selection",
  "스크롤 보기": "Scroll",
  "선택 없음": "No selection",
  "텍스트 복사": "Copy text",
  "PDF 열기를 눌러 문서를 선택하세요.": "Select Open PDF to choose a document.",
  "PDF 파일 선택": "Choose a PDF file",
  "변경 없음": "No changes",
  "{0} / {1} 페이지   |   {2}   |   확대 {3}%{4}{5}{6}": "Page {0} / {1}   |   {2}   |   Zoom {3}%{4}{5}{6}",
  "좌우 보기": "Horizontal",
  "유효한 영역이 선택되지 않았습니다.\n문구, 이미지 또는 빈 공간을\n조금 더 넓게 드래그해 보세요.": "No valid selection.\nTry selecting a larger area\nwith text or an image.",
  "OCR 엔진을 찾을 수 없습니다. Tesseract OCR을 설치한 뒤 다시 시도하세요.": "OCR engine not found. Install Tesseract OCR and try again.",
  "한국어·영어 OCR 언어 데이터를 찾을 수 없습니다.": "Korean and English OCR language data not found.",
  "먼저 PDF를 열어 주세요.": "Open a PDF first.",
  "선택 텍스트를 클립보드에 복사했습니다. ({0}자)": "Copied selected text to the clipboard. ({0} characters)",
  "텍스트": "Text",
  "이미지 {0}개": "{0} images",
  "빈 공간": "Empty space",
  "문서에서 문구를 드래그해 먼저 선택하세요.": "Select text in the document first.",
  "원래 글자 크기를 유지할 공간이 부족합니다. 글자를 축소하지 않았으며 원문도 바꾸지 않았습니다.": "Not enough space to keep the original font size. The original text has not been changed or reduced.",
  "문구를 변경했습니다.": "Text updated.",
  "선택 문구를 굵게 처리했습니다.": "Selected text made bold.",
  "기존 문구를 새 문구로 바꿉니다. 이 변경은 저장 전까지 되돌릴 수 없습니다. 계속할까요?": "Replace the selected text? This change cannot be undone before saving. Continue?",
  "편집한 PDF 저장": "Save edited PDF",
  "저장 완료": "Saved",
  "편집한 PDF를 저장했습니다.": "Edited PDF saved.",
  "현재 페이지를 {0}로 저장": "Save current page as {0}",
  "현재 페이지를 {0} 이미지로 저장했습니다.": "Saved the current page as a {0} image.",
  "저장된 책갈피가 없습니다.": "No saved bookmarks.",
  "＋  PDF 열기": "＋  Open PDF",
  "  |  오른쪽이 아닌 왼쪽 아래 ‘PDF로 저장’으로 사본을 보관하세요.": "  |  Use “Save as PDF” in the lower left panel to save a copy.",
  "텍스트 선택됨 · {0}자": "Text selected · {0} characters",
  "{0} · 읽기 및 편집 가능": "{0} · Ready to read and edit",
  "PDF를 열 수 없습니다.\n\n{0}": "Could not open the PDF.\n\n{0}",
  "PDF를 열어 시작하세요": "Open a PDF to start",
  "PDF 열기 또는 끌어놓기\n읽기·검색 → 문구 선택 → 편집 → 저장": "Open or drop a PDF\nRead and search → Select text → Edit → Save",
  "왼쪽의 ‘PDF 열기’ 버튼으로 시작하세요.": "Start with “Open PDF” in the left panel.",
  "문서 OCR을 마쳤습니다.\n\n인식 단어: {0}개\n실패한 페이지: {1}": "Document OCR finished.\n\nWords recognized: {0}\nFailed pages: {1}",
  "문서 전체 OCR이 완료됐습니다.\n\n페이지: {0}개\n인식 단어: {1}개\n이제 모든 페이지에서 검색·선택·복사·표시·수정할 수 있습니다.": "Document OCR completed.\n\nPages: {0}\nWords recognized: {1}\nYou can now search, select, copy, annotate and edit all pages.",
  "OCR을 실행할 수 없습니다.\n\n{0}": "Could not run OCR.\n\n{0}",
  "선택 검사 · ": "Inspect selection · ",
  "선택한 텍스트": "Selected text",
  "텍스트는 형광펜·밑줄·취소선·굵게·문구 수정을 사용할 수 있습니다.": "Use highlight, underline, strikethrough, bold or edit on selected text.",
  "먼저 문구를 드래그해 선택한 뒤 마우스 오른쪽 버튼을 누르세요.": "Select text, then right-click.",
  "저장 완료 · {0}": "Saved · {0}",
  "저장할 수 없습니다.\n\n{0}": "Could not save.\n\n{0}",
  "현재 페이지를 {0}으로 저장했습니다.": "Saved the current page as {0}.",
  "이미지로 저장할 수 없습니다.\n\n{0}": "Could not save the image.\n\n{0}",
  "Windows 인쇄 미리보기를 준비하고 있습니다…": "Preparing Windows print preview…",
  "Windows 인쇄 미리보기를 열 수 없습니다.\n\n{0}": "Could not open Windows print preview.\n\n{0}",
  "{0} / {1} 페이지 · {2}%": "Page {0} / {1} · {2}%",
  "Windows 인쇄 대기열에 작업을 만들지 못했습니다.": "Could not create a Windows print job.",
  "작업 #{0} · ": "Job #{0} · ",
  "인쇄 작업을 Windows 대기열에 보냈습니다.\n\n{0}페이지: {1}~{2}": "Sent the print job to Windows.\n\n{0} pages: {1}–{2}",
  "인쇄를 시작할 수 없습니다.\n\n{0}": "Could not start printing.\n\n{0}",
  "결과 없음": "No results",
  "문구를 드래그해 선택한 뒤\n마우스 오른쪽 버튼을 누르세요.\n\n형광펜 · 밑줄 · 취소선 · 굵게\n문구 수정 · 텍스트 복사를 제공합니다.": "Select text, then right-click.\n\nHighlight · Underline · Strikethrough · Bold\nEdit text · Copy text",
  "읽기": "Read",
  "이미지 선택됨": "Image selected",
  "PDF 문서": "PDF document",
  "OCR 엔진이 결과를 만들지 못했습니다.": "The OCR engine produced no output.",
  "OCR 진행 중 · {0} / {1} 페이지를 인식하고 있습니다…": "OCR in progress · Page {0} / {1}…",
  "OCR 완료 · {0} / {1} 페이지, {2}개 단어 인식": "OCR completed · Page {0} / {1}, {2} words",
  "OCR 완료 · 전체 {0}페이지에서 {1}개 단어를 인식했습니다.": "OCR completed · {1} words across {0} pages.",
  "OCR 실패": "OCR failed",
  "선택 영역에 이미지가 있습니다.": "The selection contains an image.",
  "현재 버전에서는 이미지를 확인할 수 있으며, 이미지 편집 기능은 준비 중입니다.": "Images can be viewed. Image editing is not yet available.",
  "선택 영역에 텍스트나 이미지가 없습니다.": "The selection contains no text or images.",
  "빈 공간에는 표시·문구 수정 기능을 적용할 수 없습니다.": "Annotations and text editing cannot be applied to empty space.",
  "{0} 이미지": "{0} image",
  "인쇄 미리보기": "Print preview",
  "Windows 인쇄 대화상자 오류: {0}": "Windows print dialog error: {0}",
  "인쇄가 취소됐습니다.": "Printing canceled.",
  "선택한 프린터의 인쇄 가능 영역을 확인할 수 없습니다.": "Could not determine the printable area of the selected printer.",
  "인쇄 대기열 전송 완료 · {0}{1}~{2}페이지": "Sent to print queue · {0}Pages {1}–{2}",
  "{0}페이지 인쇄 작업을 시작하지 못했습니다.": "Could not start printing page {0}.",
  "{0}페이지를 인쇄 대기열에 보내지 못했습니다.": "Could not send page {0} to the print queue.",
  "설치 파일의 검증 정보를 찾을 수 없습니다.": "Installer checksum information not found.",
  "버전 형식이 올바르지 않습니다.": "Invalid version format.",
  "업데이트 응답이 너무 큽니다.": "Update response is too large.",
  "업데이트 목록을 읽을 수 없습니다.": "Could not read the update list.",
  "업데이트 확인 중…": "Checking for updates…",
  "다운로드 0%": "Downloading 0%",
  "HTTPS가 아닌 다운로드 주소입니다.": "Download URL must use HTTPS.",
  "설치 파일 검증에 실패했습니다. 다시 다운로드해 주세요.": "Installer verification failed. Please download it again.",
  "CY뷰어 업데이트": "CY Viewer update",
  "개발 실행에서는 설치를 시작하지 않습니다.": "Installation is not available when running from source.",
  "저장하지 않은 변경이 있습니다. PDF를 저장한 뒤 업데이트 설치를 다시 눌러 주세요.": "You have unsaved changes. Save your PDF before installing the update.",
  "다운로드와 검증이 완료되었습니다.\n\nCY뷰어를 종료하고 업데이트를 설치한 뒤 다시 실행할까요?": "Download and verification completed.\n\nClose CY Viewer, install the update and restart?",
  "설치를 시작하지 못했습니다.\n{0}": "Could not start installation.\n{0}",
  "설치 파일 크기가 일치하지 않습니다.": "Installer size does not match.",
  "다운로드 {0}%": "Downloading {0}%",
  "업데이트를 확인할 수 없습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.": "Could not check for updates. Check your internet connection and try again.",
  "새 버전 {0}이 있습니다.\n현재 버전: {1}\n\n설치 파일을 다운로드할까요? 문서는 계속 사용할 수 있습니다.": "Version {0} is available.\nCurrent version: {1}\n\nDownload the installer? You can keep using your document.",
  "업데이트 설치": "Install update",
  "업데이트를 다운로드하지 못했습니다.\n{0}": "Could not download the update.\n{0}",
  "현재 최신 버전({0})입니다.": "You are up to date ({0}).",
  "업데이트 재시도": "Retry update",
  "PDF 경로가 없습니다.": "PDF path is missing.",
  "앱 창이 닫혀 파일 접근 권한을 처리할 수 없습니다.": "The app window is closed; file access cannot be processed.",
  "파일 접근 권한을 저장할 수 없습니다: {0}": "Could not save file access permission: {0}",
  "PDF를 열 수 없습니다.": "Could not open the PDF.",
  "--- {0} 페이지 ---\n": "--- Page {0} ---\n",
  "OCR 처리에 실패했습니다: {0}": "OCR failed: {0}",
  "파일 접근 정보가 없습니다.": "File access information is missing.",
  "파일 경로가 올바르지 않습니다.": "Invalid file path.",
  "저장된 파일 접근 정보가 올바르지 않습니다.": "Invalid saved file access information.",
  "새 버전을 확인하고 있습니다…": "Checking for a new version…",
  "업데이트 확인 실패": "Update check failed",
  "인터넷 연결을 확인하고 다시 시도해 주세요.": "Check your internet connection and try again.",
  "최신 버전입니다": "You are up to date",
  "현재 CY뷰어 {0}을 사용하고 있습니다.": "You are using CY Viewer {0}.",
  "CY뷰어 {0} 업데이트": "CY Viewer {0} update",
  "현재 버전: {0}\n\n설치 파일을 다운로드하고 검증한 뒤 엽니다. 마지막으로 CYViewer.app을 Applications로 옮겨 기존 앱을 교체해 주세요.": "Current version: {0}\n\nThe installer will be downloaded, verified and opened. Then move CYViewer.app to Applications to replace the existing app.",
  "다운로드": "Download",
  "나중에": "Later",
  "업데이트를 완료하지 못했습니다": "Could not complete the update",
  "설치 파일을 다운로드하고 검증합니다…": "Downloading and verifying the installer…",
  "설치 파일의 검증 정보를 받지 못했습니다. 다시 시도해 주세요.": "Could not get installer verification information. Please try again.",
  "설치 파일을 다운로드하지 못했습니다. 다시 시도해 주세요.": "Could not download the installer. Please try again.",
  "설치 파일이 준비되었습니다": "Installer is ready",
  "작업한 문서를 저장하세요. DMG를 연 뒤 CY뷰어를 종료하고 CYViewer.app을 Applications로 옮겨 교체합니다. 앱을 자동으로 종료하거나 문서를 닫지 않습니다.": "Save your documents. After opening the DMG, quit CY Viewer and move CYViewer.app to Applications to replace it. Your app and documents will not be closed automatically.",
  "설치 파일 열기": "Open installer",
  "설치 파일을 열 수 없습니다": "Could not open the installer",
  "배포 사이트에서 설치 파일을 받아 주세요.\nhttps://kimmacaroni.github.io/CY_Viewer/download/": "Download the installer from the download site.\nhttps://kimmacaroni.github.io/CY_Viewer/download/",
  "주 메뉴": "Main Menu",
  "CY뷰어 정보": "About CY Viewer",
  "설정…": "Settings…",
  "서비스": "Services",
  "APP_NAME 가리기": "Hide APP_NAME",
  "기타 가리기": "Hide Others",
  "모두 보기": "Show All",
  "APP_NAME 종료": "Quit APP_NAME",
  "파일": "File",
  "PDF 열기…": "Open PDF…",
  "PDF 복사본 저장…": "Save PDF Copy…",
  "인쇄…": "Print…",
  "창 닫기": "Close Window",
  "편집": "Edit",
  "실행 취소": "Undo",
  "다시 실행": "Redo",
  "잘라내기": "Cut",
  "붙여넣기": "Paste",
  "스타일에 맞춰 붙여넣기": "Paste and Match Style",
  "모두 선택": "Select All",
  "찾기": "Find",
  "찾기…": "Find…",
  "찾아서 바꾸기…": "Find and Replace…",
  "다음 찾기": "Find Next",
  "이전 찾기": "Find Previous",
  "선택 부분으로 찾기": "Use Selection for Find",
  "선택 부분으로 이동": "Jump to Selection",
  "맞춤법 및 문법": "Spelling and Grammar",
  "맞춤법": "Spelling",
  "맞춤법 및 문법 보기": "Show Spelling and Grammar",
  "지금 문서 검사": "Check Document Now",
  "입력하는 동안 맞춤법 검사": "Check Spelling While Typing",
  "맞춤법과 함께 문법 검사": "Check Grammar With Spelling",
  "맞춤법 자동 수정": "Correct Spelling Automatically",
  "대치": "Substitutions",
  "대치 보기": "Show Substitutions",
  "스마트 복사/붙여넣기": "Smart Copy/Paste",
  "스마트 인용 부호": "Smart Quotes",
  "스마트 대시": "Smart Dashes",
  "스마트 링크": "Smart Links",
  "데이터 감지기": "Data Detectors",
  "텍스트 대치": "Text Replacement",
  "변환": "Transformations",
  "대문자로": "Make Upper Case",
  "소문자로": "Make Lower Case",
  "단어 첫 글자를 대문자로": "Capitalize",
  "말하기": "Speech",
  "말하기 시작": "Start Speaking",
  "말하기 중단": "Stop Speaking",
  "보기": "View",
  "전체 화면 시작": "Enter Full Screen",
  "윈도우": "Window",
  "최소화": "Minimize",
  "확대/축소": "Zoom",
  "모두 앞으로 가져오기": "Bring All to Front",
  "도움말": "Help",
  "CY뷰어 다운로드 — Mac, Windows, 웹": "Download CY Viewer — Mac, Windows and Web",
  "Mac과 Windows용 CY뷰어를 다운로드하거나 설치 없이 웹에서 PDF를 여세요. 기기에 맞는 최신 버전과 업데이트 안내를 확인할 수 있습니다.": "Download CY Viewer for Mac and Windows, or open PDFs on the web without installation. Find the latest version and update instructions for your device.",
  "다운로드로 건너뛰기": "Skip to downloads",
  "업데이트 안내": "Updates",
  "웹앱 열기 ↗": "Open web app ↗",
  "내 기기에서,": "Your PDFs.",
  "바로 여는 PDF.": "On your device.",
  "읽고, 찾고, 중요한 내용을 남기세요.": "Read, search and keep what matters.",
  "Mac, Windows, 웹에서 같은 CY뷰어를 만납니다.": "One CY Viewer across Mac, Windows and the web.",
  "설치 없이 바로 시작": "Start without installing",
  "웹앱 열기": "Open web app",
  "브라우저에서 PDF를 선택하면 바로 열립니다.": "Choose a PDF in your browser to start reading.",
  "다른 운영체제 다운로드": "Downloads for other platforms",
  "하나의 문서 작업 공간": "One document workspace",
  "CY뷰어 문서함 화면: 전체 문서와 즐겨찾기, PDF 열기 기능": "CY Viewer library with all documents, favorites and Open PDF",
  "문서 검색 · 책갈피 · 표시 · 저장": "Search · Bookmark · Annotate · Save",
  "어디서든, CY뷰어.": "CY Viewer, wherever you read.",
  "아래에서 기기에 맞는 버전을 선택하세요.": "Choose the version for your device below.",
  "macOS 앱 · Apple Silicon 및 Intel": "macOS app · Apple Silicon and Intel",
  "Mac 다운로드": "Download for Mac",
  "변경 사항·검증 파일 ↗": "Release notes and checksums ↗",
  "Windows 10·11 · 64비트": "Windows 10/11 · 64-bit",
  "Windows 다운로드": "Download for Windows",
  "웹앱": "Web app",
  "iPhone·iPad·Android·PC 브라우저": "iPhone · iPad · Android · Desktop browsers",
  "별도 설치 없이 사용 · 홈 화면에 추가 가능": "No installation required · Add to your home screen",
  "홈 화면에 추가하는 방법 ↓": "How to add to your home screen ↓",
  "기기 자동 추천과 최신 버전 확인에는 JavaScript가 필요합니다. 위 다운로드 링크는 그대로 사용할 수 있습니다.": "JavaScript is required for device recommendations and release checks. The download links above still work.",
  "새 버전도 앱 안에서.": "Updates, right in the app.",
  "Mac 1.5.0·Windows 1.2.0부터 앱을 열면 새 버전을 자동으로 확인합니다. 이전 버전은 이 페이지에서 새 설치 파일을 한 번 받아 설치해 주세요.": "Starting with Mac 1.5.0 and Windows 1.2.0, the app checks for updates automatically. If you use an older version, download and install the latest release from this page once.",
  "Windows 업데이트": "Windows updates",
  "새 버전 안내에서 다운로드를 선택하세요. 파일 검증이 끝나면 저장하지 않은 문서를 먼저 저장하고 ‘설치’를 누릅니다. 앱이 종료된 뒤 업데이트가 설치되고 다시 실행됩니다.": "Choose Download in the update notice. After verification, save your documents and choose Install. The app closes, installs the update and restarts.",
  "Mac 업데이트": "Mac updates",
  "앱에서 새 버전을 알리고 설치 파일을 다운로드·검증한 뒤 DMG를 엽니다. CYViewer.app을 Applications로 옮겨 기존 앱을 교체해 주세요. 현재 Mac 배포본은 Apple 서명·공증 전이므로 마지막 교체는 직접 진행합니다.": "The app notifies you of updates, downloads and verifies the installer, then opens the DMG. Move CYViewer.app to Applications to replace the existing app. The current Mac release is not yet Apple-signed or notarized; replacement is manual.",
  "웹앱을 홈 화면에 추가하기": "Add the web app to your home screen",
  "웹앱을 연 뒤 iPhone·iPad의 Safari에서는 공유 → ‘홈 화면에 추가’를 선택하세요. Android의 Chrome에서는 메뉴 → ‘홈 화면에 추가’ 또는 ‘앱 설치’를 선택하세요. 데스크톱에서도 지원 브라우저의 설치 메뉴를 사용할 수 있습니다.": "Open the web app. In Safari on iPhone or iPad, choose Share → Add to Home Screen. In Chrome on Android, choose Menu → Add to Home Screen or Install app. Supported desktop browsers also offer an installation menu.",
  "웹앱으로 이동 ↗": "Go to the web app ↗",
  "다운로드와 문서 보관": "Downloads and document storage",
  "설치 파일은 CY뷰어의 공식 GitHub 릴리스에서 받습니다. PDF 문서는 기기에서 처리합니다. 웹앱은 탭을 닫으면 PDF 원본을 보관하지 않으므로 파일은 별도로 보관해 주세요.": "Installers come from official CY Viewer GitHub releases. PDFs are processed on your device. The web app does not retain the PDF after the tab closes, so keep your original file separately.",
  "모든 릴리스 ↗": "All releases ↗",
  "문제 제보 ↗": "Report an issue ↗",
  "이 기기에 추천 · {0}": "Recommended for this device · {0}",
  "{0}용 CY뷰어 다운로드 ↓": "Download CY Viewer for {0} ↓",
  "공개된 최신 정식 버전을 확인했습니다.": "Latest public releases confirmed.",
  "최신 버전을 확인하지 못했습니다. 아래 배포본을 받거나 모든 릴리스에서 확인해 주세요.": "Could not check the latest version. Use the downloads below or view all releases.",
  "CYViewer 가리기": "Hide CY Viewer",
  "CYViewer 종료": "Quit CY Viewer",
  "CY뷰어 가리기": "Hide CY Viewer",
  "CY뷰어 종료": "Quit CY Viewer",
  "최근 열어본 파일": "Recent files",
  "최근 열어본 파일이 없습니다.": "No recent files yet.",
  "최근 5개 · 이 기기에 저장됨": "Last 5 files · On this device",
  "최근 5개 · 이 브라우저에만 저장됨": "Last 5 files · In this browser only",
  "최근 목록에서 제거": "Remove from recent files",
  "최근 파일 목록을 불러오지 못했습니다. PDF 열기는 계속 사용할 수 있습니다.": "Could not load recent files. You can still open a PDF.",
  "최근 파일을 저장하지 못했습니다. 브라우저 저장 공간을 확인해 주세요.": "Could not save the recent PDF. Check your browser storage.",
  "저장된 사본을 찾을 수 없습니다. PDF를 다시 선택해 주세요.": "The saved copy is unavailable. Select the PDF again.",
  "PDF는 열렸지만 최근 목록을 저장하지 못했습니다.": "The PDF opened, but the recent files list could not be saved.",
  "저장하지 않은 변경을 버리고 다른 PDF를 열까요?": "Discard unsaved changes and open another PDF?",
  "문서는 서버로 전송되지 않습니다.\n최근 PDF 5개의 사본을 이 브라우저에 저장합니다.": "Documents are not uploaded to a server.\nCopies of your last 5 PDFs are saved in this browser.",
  "설치 파일은 CY뷰어의 공식 GitHub 릴리스에서 받습니다. PDF 문서는 기기에서 처리합니다. 웹앱은 최근 PDF 5개의 사본을 이 브라우저에 저장합니다. 최근 목록에서 제거하면 사본도 삭제됩니다. 브라우저 데이터 삭제나 저장 공간 정리로 사라질 수 있으므로 원본은 별도로 보관해 주세요.": "Installers come from official CY Viewer GitHub releases. PDFs are processed on your device. The web app saves copies of your last 5 PDFs in this browser. Removing a recent file also deletes its saved copy. Browser data clearing or storage cleanup may remove these copies, so keep your originals separately.",
  "인쇄 범위": "Print range",
  "인쇄할 페이지": "Pages to print",
  "전체 페이지": "All pages",
  "전체 {0}페이지": "{0} pages total",
  "현재 페이지 ({0})": "Current page ({0})",
  "페이지 직접 지정": "Custom pages",
  "페이지 범위": "Page range",
  "인쇄용 PDF 준비": "Prepare print PDF",
  "인쇄용 PDF 준비 완료": "Print PDF ready",
  "PDF 열고 인쇄하기": "Open PDF to print",
  "1~{0} 사이의 페이지를 입력하세요. 예: 2-5, 8": "Enter pages from 1 to {0}. Example: 2-5, 8",
  "선택한 {0}페이지가 준비되었습니다. PDF를 연 다음 공유 메뉴에서 인쇄를 선택하세요. 인쇄 창의 페이지 번호는 선택한 PDF 안에서 다시 매겨집니다.": "Your {0} selected pages are ready. Open the PDF, then choose Print from the Share menu. Page numbers in the print dialog refer to this selected PDF.",
  "PDF 창이 차단되었습니다. 팝업을 허용한 뒤 다시 눌러 주세요.": "The PDF window was blocked. Allow pop-ups and try again.",
  "이전 인쇄 준비가 진행 중입니다. 잠시 후 다시 시도해 주세요.": "The previous print preparation is still running. Please try again shortly.",
  "문서가 너무 큽니다. 인쇄 범위를 줄이거나 원본 PDF를 사용해 주세요.": "The document is too large. Choose fewer pages or use the original PDF.",
  "인쇄 준비 시간이 초과되었습니다. 범위를 줄여 다시 시도해 주세요.": "Print preparation timed out. Try again with fewer pages.",
  "선택한 {0}페이지": "{0} selected pages",
  "인쇄 준비 중 {0}/{1}": "Preparing print {0}/{1}",
  "전체 페이지가 기본입니다. 인쇄를 누르면 시스템 인쇄 창이 열립니다.": "All pages are selected by default. Select Print to open the system print dialog.",
  "범위 변경": "Change range",
  "인쇄가 안 되면 원본 PDF 열기": "If printing fails, open the original PDF",
]
// END GENERATED TRANSLATIONS
