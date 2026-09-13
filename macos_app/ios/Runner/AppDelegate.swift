import Flutter
import PDFKit
import UIKit
import Vision

final class IOSFileCoordinator {
  static let shared = IOSFileCoordinator()

  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []

  private init() {}

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    deliverPendingPaths()
  }

  func importFiles(from urls: [URL]) {
    guard !urls.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      var imported: [String] = []
      for url in urls where url.pathExtension.lowercased() == "pdf" {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
          if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
          let manager = FileManager.default
          let documents = try manager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
          let directory = documents.appendingPathComponent("CYViewer 문서", isDirectory: true)
          try manager.createDirectory(at: directory, withIntermediateDirectories: true)
          let destination = directory.appendingPathComponent(
            "\(Int(Date().timeIntervalSince1970 * 1000))-\(url.lastPathComponent)")
          try manager.copyItem(at: url, to: destination)
          imported.append(destination.path)
        } catch {
          continue
        }
      }
      DispatchQueue.main.async { self.enqueue(paths: imported) }
    }
  }

  func takePendingPaths() -> [String] {
    let paths = pendingPaths
    pendingPaths.removeAll()
    return paths
  }

  private func enqueue(paths: [String]) {
    for path in paths where !pendingPaths.contains(path) {
      pendingPaths.append(path)
    }
    deliverPendingPaths()
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
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    let fileAccessChannel = FlutterMethodChannel(
      name: "com.kimmacaroni.cyviewer/file_access",
      binaryMessenger: messenger)
    fileAccessChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePendingFiles":
        result(IOSFileCoordinator.shared.takePendingPaths())
      case "createBookmark", "resolveBookmark":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    IOSFileCoordinator.shared.attach(channel: fileAccessChannel)

    let ocrChannel = FlutterMethodChannel(
      name: "com.kimmacaroni.cyviewer/ocr",
      binaryMessenger: messenger)
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
  }

  private static func recognizePdf(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "open_failed", message: "PDF를 열 수 없습니다.", details: nil))
        }
        return
      }
      guard document.pageCount > 0 else {
        DispatchQueue.main.async {
          result(FlutterError(code: "empty_document", message: "페이지가 없는 PDF 문서입니다.", details: nil))
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
            let scale = min(2.0, 2200.0 / max(bounds.width, bounds.height))
            let thumbnail = page.thumbnail(
              of: CGSize(
                width: max(bounds.width * scale, 1),
                height: max(bounds.height * scale, 1)),
              for: .mediaBox)
            guard let image = thumbnail.cgImage else { return }

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
            pages.append("--- \(index + 1) 페이지 ---\n" + recognized.joined(separator: "\n"))
          }
        }
        DispatchQueue.main.async { result(pages.joined(separator: "\n\n")) }
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
