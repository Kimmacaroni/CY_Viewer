"""Swift 소스의 실제 릴리스 선택기를 추출해 Mac에서 실행한다."""
from pathlib import Path
import subprocess
import tempfile

source = Path('macos_app/macos/Runner/MainFlutterWindow.swift').read_text()
parser = source[source.index('private struct MacUpdateInfo'):source.index('private final class MacUpdateController')]
checks = r'''
let prefix = "https://github.com/Kimmacaroni/CY_Viewer/releases/download/macos-v1.10.0/"
let release: [String: Any] = ["tag_name":"macos-v1.10.0", "draft":false, "prerelease":false, "assets":[
["name":"CYViewer-macOS-v1.10.0.dmg", "size":Int64(100), "browser_download_url":prefix+"CYViewer-macOS-v1.10.0.dmg"],
["name":"SHA256SUMS-macOS-v1.10.0.txt", "browser_download_url":prefix+"SHA256SUMS-macOS-v1.10.0.txt"]]]
assert(MacUpdateInfo.newest([release], current:"1.9.0")?.version == "1.10.0")
assert(MacUpdateInfo.newest([release], current:"1.10.0") == nil)
assert(MacUpdateInfo.newest([release], current:"2.0.0") == nil)
assert(MacUpdateInfo.versionParts("1.2.x.3") == nil)
var trial = release; trial["prerelease"] = true
assert(MacUpdateInfo.newest([trial], current:"1.0.0") == nil)
var bad = release; bad["assets"] = [["name":"CYViewer-macOS-v1.10.0.dmg", "size":100, "browser_download_url":"https://example.com/fake.dmg"]]
assert(MacUpdateInfo.newest([bad], current:"1.0.0") == nil)
assert(MacUpdateInfo.newest([release], current:"1.9.0")?.url.absoluteString == prefix+"CYViewer-macOS-v1.10.0.dmg")
print("Mac updater checks passed")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)/'checks.swift'
    path.write_text('import Foundation\n'+parser+checks)
    subprocess.run(['swift', str(path)], check=True)

# 샌드박스 내부 DMG를 만든 뒤 여는 회귀를 막는다. URL은 위 Swift 선택기가 허용 목록으로 검증한다.
assert 'NSWorkspace.shared.open(update.url)' in source
assert 'downloadTask(with: packageRequest)' not in source
