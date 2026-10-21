param(
  [Parameter(Mandatory = $true)][string]$FlutterPath,
  [Parameter(Mandatory = $true)][string]$RuntimeDirectory,
  [string]$GatewayUrl = '',
  [string]$DataUpdateUrl = 'https://raw.githubusercontent.com/nguyenthang135/FPT-KNOWLEDGE-WITH-OBSIDIAN/main/releases/data/latest.json',
  [string]$DirectGroqPrivateInput = '',
  [string]$PortableDirectory = '',
  [switch]$LocalCandidate,
  [switch]$SkipBuild,
  [string]$InnoCompiler = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
function Assert-PublicHttps([string]$value) {
  $uri = [Uri]$value
  if ($uri.Scheme -ne 'https' -or !$uri.Host -or $uri.UserInfo -or $uri.Fragment -or
      $uri.Host -match 'localhost|example\.|\.invalid$|^\d+\.') { throw 'A real public HTTPS endpoint is required.' }
}
if (!$LocalCandidate) {
  if (!$DataUpdateUrl) { throw 'Public packaging requires the published data-feed URL.' }
  if (!$GatewayUrl -and !$DirectGroqPrivateInput) {
    $DirectGroqPrivateInput = Join-Path (Split-Path $projectRoot -Parent) 'api code.txt'
  }
}
if ($GatewayUrl) { Assert-PublicHttps $GatewayUrl }
if ($DataUpdateUrl) { Assert-PublicHttps $DataUpdateUrl }
$versionMatch = [regex]::Match((Get-Content -LiteralPath pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)')
if (!$versionMatch.Success) { throw 'App version missing' }
$version = $versionMatch.Groups[1].Value
if (!$SkipBuild) {
  $buildArgs = @('build', 'windows', '--release')
  if ($GatewayUrl) { $buildArgs += "--dart-define=FPT_AI_GATEWAY_URL=$GatewayUrl" }
  if ($DataUpdateUrl) { $buildArgs += "--dart-define=FPT_DATA_UPDATE_URL=$DataUpdateUrl" }
  $privateConfiguration = $null
  $privateDirectory = $null
  $buildSecret = ''
  try {
    if ($DirectGroqPrivateInput) {
      if ($GatewayUrl) { throw 'Choose direct Groq or gateway, not both.' }
      $privateText = [IO.File]::ReadAllText($DirectGroqPrivateInput)
      $keyMatch = [regex]::Match($privateText, '(?im)^\s*(?:set\s+)?"?GROQ_API_KEY\s*=\s*([^\s"\r\n]+)')
      if (!$keyMatch.Success) { throw 'Private Groq input is missing GROQ_API_KEY.' }
      $buildSecret = $keyMatch.Groups[1].Value
      $privateDirectory = Join-Path ([IO.Path]::GetTempPath()) ('fpt-private-build-' + [Guid]::NewGuid().ToString('N'))
      New-Item -ItemType Directory -Path $privateDirectory | Out-Null
      $privateConfiguration = Join-Path $privateDirectory 'defines.json'
      $configuration = @{ GROQ_API_KEY = $buildSecret; GROQ_MODEL = 'openai/gpt-oss-20b' } | ConvertTo-Json -Compress
      [IO.File]::WriteAllText($privateConfiguration, $configuration, [Text.UTF8Encoding]::new($false))
      $buildArgs += "--dart-define-from-file=$privateConfiguration"
    }
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist') -Force | Out-Null
    $encodedSecret = if ($buildSecret) { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("GROQ_API_KEY=$buildSecret")) } else { '' }
    & $FlutterPath @buildArgs 2>&1 | ForEach-Object {
      $safeLine = $_.ToString()
      if ($buildSecret) { $safeLine = $safeLine.Replace($buildSecret, '[redacted]').Replace($encodedSecret, '[redacted]') }
      $safeLine
    } | Tee-Object -FilePath (Join-Path $projectRoot 'dist\final-build.log')
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
  } finally {
    if ($privateConfiguration -and (Test-Path -LiteralPath $privateConfiguration)) { Remove-Item -LiteralPath $privateConfiguration }
    if ($privateDirectory -and (Test-Path -LiteralPath $privateDirectory)) { Remove-Item -LiteralPath $privateDirectory }
    $privateText = $null; $keyMatch = $null; $configuration = $null; $buildSecret = $null
  }
}
$release = Join-Path $projectRoot 'build\windows\x64\runner\Release'
foreach ($required in @('fptu_se_brain.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets\assets\database\fpt_knowledge_database.zip')) {
  if (!(Test-Path -LiteralPath (Join-Path $release $required))) { throw "Release file missing: $required" }
}
$suffix = if ($LocalCandidate) { '-LOCAL-CANDIDATE' } else { '' }
$artifactName = "FPT-Knowledge-v$version-Windows-Portable$suffix"
$output = if ($LocalCandidate) { Join-Path $projectRoot 'dist' } else { Split-Path $projectRoot -Parent }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$stage = Join-Path (Join-Path $projectRoot 'dist') ('stage-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$appFolder = Join-Path $stage 'FPT Knowledge'
New-Item -ItemType Directory -Path $appFolder | Out-Null
Copy-Item -LiteralPath "$release\data" -Destination $appFolder -Recurse
Get-ChildItem -LiteralPath $release -File | Where-Object Extension -In '.exe','.dll' | Copy-Item -Destination $appFolder
Rename-Item -LiteralPath "$appFolder\fptu_se_brain.exe" -NewName 'FPT Knowledge.exe'
foreach ($requiredDll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  if (!(Test-Path -LiteralPath (Join-Path $RuntimeDirectory $requiredDll))) { throw "VC++ runtime missing: $requiredDll" }
}
Get-ChildItem -LiteralPath $RuntimeDirectory -Filter '*.dll' -File | Copy-Item -Destination $appFolder
foreach ($doc in @('INSTALL.md','USER_GUIDE.md','THIRD_PARTY_NOTICES.md')) {
  Copy-Item -LiteralPath (Join-Path $projectRoot $doc) -Destination $appFolder
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\database\bundle_info.json') -Destination (Join-Path $appFolder 'DATABASE_VERSION.json')
$scanArgs = @((Join-Path $PSScriptRoot 'audit_release.mjs'), $appFolder)
if ($DirectGroqPrivateInput) { $scanArgs += '--allow-compiled-groq' }
& node @scanArgs
if ($LASTEXITCODE -ne 0) { throw 'Artifact secret scan failed' }
$archive = Join-Path $output "$artifactName.zip"
if (Test-Path -LiteralPath $archive) {
  Move-Item -LiteralPath $archive -Destination ($archive + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
Compress-Archive -LiteralPath $appFolder -DestinationPath $archive -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archive))" | Set-Content -LiteralPath "$archive.sha256" -Encoding ascii
if (!$LocalCandidate) {
  if (!$PortableDirectory) { $PortableDirectory = Join-Path (Split-Path $projectRoot -Parent) 'FPT Knowledge' }
  $destination = [IO.Path]::GetFullPath($PortableDirectory)
  $expectedDestination = [IO.Path]::GetFullPath((Join-Path (Split-Path $projectRoot -Parent) 'FPT Knowledge'))
  if ($destination -ne $expectedDestination) { throw 'Final destination must be the explicitly requested FPT Knowledge folder.' }
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  $managedMarker = Join-Path $destination '.portable-managed-files.json'
  $previousFiles = if (Test-Path -LiteralPath $managedMarker) { @(Get-Content -LiteralPath $managedMarker -Raw | ConvertFrom-Json) } else { @() }
  $managedFiles = @(Get-ChildItem -LiteralPath $appFolder -File -Recurse | ForEach-Object { $_.FullName.Substring($appFolder.Length + 1) })
  foreach ($relative in $managedFiles) {
    $target = Join-Path $destination $relative
    if ((Test-Path -LiteralPath $target) -and $relative -notin $previousFiles) { throw "Preserving unknown destination file: $relative" }
  }
  $previousBackup = Join-Path (Join-Path $projectRoot 'dist') ('portable-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  foreach ($relative in $managedFiles) {
    $target = Join-Path $destination $relative
    if (Test-Path -LiteralPath $target) {
      $backupTarget = Join-Path $previousBackup $relative
      New-Item -ItemType Directory -Path (Split-Path $backupTarget) -Force | Out-Null
      Copy-Item -LiteralPath $target -Destination $backupTarget
    }
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $appFolder $relative) -Destination $target -Force
  }
  ConvertTo-Json -InputObject $managedFiles | Set-Content -LiteralPath $managedMarker -Encoding utf8
  Write-Output "Final portable folder: $destination"
}
if ($InnoCompiler) {
  & $InnoCompiler "/DAppVersion=$version" "/DSourceDir=$appFolder" "/DOutputDir=$output" "/DReleaseSuffix=$suffix" (Join-Path $PSScriptRoot 'windows-installer.iss')
  if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed' }
  $installer = Join-Path $output "FPT-Knowledge-v$version-Setup$suffix.exe"
  $installerHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
  "$installerHash  $([IO.Path]::GetFileName($installer))" | Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
}
Get-Item -LiteralPath $archive | Select-Object FullName,Length
Write-Output "SHA256: $hash"
Write-Output "Staged application: $appFolder"
