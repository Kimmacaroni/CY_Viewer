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
