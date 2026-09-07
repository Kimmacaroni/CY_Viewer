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

      do {
        var pages: [String] = []
        for index in 0..<document.pageCount {
          guard let page = document.page(at: index) else { continue }
          let bounds = page.bounds(for: .mediaBox)
          let thumbnail = page.thumbnail(
            of: NSSize(width: bounds.width * 2, height: bounds.height * 2),
            for: .mediaBox)
          var imageRect = NSRect(origin: .zero, size: thumbnail.size)
          guard let image = thumbnail.cgImage(
            forProposedRect: &imageRect,
            context: nil,
            hints: nil)
          else { continue }

          var recognized: [String] = []
          let request = VNRecognizeTextRequest { request, _ in
            recognized = (request.results as? [VNRecognizedTextObservation] ?? [])
              .compactMap { $0.topCandidates(1).first?.string }
          }
          request.recognitionLevel = .accurate
          request.recognitionLanguages = ["ko-KR", "en-US"]
          request.usesLanguageCorrection = true
          try VNImageRequestHandler(cgImage: image).perform([request])
          pages.append(
            "--- \(index + 1) 페이지 ---\n" + recognized.joined(separator: "\n"))
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
