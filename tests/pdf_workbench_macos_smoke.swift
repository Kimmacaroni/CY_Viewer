// 실제 상속 샌드박스 안에서 편집 창이 생성되는지 확인한다.
import Foundation
import CoreGraphics

let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let input = folder.appendingPathComponent("workbench-smoke.pdf")
var rectangle = CGRect(x: 0, y: 0, width: 612, height: 792)
guard let consumer = CGDataConsumer(url: input as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: &rectangle, nil) else {
    fatalError("검사 PDF를 만들지 못했습니다.")
}
pdf.beginPDFPage(nil)
pdf.setFillColor(gray: 1, alpha: 1)
pdf.fill(rectangle)
pdf.endPDFPage()
pdf.closePDF()
let original = try Data(contentsOf: input)
let task = Process()
task.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/cy-pdf-workbench")
task.arguments = [input.path]
try task.run()
defer { if task.isRunning { task.terminate(); task.waitUntilExit() } }
var found = false
for _ in 0..<30 {
    Thread.sleep(forTimeInterval: 0.5)
    if !task.isRunning { fatalError("PDF 작업실이 창을 열기 전에 종료됐습니다: \(task.terminationStatus)") }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    if windows.contains(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == task.processIdentifier }) {
        found = true
        break
    }
}
guard found else { fatalError("PDF 작업실의 실제 창이 생성되지 않았습니다.") }
guard try Data(contentsOf: input) == original else { fatalError("PDF 작업실이 입력 사본을 변경했습니다.") }
print("전체 PDF 작업실: 샌드박스 프로세스·실제 창 생성·입력 보존 확인")
