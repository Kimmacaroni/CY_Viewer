import Cocoa
import FlutterMacOS
import PDFKit
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

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

    super.awakeFromNib()
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
