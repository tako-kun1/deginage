param(
  [string]$SourceDir = "build/windows/x64/runner/Release",
  [string]$OutputPath = "deginage-windows-x64.msi",
  [string]$Version = "",
  [string]$WixExe = "wix"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

if (-not $Version) {
  $pubspec = Get-Content (Join-Path $RepoRoot "pubspec.yaml") -Raw
  if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    $Version = $Matches[1]
  } else {
    throw "pubspec.yaml からバージョンを取得できませんでした。"
  }
}

$ResolvedSource = (Resolve-Path (Join-Path $RepoRoot $SourceDir)).Path
$IconPath = (Resolve-Path (Join-Path $RepoRoot "windows/runner/resources/app_icon.ico")).Path
$LicensePath = (Resolve-Path (Join-Path $PSScriptRoot "license.rtf")).Path
$WxsPath = (Resolve-Path (Join-Path $PSScriptRoot "Package.wxs")).Path
$WxlPath = (Resolve-Path (Join-Path $PSScriptRoot "ja-JP.wxl")).Path

if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot $OutputPath
}

Write-Host "MSI ビルド開始: Deginage v$Version -> $OutputPath"

& $WixExe build `
  -arch x64 `
  -ext WixToolset.UI.wixext `
  -culture ja-JP `
  -loc $WxlPath `
  -d "AppVersion=$Version" `
  -d "SourceDir=$ResolvedSource" `
  -d "IconPath=$IconPath" `
  -d "LicensePath=$LicensePath" `
  -o $OutputPath `
  $WxsPath

if ($LASTEXITCODE -ne 0) {
  throw "WiX ビルドが失敗しました (exit code: $LASTEXITCODE)"
}

Write-Host "MSI ビルド完了: $OutputPath ($((Get-Item $OutputPath).Length) bytes)"
