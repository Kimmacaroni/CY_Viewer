"""공식 릴리스 확인, 무결성 검사, 사용자 동의 후 설치를 담당한다."""
from __future__ import annotations
import hashlib
import json
import queue
import re
import subprocess
import sys
import tempfile
import threading
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from tkinter import messagebox
from version import APP_VERSION

REPO = "https://github.com/Kimmacaroni/CY_Viewer"
API = "https://api.github.com/repos/Kimmacaroni/CY_Viewer/releases?per_page=100"
MAX_PACKAGE = 250 * 1024 * 1024


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError("버전 형식이 올바르지 않습니다.")
    return tuple(map(int, value.split(".")))


@dataclass(frozen=True)
class Update:
    version: str
    url: str
    checksum_url: str
    size: int
    filename: str


def select_release(releases, current=APP_VERSION):
    choices = []
    for release in releases:
        tag = release.get("tag_name", "")
        if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"windows-v\d+\.\d+\.\d+", tag):
            continue
        version = tag.removeprefix("windows-v")
        if version_tuple(version) <= version_tuple(current):
            continue
        filename = f"CYViewer-Setup-v{version}.exe"
        checksum = f"SHA256SUMS-Windows-v{version}.txt"
        prefix = f"{REPO}/releases/download/{tag}/"
        assets = {a.get("name"): a for a in release.get("assets", [])}
        binary, sums = assets.get(filename, {}), assets.get(checksum, {})
        size = binary.get("size", 0)
        if (binary.get("browser_download_url") == prefix + filename
                and sums.get("browser_download_url") == prefix + checksum
                and isinstance(size, int) and 0 < size <= MAX_PACKAGE):
            choices.append(Update(version, prefix + filename, prefix + checksum, size, filename))
    return max(choices, key=lambda item: version_tuple(item.version), default=None)


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not newurl.startswith("https://"):
            raise ValueError("HTTPS가 아닌 다운로드 주소입니다.")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def open_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": f"CYViewer/{APP_VERSION}", "Accept": "application/vnd.github+json" if url == API else "*/*"})
    return urllib.request.build_opener(HTTPSRedirect()).open(request, timeout=30)


def check_release():
    with open_url(API) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise ValueError("업데이트 응답이 너무 큽니다.")
    releases = json.loads(data)
    if not isinstance(releases, list):
        raise ValueError("업데이트 목록을 읽을 수 없습니다.")
    return select_release(releases)


def checksum_for(text, filename):
    for line in text.splitlines():
        match = re.fullmatch(r"([a-fA-F0-9]{64})\s+\*?(.+)", line.strip())
        if match and match[2] == filename:
            return match[1].lower()
    raise ValueError("설치 파일의 검증 정보를 찾을 수 없습니다.")


def download(update, progress, opener=open_url):
    with opener(update.checksum_url) as response:
        expected = checksum_for(response.read(65536).decode("utf-8-sig"), update.filename)
    directory = Path(tempfile.mkdtemp(prefix="CYViewer-update-"))
    target = directory / update.filename
    partial = target.with_suffix(".part")
    digest, received = hashlib.sha256(), 0
    try:
        with opener(update.url) as response, partial.open("wb") as output:
            while chunk := response.read(256 * 1024):
                received += len(chunk)
                if received > update.size:
                    raise ValueError("설치 파일 크기가 일치하지 않습니다.")
                output.write(chunk)
                digest.update(chunk)
                progress(int(received * 100 / update.size))
        if received != update.size or digest.hexdigest() != expected:
            raise ValueError("설치 파일 검증에 실패했습니다. 다시 다운로드해 주세요.")
        partial.rename(target)
        return target
    except Exception:
        partial.unlink(missing_ok=True)
        raise


def powershell_quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def installer_script(installer, executable, pid):
    # 앱 종료를 기다린 뒤 설치한다. 종료 전에는 실행 파일을 교체하지 않는다.
    return f'''$ErrorActionPreference = 'Stop'
Wait-Process -Id {int(pid)} -ErrorAction SilentlyContinue
$arguments = @('/SILENT', '/NORESTART', '/SP-', '/NOCLOSEAPPLICATIONS', {powershell_quote('/DIR="' + str(executable.parent) + '"')})
$setup = Start-Process -FilePath {powershell_quote(installer)} -ArgumentList $arguments -Wait -PassThru
if ($setup.ExitCode -eq 0) {{ Start-Process -FilePath {powershell_quote(executable)} }}
else {{ Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('업데이트 설치를 완료하지 못했습니다. 배포 사이트에서 다시 설치해 주세요.', 'CY뷰어 업데이트') }}
'''


class UpdateController:
    def __init__(self, app, button):
        self.app, self.button = app, button
        self.events = queue.Queue()
        self.busy = False
        self.ready = None
        self.app.after(200, self.poll)
        if getattr(sys, "frozen", False):
            self.app.after(5000, self.automatic_check)

    def automatic_check(self):
        self.check(manual=False)
        self.app.after(6 * 60 * 60 * 1000, self.automatic_check)

    def label(self, text):
        self.button.text = text
        self.button._draw()

    def check(self, manual=True):
        if self.busy:
            return
        if self.ready:
            self.install()
            return
        self.busy = True
        self.label("업데이트 확인 중…")
        def work():
            try:
                self.events.put(("checked", (check_release(), manual)))
            except Exception:
                self.events.put(("error", ("업데이트를 확인할 수 없습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.", manual)))
        threading.Thread(target=work, daemon=True).start()

    def poll(self):
        try:
            while True:
                event, value = self.events.get_nowait()
                if event == "progress":
                    self.label(f"다운로드 {value}%")
                elif event == "checked":
                    self.busy = False
                    self.label("업데이트 확인")
                    update, manual = value
                    if update and messagebox.askyesno("CY뷰어 업데이트", f"새 버전 {update.version}이 있습니다.\n현재 버전: {APP_VERSION}\n\n설치 파일을 다운로드할까요? 문서는 계속 사용할 수 있습니다.", parent=self.app):
                        self.start_download(update)
                    elif not update and manual:
                        messagebox.showinfo("CY뷰어 업데이트", f"현재 최신 버전({APP_VERSION})입니다.", parent=self.app)
                elif event == "ready":
                    self.busy = False
                    self.ready = value
                    self.label("업데이트 설치")
                    self.install()
                elif event == "error":
                    self.busy = False
                    self.label("업데이트 재시도")
                    message, visible = value
                    if visible:
                        messagebox.showerror("CY뷰어 업데이트", message, parent=self.app)
        except queue.Empty:
            pass
        self.app.after(200, self.poll)

    def start_download(self, update):
        self.busy = True
        self.label("다운로드 0%")
        def work():
            try:
                path = download(update, lambda percent: self.events.put(("progress", percent)))
                self.events.put(("ready", path))
            except Exception as error:
                self.events.put(("error", (f"업데이트를 다운로드하지 못했습니다.\n{error}", True)))
        threading.Thread(target=work, daemon=True).start()

    def install(self):
        if not getattr(sys, "frozen", False):
            messagebox.showinfo("CY뷰어 업데이트", "개발 실행에서는 설치를 시작하지 않습니다.", parent=self.app)
            return
        if self.app.is_dirty:
            messagebox.showinfo("CY뷰어 업데이트", "저장하지 않은 변경이 있습니다. PDF를 저장한 뒤 업데이트 설치를 다시 눌러 주세요.", parent=self.app)
            return
        if not messagebox.askyesno("CY뷰어 업데이트", "다운로드와 검증이 완료되었습니다.\n\nCY뷰어를 종료하고 업데이트를 설치한 뒤 다시 실행할까요?", parent=self.app):
            return
        try:
            import os
            script = self.ready.parent / "install.ps1"
            script.write_text(installer_script(self.ready, Path(sys.executable), os.getpid()), encoding="utf-8-sig")
            subprocess.Popen(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(script)], creationflags=subprocess.CREATE_NO_WINDOW)
            self.app.destroy()
        except Exception as error:
            messagebox.showerror("CY뷰어 업데이트", f"설치를 시작하지 못했습니다.\n{error}", parent=self.app)
