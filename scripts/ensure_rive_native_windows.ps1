# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0
#
# Make sure rive_native's prebuilt Windows libraries are on disk before
# `flutter build windows` links against them.
#
# rive_native's windows/CMakeLists.txt runs `dart run rive_native:setup -p
# windows` at configure time. That tool downloads the library zip, checks its
# SHA-512, then unzips it by shelling out to Windows PowerShell 5.1
# `Expand-Archive` and never checks that anything was extracted. On runner
# image windows-2025-vs2026 20261116.315.1 (Windows PowerShell 5.1.26100.33822)
# `windows\bin` is left empty, setup exits 0 and the link step then fails
# with LNK1181 on bin\lib\release\rive_native.lib.
#
# This script runs the same setup, and if the libraries are missing afterwards
# it downloads the same zip, verifies the same hash from the package's own
# hash.txt, and extracts it with .NET. The setup marker file the tool wrote
# makes the configure-time setup a no-op afterwards.
#
# Run from the Flutter app root, after `flutter pub get`:
#   pwsh -File scripts/ensure_rive_native_windows.ps1
$ErrorActionPreference = 'Stop'

dart run rive_native:setup --verbose -p windows
if ($LASTEXITCODE -ne 0) { throw "rive_native:setup failed with exit code $LASTEXITCODE" }

$configPath = (Resolve-Path '.dart_tool/package_config.json').Path
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$entry = $config.packages | Where-Object { $_.name -eq 'rive_native' }
if (-not $entry) { throw 'rive_native is not in .dart_tool/package_config.json' }

$configDir = [IO.Path]::GetDirectoryName($configPath)
$base = [Uri]::new(($configDir.TrimEnd('\') + '\'))
$root = [Uri]::new($base, $entry.rootUri).LocalPath
$bin = Join-Path $root 'windows\bin'
$required = @(
  'lib\release\rive_native.lib',
  'lib\release\rive_native.dll'
)

function Test-RiveLibraries {
  foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $bin $file))) { return $false }
  }
  return $true
}

if (Test-RiveLibraries) {
  Write-Host "rive_native Windows libraries present in $bin"
  return
}

Write-Warning "rive_native:setup exited 0 but left no libraries in $bin; extracting the verified zip directly"

$version = (Get-Content (Join-Path $root 'version.txt') -Raw).Trim()
$expected = ((Get-Content (Join-Path $root 'hash.txt') -Raw) | ConvertFrom-Json).windows.Trim()
$url = 'https://rive-flutter-artifacts.rive.app/rive_native_versions/' +
  [Uri]::EscapeDataString($version) + '/rive_native_artifacts_windows.zip'

$temp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$zip = Join-Path $temp 'rive_native_artifacts_windows.zip'
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA512).Hash
if ($actual -ne $expected) {
  throw "rive_native Windows zip hash mismatch: expected $expected, got $actual"
}

New-Item -ItemType Directory -Force -Path $bin | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
  foreach ($zipEntry in $archive.Entries) {
    if ([string]::IsNullOrEmpty($zipEntry.Name)) { continue }
    $target = [IO.Path]::GetFullPath((Join-Path $bin $zipEntry.FullName))
    if (-not $target.StartsWith([IO.Path]::GetFullPath($bin), [StringComparison]::OrdinalIgnoreCase)) {
      throw "rive_native zip entry escapes the target directory: $($zipEntry.FullName)"
    }
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($zipEntry, $target, $true)
  }
} finally {
  $archive.Dispose()
}

if (-not (Test-RiveLibraries)) {
  throw "rive_native Windows libraries are still missing from $bin after extraction"
}
Write-Host "rive_native Windows libraries extracted to $bin"
