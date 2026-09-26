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
