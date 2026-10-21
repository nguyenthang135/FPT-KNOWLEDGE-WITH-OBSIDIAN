param(
  [Parameter(Mandatory = $true)][string]$Archive,
  [switch]$Online,
  [string]$InstalledDatabase = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $projectRoot ('dist\portable-verification-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Expand-Archive -LiteralPath $Archive -DestinationPath $testRoot
$exe = Join-Path $testRoot 'FPT Knowledge\FPT Knowledge.exe'
$profile = Join-Path $testRoot 'isolated-appdata'
New-Item -ItemType Directory -Path $profile | Out-Null
[IO.File]::WriteAllText((Join-Path $profile '.fpt-release-verification'), 'isolated release QA')
if ($InstalledDatabase) {
  $installedRoot = [IO.Path]::GetFullPath($InstalledDatabase)
  if (!(Test-Path -LiteralPath (Join-Path $installedRoot 'managed_manifest.json'))) { throw 'Installed database manifest missing.' }
  $dataParent = Join-Path $profile 'FPT Knowledge'
  New-Item -ItemType Directory -Path $dataParent | Out-Null
  Copy-Item -LiteralPath $installedRoot -Destination (Join-Path $dataParent 'Database') -Recurse
}
function Invoke-Verification([string]$mode) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $exe
  $info.WorkingDirectory = Split-Path $exe
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.Environment['APPDATA'] = $profile
  [void]$info.Environment.Remove('GROQ_API_KEY')
  [void]$info.Environment.Remove('GROQ_MODEL')
  [void]$info.ArgumentList.Add("--verify-release-$mode")
  $app = [Diagnostics.Process]::Start($info)
  if (!$app.WaitForExit(60000)) {
    Write-Output "Verification still running: $mode"
    if (!$app.WaitForExit(60000)) {
      if ($app.Path -eq $exe) { Stop-Process -Id $app.Id }
      throw "Verification timed out: $mode"
    }
  }
  $reportFile = Join-Path $profile 'release-verification.json'
  if (!(Test-Path -LiteralPath $reportFile)) { throw "EXE produced no verification report; exit $($app.ExitCode)" }
  $report = Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json
  Copy-Item -LiteralPath $reportFile -Destination (Join-Path $testRoot "$mode.json")
  $report | ConvertTo-Json -Depth 6
  if ($app.ExitCode -ne 0 -or !$report.passed) { throw "EXE verification failed: $mode" }
}
Invoke-Verification 'offline'
$marker = Join-Path $profile 'FPT Knowledge\Database\.installation.json'
$markerHash = (Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash
$markerTime = (Get-Item -LiteralPath $marker).LastWriteTimeUtc
if ($Online) { Invoke-Verification 'online' }
if ($InstalledDatabase -and !$Online) { Invoke-Verification 'offline' }
if ((Get-FileHash -LiteralPath $marker -Algorithm SHA256).Hash -ne $markerHash -or
    (Get-Item -LiteralPath $marker).LastWriteTimeUtc -ne $markerTime) { throw 'Restart unnecessarily reinstalled database' }
Write-Output 'Installation marker preserved across restart.'
Write-Output "Verification evidence: $testRoot"
