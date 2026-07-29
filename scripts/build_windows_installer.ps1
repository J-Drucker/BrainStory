[CmdletBinding()]
param(
  [ValidatePattern('^[0-9A-Za-z][0-9A-Za-z._-]*$')]
  [string]$Version = '0.1.0',
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'

function Get-RequiredCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [string]$InstallHint
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "$Name was not found. $InstallHint"
  }
  return $command.Source
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Executable failed with exit code $LASTEXITCODE."
  }
}

function Get-VcRuntimeDirectory {
  $candidateRoots = @()
  if (-not [string]::IsNullOrWhiteSpace($env:VCToolsRedistDir)) {
    $candidateRoots += $env:VCToolsRedistDir
  }

  $programFilesX86 = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFilesX86
  )
  $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path $vswhere) {
    $installationPath = (& $vswhere `
      -latest `
      -products '*' `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
      -property installationPath).Trim()
    if (-not [string]::IsNullOrWhiteSpace($installationPath)) {
      $redistRoot = Join-Path $installationPath 'VC\Redist\MSVC'
      if (Test-Path $redistRoot) {
        $candidateRoots += @(
          Get-ChildItem $redistRoot -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { $_.FullName }
        )
      }
    }
  }

  foreach ($root in $candidateRoots) {
    $x64Root = Join-Path $root 'x64'
    if (-not (Test-Path $x64Root)) {
      continue
    }
    $crtDirectory = Get-ChildItem $x64Root -Directory |
      Where-Object { $_.Name -like 'Microsoft.VC*.CRT' } |
      Select-Object -First 1
    if ($null -ne $crtDirectory) {
      return $crtDirectory.FullName
    }
  }

  throw 'The Visual C++ x64 runtime files were not found. Install the Visual Studio 2022 Desktop development with C++ workload.'
}

function Get-InnoCompiler {
  $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $programFiles = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFiles
  )
  $programFilesX86 = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ProgramFilesX86
  )
  $candidates = @()
  foreach ($majorVersion in @('7', '6')) {
    $relativePath = "Inno Setup $majorVersion\ISCC.exe"
    $candidates += Join-Path $programFilesX86 $relativePath
    $candidates += Join-Path $programFiles $relativePath
  }
  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw 'ISCC.exe was not found. Install Inno Setup 6.3 or newer.'
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$guiDirectory = Join-Path $repositoryRoot 'gui'
$engineManifest = Join-Path $repositoryRoot 'engine\Cargo.toml'
$installerDefinition = Join-Path $repositoryRoot 'packaging\windows\BrainStory.iss'
$outputDirectory = Join-Path $repositoryRoot 'dist'

$flutter = Get-RequiredCommand `
  -Name 'flutter' `
  -InstallHint 'Install Flutter and add its bin directory to PATH.'
$cargo = Get-RequiredCommand `
  -Name 'cargo' `
  -InstallHint 'Install Rust from https://rustup.rs and restart the terminal.'

if (-not $SkipChecks) {
  Invoke-NativeCommand `
    -Executable $cargo `
    -Arguments @(
      'test',
      '--locked',
      '--manifest-path',
      $engineManifest
    )
}

Push-Location $guiDirectory
try {
  Invoke-NativeCommand -Executable $flutter -Arguments @('pub', 'get')
  if (-not $SkipChecks) {
    Invoke-NativeCommand -Executable $flutter -Arguments @('analyze')
    Invoke-NativeCommand -Executable $flutter -Arguments @('test')
  }
  Invoke-NativeCommand `
    -Executable $flutter `
    -Arguments @('build', 'windows', '--release')
}
finally {
  Pop-Location
}

$releaseCandidates = @(
  (Join-Path $guiDirectory 'build\windows\x64\runner\Release'),
  (Join-Path $guiDirectory 'build\windows\runner\Release')
)
$releaseDirectory = $releaseCandidates |
  Where-Object { Test-Path (Join-Path $_ 'brainstory_gui.exe') } |
  Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($releaseDirectory)) {
  throw 'Flutter completed without producing the expected Windows release directory.'
}

$requiredBundleEntries = @(
  'brainstory_gui.exe',
  'brainstory_engine.dll',
  'flutter_windows.dll',
  'data'
)
foreach ($entry in $requiredBundleEntries) {
  $entryPath = Join-Path $releaseDirectory $entry
  if (-not (Test-Path $entryPath)) {
    throw "The Windows release bundle is incomplete: $entry is missing."
  }
}

$vcRuntimeDirectory = Get-VcRuntimeDirectory
$vcRuntimeFiles = Get-ChildItem $vcRuntimeDirectory -File -Filter '*.dll'
if ($vcRuntimeFiles.Count -eq 0) {
  throw "No Visual C++ runtime DLLs were found in $vcRuntimeDirectory."
}
foreach ($runtimeFile in $vcRuntimeFiles) {
  Copy-Item $runtimeFile.FullName $releaseDirectory -Force
}

$innoCompiler = Get-InnoCompiler
New-Item $outputDirectory -ItemType Directory -Force | Out-Null

$environmentNames = @(
  'BRAINSTORY_VERSION',
  'BRAINSTORY_BUILD_DIR',
  'BRAINSTORY_OUTPUT_DIR',
  'BRAINSTORY_REPOSITORY_ROOT'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable(
    $name,
    'Process'
  )
}

try {
  $env:BRAINSTORY_VERSION = $Version
  $env:BRAINSTORY_BUILD_DIR = $releaseDirectory
  $env:BRAINSTORY_OUTPUT_DIR = $outputDirectory
  $env:BRAINSTORY_REPOSITORY_ROOT = $repositoryRoot
  Invoke-NativeCommand `
    -Executable $innoCompiler `
    -Arguments @($installerDefinition)
}
finally {
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable(
      $name,
      $previousEnvironment[$name],
      'Process'
    )
  }
}

$installerPath = Join-Path $outputDirectory "BrainStory-Setup-$Version-x64.exe"
if (-not (Test-Path $installerPath)) {
  throw "Inno Setup completed without producing $installerPath."
}

$hash = Get-FileHash $installerPath -Algorithm SHA256
$hashPath = "$installerPath.sha256"
"$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($installerPath))" |
  Set-Content $hashPath -Encoding Ascii

Write-Host "Installer: $installerPath"
Write-Host "SHA256:   $($hash.Hash.ToLowerInvariant())"
