# 격리된 CI 폴더에서 실제 설치 파일의 설치·덮어쓰기와 실행 파일 배치를 검사한다.
$ErrorActionPreference = 'Stop'
$target = Join-Path $env:RUNNER_TEMP 'CYViewer installer test'
$version = [regex]::Match((Get-Content installer/CYViewer.iss -Raw), 'MyAppVersion "([0-9.]+)"').Groups[1].Value
$installer = (Resolve-Path "release/CYViewer-Setup-v$version.exe").Path
$arguments = @('/VERYSILENT', '/NORESTART', '/SP-', '/NOCLOSEAPPLICATIONS', "/DIR=`"$target`"")
foreach ($pass in 1..2) {
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installer pass $pass failed: $($process.ExitCode)" }
    if (-not (Test-Path (Join-Path $target 'CYViewer.exe'))) { throw 'Installed executable missing' }
}
$expected = (Get-FileHash dist_titleicon4/CYViewer/CYViewer.exe -Algorithm SHA256).Hash
$actual = (Get-FileHash (Join-Path $target 'CYViewer.exe') -Algorithm SHA256).Hash
if ($expected -ne $actual) { throw 'Installed executable differs from build' }
Write-Output 'Installer install/replace and executable hash checks passed.'
# 페이지 엔진과 고지가 설치본에 빠지지 않았는지 실제 파일로 확인한다.
foreach ($file in @('cy-pdfcraft.exe', 'THIRD_PARTY_NOTICES.txt')) {
    $relative = "_internal/pdfcraft/$file"
    $installed = Join-Path $target $relative
    if (-not (Test-Path $installed)) { throw "페이지 모듈 설치 파일 누락: $file" }
    $builtHash = (Get-FileHash (Join-Path 'build/pdfcraft' $file) -Algorithm SHA256).Hash
    if ((Get-FileHash $installed -Algorithm SHA256).Hash -ne $builtHash) { throw "페이지 모듈 파일 불일치: $file" }
}
& (Join-Path $target '_internal/pdfcraft/cy-pdfcraft.exe') --version
if ($LASTEXITCODE -ne 0) { throw '설치된 페이지 모듈이 실행되지 않습니다.' }
# 전체 편집 작업실도 실제 설치본에서 해시와 실행을 확인한다.
foreach ($pair in @(
    @('cy-pdf-workbench.exe', 'cy-pdf-workbench.exe'),
    @('workbench/THIRD_PARTY_NOTICES.txt', 'THIRD_PARTY_NOTICES.txt'),
    @('models/text-detection.rten', 'models/text-detection.rten'),
    @('models/text-recognition.rten', 'models/text-recognition.rten'),
    @('models/CC-BY-SA-4.0.txt', 'models/CC-BY-SA-4.0.txt')
)) {
    $installed = Join-Path $target ("_internal/pdfcraft/" + $pair[0])
    $built = Join-Path 'build/pdf-workbench/bin' $pair[1]
    if (-not (Test-Path $installed)) { throw "PDF 작업실 설치 파일 누락: $($pair[0])" }
    if ((Get-FileHash $installed -Algorithm SHA256).Hash -ne (Get-FileHash $built -Algorithm SHA256).Hash) { throw "PDF 작업실 설치 파일 불일치: $($pair[0])" }
}
& (Join-Path $target '_internal/pdfcraft/cy-pdf-workbench.exe') --version
if ($LASTEXITCODE -ne 0) { throw '설치된 전체 PDF 작업실이 실행되지 않습니다.' }
# 설치된 전체 편집기를 실제 GUI로 시작한다. 검사 PDF는 수정되지 않아야 한다.
$fixture = (Resolve-Path 'macos_app/test/fixtures/print-pages.pdf').Path
$fixtureHash = (Get-FileHash $fixture -Algorithm SHA256).Hash
$workbench = Start-Process -FilePath (Join-Path $target '_internal/pdfcraft/cy-pdf-workbench.exe') -ArgumentList @("`"$fixture`"") -PassThru
try {
    $visible = $false
    foreach ($attempt in 1..30) {
        Start-Sleep -Milliseconds 500
        $workbench.Refresh()
        if ($workbench.HasExited) { throw "전체 PDF 작업실이 창 생성 전에 종료됐습니다: $($workbench.ExitCode)" }
        if ($workbench.MainWindowHandle -ne 0) { $visible = $true; break }
    }
    if (-not $visible) { throw '설치된 전체 PDF 작업실의 창이 생성되지 않았습니다.' }
    if ((Get-FileHash $fixture -Algorithm SHA256).Hash -ne $fixtureHash) { throw '작업실이 입력 PDF를 변경했습니다.' }
    Write-Output 'Installed PDF workbench window and input preservation checks passed.'
} finally {
    if (-not $workbench.HasExited) {
        $null = $workbench.CloseMainWindow()
        if (-not $workbench.WaitForExit(5000)) { $workbench.Kill() }
    }
}
