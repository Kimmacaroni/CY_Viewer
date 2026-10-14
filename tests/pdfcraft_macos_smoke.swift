// 샌드박스가 켜진 부모 프로세스에서 실제 배포 모듈의 실행·저장을 확인한다.
import Foundation
import PDFKit
import CoreGraphics

func check(_ condition: Bool, _ message: String) throws {
  if !condition { throw NSError(domain: "CYPageSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
func run() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let source = directory.appendingPathComponent("source.pdf")
  let output = directory.appendingPathComponent("result.pdf")
  guard let consumer = CGDataConsumer(url: source as CFURL),
        let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
    throw NSError(domain: "CYPageSmoke", code: 2)
  }
  for width in [300.0, 400.0] {
    var box = CGRect(x: 0, y: 0, width: width, height: 500)
    let data = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
    context.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
    context.endPDFPage()
  }
  context.closePDF()
  let original = try Data(contentsOf: source)
  let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("cy-pdfcraft")
  let process = Process()
  process.executableURL = executable
  let input = Pipe(), report = Pipe(), errors = Pipe()
  process.standardInput = input; process.standardOutput = report; process.standardError = errors
  try process.run()
  let request: [String: Any] = ["sources": [["path": source.path, "title": "CY smoke", "pages": "2,1"]], "output": output.path]
  input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request))
  try input.fileHandleForWriting.close()
  process.waitUntilExit()
  let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  try check(process.terminationStatus == 0, "샌드박스 모듈 오류: \(error)")
  guard let document = PDFDocument(url: output) else { throw NSError(domain: "CYPageSmoke", code: 3) }
  try check(document.pageCount == 2, "페이지 수 오류")
  try check(document.page(at: 0)?.bounds(for: .mediaBox).width == 400, "페이지 순서 오류")
  try check(try Data(contentsOf: source) == original, "원본 변경")
  print("Mac 샌드박스 PdfCraft 실행·페이지 순서·저장 검사 통과")
}
do { try run() } catch { fputs("\(error)\n", stderr); exit(1) }
