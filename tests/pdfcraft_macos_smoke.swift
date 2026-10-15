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
    context.beginPDFPage([kCGPDFContextMediaBox as String: data] as CFDictionary)
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 20, y: 20, width: 50, height: 50))
    context.endPDFPage()
  }
  context.closePDF()
  let original = try Data(contentsOf: source)
  guard let parent = Bundle.main.executableURL else { throw NSError(domain: "CYPageSmoke", code: 4) }
  let executable = parent.deletingLastPathComponent().appendingPathComponent("cy-pdfcraft")
  func invoke(_ request: [String: Any]) throws {
    let process = Process()
    process.executableURL = executable
    let input = Pipe(), report = Pipe(), errors = Pipe()
    process.standardInput = input; process.standardOutput = report; process.standardError = errors
    try process.run()
    input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    let error = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    try check(process.terminationStatus == 0, "샌드박스 모듈 오류: \(error)")
  }
  try invoke(["sources": [["path": source.path, "title": "CY smoke", "pages": "2,1"]], "output": output.path])
  guard let document = PDFDocument(url: output) else { throw NSError(domain: "CYPageSmoke", code: 3) }
  try check(document.pageCount == 2, "페이지 수 오류")
  try check(document.page(at: 0)?.bounds(for: .mediaBox).width == 400, "페이지 순서 오류")
  let protected = directory.appendingPathComponent("protected.pdf")
  let plan: [[String: Any]] = [["index": 1, "rotation": 90], ["index": NSNull(), "rotation": 0], ["index": 0, "rotation": 0]]
  try invoke([
    "sources": [["path": source.path, "title": "CY smoke"]], "output": protected.path,
    "page_plan": plan,
    "metadata": ["Title": "편집한 문서"],
    "bookmarks": [["action": "add", "title": "두 번째 장", "page": 2]],
    "new_password": "cy-test-password"
  ])
  guard let edited = PDFDocument(url: protected) else { throw NSError(domain: "CYPageSmoke", code: 5) }
  try check(edited.isLocked, "암호 설정 오류")
  try check(edited.unlock(withPassword: "cy-test-password"), "암호 열기 오류")
  try check(edited.pageCount == 3, "빈 페이지 삽입 오류")
  try check(edited.page(at: 0)?.rotation == 90, "페이지 회전 오류")
  try check(edited.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "편집한 문서", "문서 정보 오류")
  try check((edited.outlineRoot?.numberOfChildren ?? 0) > 0, "문서 책갈피 오류")
  let finished = directory.appendingPathComponent("finished.pdf")
  try invoke(["sources": [["path": source.path, "title": "CY smoke"]], "output": finished.path,
              "finishing": ["watermark": "DRAFT", "header": "CY VIEWER", "page_numbers": true,
                            "crop_mm": [2.0, 3.0, 4.0, 5.0], "optimize": true]])
  guard let marked = PDFDocument(url: finished) else { throw NSError(domain: "CYPageSmoke", code: 6) }
  try check(marked.pageCount == 2, "문서 마무리 페이지 수 오류")
  try check(marked.page(at: 0)?.string?.contains("DRAFT") == true, "워터마크 오류")
  try check(marked.page(at: 1)?.string?.contains("2/2") == true, "페이지 번호 오류")
  try check((marked.page(at: 0)?.bounds(for: .cropBox).width ?? 300) < 300, "여백 자르기 오류")
  try check(try Data(contentsOf: source) == original, "원본 변경")
  print("Mac 샌드박스 PdfCraft 실행·페이지 순서·회전·빈 페이지·문서 정보·책갈피·암호·저장 검사 통과")
}
do { try run() } catch { fputs("\(error)\n", stderr); exit(1) }
