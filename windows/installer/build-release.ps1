[CmdletBinding()]
param(
  [string]$OutputDirectory,
  [string]$IsccPath,
  [string]$NodeArchivePath,
  [string]$WorkingDirectory,
  [switch]$KeepWorkingDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$installerRoot = $PSScriptRoot
$windowsRoot = Split-Path -Parent $installerRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
$manifestPath = Join-Path $installerRoot 'node-runtime.json'
$definitionPath = Join-Path $installerRoot 'codex-aurora-skin.iss'
$bootstrapPath = Join-Path $installerRoot 'setup-bootstrap.ps1'
$launcherSourcePath = Join-Path $installerRoot 'manager-launcher.cs'
$versionPath = Join-Path $windowsRoot 'VERSION'
$macosVersionPath = Join-Path (Join-Path $repositoryRoot 'macos') 'VERSION'
$macosPackagePath = Join-Path (Join-Path $repositoryRoot 'macos') 'package.json'
$licensePath = Join-Path $repositoryRoot 'LICENSE'
$noticePath = Join-Path $repositoryRoot 'NOTICE.md'
$innoLanguageRoot = Join-Path $installerRoot 'languages'
$innoChineseLanguagePath = Join-Path $innoLanguageRoot 'ChineseSimplified.isl'
$innoSetupLicensePath = Join-Path $innoLanguageRoot 'Inno-Setup-License.txt'
$innoChineseLanguageSha256 = '7d544b9bb1d142cfa11f2e5d3cc8abe2e55f8e066c5124e3772675aa236e1278'
$innoSetupLicenseSha256 = '0c81595601bce47eeef8d865d5da7f9ca2c6a12235b7482b29f5ab23ed02ee5a'
$publicPresetRoot = Join-Path (Join-Path $repositoryRoot 'library') 'preset-red-white-abstract'
$libraryRoot = Join-Path $repositoryRoot 'library'
$libraryIntegrityPath = Join-Path $libraryRoot 'integrity.json'
$publicPresetImagePath = Join-Path $publicPresetRoot 'background.png'
$publicPresetThemePath = Join-Path $publicPresetRoot 'theme.json'
$publicPresetImageSha256 = '31bde93bb02d6723e0b6aa0ead675577604120acb0a6799163dd37f5cdd0a08e'
$publicPresetThemeSha256 = '1d2fbbd9323739e7720f9f17c96b7f617e3b596c21f0d976e9ceaed2fb8a109b'

function Read-ReleaseTextFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required release input does not exist: $Path"
  }
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-ReleasePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$BasePath
  )
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Assert-NodeRuntimeManifest {
  param([Parameter(Mandatory = $true)][object]$Manifest)
  $expectedVersion = '22.23.1'
  $expectedArchive = "node-v$expectedVersion-win-x64.zip"
  $expectedRoot = "node-v$expectedVersion-win-x64"
  $expectedUrl = "https://nodejs.org/dist/v$expectedVersion/$expectedArchive"
  $expectedHash = '7df0bc9375723f4a86b3aa1b7cc73342423d9677a8df4538aca31a049e309c29'

  if ("$($Manifest.version)" -cne $expectedVersion -or
    "$($Manifest.platform)" -cne 'win' -or
    "$($Manifest.architecture)" -cne 'x64' -or
    "$($Manifest.archive)" -cne $expectedArchive -or
    "$($Manifest.url)" -cne $expectedUrl -or
    "$($Manifest.sha256)" -cne $expectedHash -or
    "$($Manifest.nodeEntry)" -cne "$expectedRoot/node.exe" -or
    "$($Manifest.licenseEntry)" -cne "$expectedRoot/LICENSE") {
    throw 'The pinned Node.js runtime manifest differs from the reviewed v22.23.1 win-x64 release.'
  }
}

function Resolve-IsccExecutable {
  param([string]$RequestedPath)
  $candidates = @()
  if ($RequestedPath) { $candidates += $RequestedPath }
  if (${env:ProgramFiles(x86)}) {
    $candidates += Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
  }
  if ($env:ProgramFiles) {
    $candidates += Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'
  }
  if ($env:ChocolateyInstall) {
    $candidates += Join-Path $env:ChocolateyInstall 'bin\iscc.exe'
  }
  $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
  if ($command) { $candidates += $command.Source }

  foreach ($candidate in $candidates) {
    if (-not $candidate) { continue }
    $resolved = Resolve-ReleasePath -Path $candidate -BasePath $repositoryRoot
    if (Test-Path -LiteralPath $resolved -PathType Leaf) { return $resolved }
  }
  throw 'Inno Setup 6 compiler (ISCC.exe) was not found. Install Inno Setup 6 or pass -IsccPath.'
}

function Copy-ReleaseDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Required release directory does not exist: $Source"
  }
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force -ErrorAction Stop
  }
}

function Copy-ZipEntry {
  param(
    [Parameter(Mandatory = $true)][object]$Archive,
    [Parameter(Mandatory = $true)][string]$EntryName,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  $entry = $Archive.GetEntry($EntryName)
  if ($null -eq $entry -or $entry.Length -le 0) {
    throw "The Node.js archive is missing a non-empty entry: $EntryName"
  }
  $parent = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $input = $entry.Open()
  try {
    $output = [System.IO.File]::Open(
      $Destination,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    try { $input.CopyTo($output) } finally { $output.Dispose() }
  } finally {
    $input.Dispose()
  }
}

function Write-AuroraSkinIcon {
  param([Parameter(Mandatory = $true)][string]$Path)
  $sizes = @(16, 24, 32, 48, 64, 256)
  $images = New-Object System.Collections.Generic.List[byte[]]

  foreach ($size in $sizes) {
    $pixelBytes = $size * $size * 4
    $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
      $writer.Write([uint32]40)
      $writer.Write([int32]$size)
      $writer.Write([int32]($size * 2))
      $writer.Write([uint16]1)
      $writer.Write([uint16]32)
      $writer.Write([uint32]0)
      $writer.Write([uint32]$pixelBytes)
      $writer.Write([int32]3780)
      $writer.Write([int32]3780)
      $writer.Write([uint32]0)
      $writer.Write([uint32]0)

      $alphaRows = New-Object 'byte[][]' $size
      for ($row = $size - 1; $row -ge 0; $row--) {
        $alphaRow = New-Object byte[] $size
        for ($column = 0; $column -lt $size; $column++) {
          $coverage = 0
          $darkCoverage = 0
          $dotCoverage = 0
          $edgeCoverage = 0
          foreach ($sampleY in @(0.125, 0.375, 0.625, 0.875)) {
            foreach ($sampleX in @(0.125, 0.375, 0.625, 0.875)) {
              # AuroraSkin 品牌 mark（与网站 favicon 同源）：白圆角方 +
              # 墨色对角半区（x+y>=1）+ 青点 + 14% 发丝描边环。
              $x = ($column + $sampleX) / $size
              $y = ($row + $sampleY) / $size
              $dx = [Math]::Max([Math]::Abs($x - 0.5) - 0.16, 0.0)
              $dy = [Math]::Max([Math]::Abs($y - 0.5) - 0.16, 0.0)
              $edgeDistance = [Math]::Sqrt($dx * $dx + $dy * $dy)
              if ($edgeDistance -le 0.285) {
                $coverage++
                if (($x + $y) -ge 1.0) { $darkCoverage++ }
                $ddx = $x - 0.719
                $ddy = $y - 0.281
                if (($ddx * $ddx + $ddy * $ddy) -le (0.08 * 0.08)) { $dotCoverage++ }
                if ($edgeDistance -gt (0.285 - [Math]::Max(0.028, 1.1 / $size))) { $edgeCoverage++ }
              }
            }
          }

          $alpha = [int][Math]::Round(255.0 * $coverage / 16.0)
          $alphaRow[$column] = [byte]$alpha
          $darkBlend = $darkCoverage / 16.0
          $dotBlend = $dotCoverage / 16.0
          $edgeBlend = 0.14 * ($edgeCoverage / 16.0)
          $red = 253.0 * (1.0 - $darkBlend) + 23.0 * $darkBlend
          $green = 253.0 * (1.0 - $darkBlend) + 24.0 * $darkBlend
          $blue = 252.0 * (1.0 - $darkBlend) + 28.0 * $darkBlend
          $red = $red * (1.0 - $dotBlend) + 45.0 * $dotBlend
          $green = $green * (1.0 - $dotBlend) + 225.0 * $dotBlend
          $blue = $blue * (1.0 - $dotBlend) + 194.0 * $dotBlend
          $red = [int][Math]::Round($red * (1.0 - $edgeBlend) + 23.0 * $edgeBlend)
          $green = [int][Math]::Round($green * (1.0 - $edgeBlend) + 24.0 * $edgeBlend)
          $blue = [int][Math]::Round($blue * (1.0 - $edgeBlend) + 28.0 * $edgeBlend)
          $writer.Write([byte]$blue)
          $writer.Write([byte]$green)
          $writer.Write([byte]$red)
          $writer.Write([byte]$alpha)
        }
        $alphaRows[$row] = $alphaRow
      }

      for ($row = $size - 1; $row -ge 0; $row--) {
        $maskRow = New-Object byte[] $maskStride
        for ($column = 0; $column -lt $size; $column++) {
          if ($alphaRows[$row][$column] -eq 0) {
            $byteIndex = [int][Math]::Floor($column / 8.0)
            $maskRow[$byteIndex] = $maskRow[$byteIndex] -bor (0x80 -shr ($column % 8))
          }
        }
        $writer.Write($maskRow)
      }
      $writer.Flush()
      $images.Add($stream.ToArray())
    } finally {
      $writer.Dispose()
      $stream.Dispose()
    }
  }

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $iconStream = [System.IO.File]::Open(
    $Path,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None
  )
  $iconWriter = [System.IO.BinaryWriter]::new($iconStream)
  try {
    $iconWriter.Write([uint16]0)
    $iconWriter.Write([uint16]1)
    $iconWriter.Write([uint16]$sizes.Count)
    $offset = 6 + (16 * $sizes.Count)
    for ($index = 0; $index -lt $sizes.Count; $index++) {
      $dimension = if ($sizes[$index] -eq 256) { 0 } else { $sizes[$index] }
      $iconWriter.Write([byte]$dimension)
      $iconWriter.Write([byte]$dimension)
      $iconWriter.Write([byte]0)
      $iconWriter.Write([byte]0)
      $iconWriter.Write([uint16]1)
      $iconWriter.Write([uint16]32)
      $iconWriter.Write([uint32]$images[$index].Length)
      $iconWriter.Write([uint32]$offset)
      $offset += $images[$index].Length
    }
    foreach ($image in $images) { $iconWriter.Write($image) }
  } finally {
    $iconWriter.Dispose()
    $iconStream.Dispose()
  }
}

$version = (Read-ReleaseTextFile -Path $versionPath).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
  throw "windows/VERSION must contain a three-part semantic version: $version"
}
$macosVersion = (Read-ReleaseTextFile -Path $macosVersionPath).Trim()
$macosPackage = (Read-ReleaseTextFile -Path $macosPackagePath) | ConvertFrom-Json
if ($macosVersion -cne $version -or "$($macosPackage.version)" -cne $version) {
  throw "Release versions differ: windows=$version macOS=$macosVersion package=$($macosPackage.version)"
}

$manifest = (Read-ReleaseTextFile -Path $manifestPath) | ConvertFrom-Json
Assert-NodeRuntimeManifest -Manifest $manifest
$null = Read-ReleaseTextFile -Path $definitionPath
$null = Read-ReleaseTextFile -Path $bootstrapPath
$null = Read-ReleaseTextFile -Path $launcherSourcePath
$null = Read-ReleaseTextFile -Path $licensePath
$null = Read-ReleaseTextFile -Path $noticePath
$null = Read-ReleaseTextFile -Path $innoChineseLanguagePath
$null = Read-ReleaseTextFile -Path $innoSetupLicensePath
$libraryIntegrity = (Read-ReleaseTextFile -Path $libraryIntegrityPath) | ConvertFrom-Json
if ($libraryIntegrity.schemaVersion -ne 1 -or $null -eq $libraryIntegrity.files) {
  throw 'The built-in resource integrity manifest is invalid.'
}
foreach ($property in $libraryIntegrity.files.PSObject.Properties) {
  $relative = "$($property.Name)"
  $expectedHash = "$($property.Value)"
  if ($relative.Contains('..') -or $relative.Contains('\') -or
    $expectedHash -cnotmatch '^[a-f0-9]{64}$') {
    throw "The built-in resource integrity entry is invalid: $relative"
  }
  $resourcePath = Join-Path $libraryRoot ($relative.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $resourcePath -PathType Leaf) -or
    (Get-FileHash -LiteralPath $resourcePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
    $expectedHash) {
    throw "Built-in resource integrity verification failed: $relative"
  }
}
$innoChineseLanguageHash = (Get-FileHash -LiteralPath $innoChineseLanguagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($innoChineseLanguageHash -cne $innoChineseLanguageSha256) {
  throw "The pinned Inno Setup Simplified Chinese messages changed. Expected $innoChineseLanguageSha256, found $innoChineseLanguageHash."
}
$innoSetupLicenseHash = (Get-FileHash -LiteralPath $innoSetupLicensePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($innoSetupLicenseHash -cne $innoSetupLicenseSha256) {
  throw "The pinned Inno Setup license changed. Expected $innoSetupLicenseSha256, found $innoSetupLicenseHash."
}
$publicPresetTheme = (Read-ReleaseTextFile -Path $publicPresetThemePath) | ConvertFrom-Json
if ("$($publicPresetTheme.id)" -cne 'preset-red-white-abstract' -or
  "$($publicPresetTheme.image)" -cne 'background.png') {
  throw 'The public Windows release preset metadata is unexpected.'
}
if (-not (Test-Path -LiteralPath $publicPresetImagePath -PathType Leaf)) {
  throw "The public Windows release preset image is missing: $publicPresetImagePath"
}
$publicPresetImageHash = (Get-FileHash -LiteralPath $publicPresetImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($publicPresetImageHash -cne $publicPresetImageSha256) {
  throw "The reviewed public preset image changed. Expected $publicPresetImageSha256, found $publicPresetImageHash."
}
$publicPresetThemeHash = (Get-FileHash -LiteralPath $publicPresetThemePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($publicPresetThemeHash -cne $publicPresetThemeSha256) {
  throw "The reviewed public preset metadata changed. Expected $publicPresetThemeSha256, found $publicPresetThemeHash."
}
$compiler = Resolve-IsccExecutable -RequestedPath $IsccPath

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'release' }
$OutputDirectory = Resolve-ReleasePath -Path $OutputDirectory -BasePath $repositoryRoot
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if ($WorkingDirectory) {
  $WorkingDirectory = Resolve-ReleasePath -Path $WorkingDirectory -BasePath $repositoryRoot
  if (Test-Path -LiteralPath $WorkingDirectory) {
    throw "The requested working directory already exists: $WorkingDirectory"
  }
  New-Item -ItemType Directory -Path $WorkingDirectory | Out-Null
} else {
  $WorkingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) (
    'codex-aurora-skin-windows-release-' + [guid]::NewGuid().ToString('N')
  )
  New-Item -ItemType Directory -Path $WorkingDirectory | Out-Null
}

try {
  $archivePath = if ($NodeArchivePath) {
    Resolve-ReleasePath -Path $NodeArchivePath -BasePath $repositoryRoot
  } else {
    Join-Path $WorkingDirectory "$($manifest.archive)"
  }
  if (-not $NodeArchivePath) {
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Write-Host "Downloading pinned Node.js v$($manifest.version) runtime..."
      Invoke-WebRequest -UseBasicParsing -Uri "$($manifest.url)" -OutFile $archivePath
    } finally {
      [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
  }
  if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Node.js archive does not exist: $archivePath"
  }
  $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($archiveHash -cne "$($manifest.sha256)") {
    throw "Node.js archive SHA-256 mismatch. Expected $($manifest.sha256), found $archiveHash."
  }

  $stageRoot = Join-Path $WorkingDirectory 'stage'
  $payloadRoot = Join-Path $stageRoot 'payload'
  $nodeRoot = Join-Path (Join-Path $payloadRoot 'runtime') 'node'
  $languageRoot = Join-Path $stageRoot 'languages'
  New-Item -ItemType Directory -Path $payloadRoot | Out-Null
  New-Item -ItemType Directory -Path $languageRoot | Out-Null
  Copy-ReleaseDirectory -Source (Join-Path $windowsRoot 'assets') -Destination (Join-Path $payloadRoot 'assets')
  Copy-ReleaseDirectory -Source (Join-Path $windowsRoot 'scripts') -Destination (Join-Path $payloadRoot 'scripts')
  $managerPayloadRoot = Join-Path $payloadRoot 'manager'
  $managerWebPayloadRoot = Join-Path $managerPayloadRoot 'web'
  New-Item -ItemType Directory -Path $managerWebPayloadRoot -Force | Out-Null
  foreach ($relative in @(
      'image-metadata.mjs',
      'heartbeat-lease.mjs',
      'server.mjs',
      'theme-store.mjs',
      'web\api-client.mjs',
      'web\app.js',
      'web\index.html',
      'web\styles.css'
    )) {
    $source = Join-Path (Join-Path $repositoryRoot 'manager') $relative
    $destination = Join-Path $managerPayloadRoot $relative
    Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
  }
  Copy-ReleaseDirectory -Source (Join-Path $repositoryRoot 'library') `
    -Destination (Join-Path $payloadRoot 'library')
  [System.IO.File]::WriteAllText(
    (Join-Path $payloadRoot 'VERSION'),
    "$version`r`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  Copy-Item -LiteralPath $bootstrapPath -Destination (Join-Path $stageRoot 'setup-bootstrap.ps1') -Force
  Copy-Item -LiteralPath $licensePath -Destination (Join-Path $stageRoot 'LICENSE.txt') -Force
  Copy-Item -LiteralPath $noticePath -Destination (Join-Path $stageRoot 'NOTICE.md') -Force
  Copy-Item -LiteralPath $innoChineseLanguagePath `
    -Destination (Join-Path $languageRoot 'ChineseSimplified.isl') -Force

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
  try {
    Copy-ZipEntry -Archive $zip -EntryName "$($manifest.nodeEntry)" `
      -Destination (Join-Path $nodeRoot 'node.exe')
    Copy-ZipEntry -Archive $zip -EntryName "$($manifest.licenseEntry)" `
      -Destination (Join-Path $nodeRoot 'LICENSE')
  } finally {
    $zip.Dispose()
  }
  Write-AuroraSkinIcon -Path (Join-Path (Join-Path $payloadRoot 'assets') 'codex-aurora-skin.ico')
  $csharpCompiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (-not $csharpCompiler) {
    throw 'The Windows .NET Framework C# compiler required for the no-console launcher was not found.'
  }
  $launcherOutputPath = Join-Path $stageRoot 'CodexAuroraSkin.Launcher.exe'
  & $csharpCompiler `
    '/nologo' `
    '/target:winexe' `
    '/optimize+' `
    "/out:$launcherOutputPath" `
    '/reference:System.dll' `
    '/reference:System.Windows.Forms.dll' `
    $launcherSourcePath
  if ($LASTEXITCODE -ne 0 -or
    -not (Test-Path -LiteralPath $launcherOutputPath -PathType Leaf)) {
    throw 'The no-console Windows launcher could not be compiled.'
  }

  $expectedPayloadFiles = @(
    'VERSION',
    'assets\aurora-skin.css',
    'assets\renderer-inject.js',
    'assets\selectors.json',
    'assets\codex-aurora-skin.ico',
    'library\catalog.json',
    'library\integrity.json',
    'library\preset-red-white-abstract\background.png',
    'library\preset-red-white-abstract\thumbnail.webp',
    'library\preset-red-white-abstract\theme.json',
    'manager\server.mjs',
    'manager\theme-store.mjs',
    'manager\image-metadata.mjs',
    'manager\heartbeat-lease.mjs',
    'manager\web\index.html',
    'manager\web\styles.css',
    'manager\web\app.js',
    'manager\web\api-client.mjs',
    'scripts\common-windows.ps1',
    'scripts\config-utf8.ps1',
    'scripts\image-metadata.mjs',
    'scripts\injector.mjs',
    'scripts\install-aurora-skin.ps1',
    'scripts\launch-manager.ps1',
    'scripts\restore-aurora-skin.ps1',
    'scripts\start-aurora-skin.ps1',
    'scripts\theme-windows.ps1',
    'scripts\verify-aurora-skin.ps1',
    'runtime\node\node.exe',
    'runtime\node\LICENSE'
  )
  foreach ($relative in $expectedPayloadFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $relative) -PathType Leaf)) {
      throw "Staged installer payload is incomplete: $relative"
    }
  }
  if (Get-ChildItem -LiteralPath (Join-Path $payloadRoot 'manager') -Recurse -File |
      Where-Object { $_.Name -like '*.test.mjs' }) {
    throw 'Staged installer payload must not contain manager test files.'
  }
  $stagedPublicThemePath = Join-Path (Join-Path $payloadRoot 'library') `
    'preset-red-white-abstract\theme.json'
  $stagedPublicThemeHash = (Get-FileHash -LiteralPath $stagedPublicThemePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($stagedPublicThemeHash -cne $publicPresetThemeSha256) {
    throw 'Staged installer payload did not retain the reviewed public release theme.'
  }

  $arguments = @(
    "/DAppVersion=$version",
    "/DStageRoot=$stageRoot",
    "/DOutputDir=$OutputDirectory",
    $definitionPath
  )
  Write-Host "Building CodexAuroraSkin-Setup-v$version.exe..."
  & $compiler @arguments
  if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed with exit code $LASTEXITCODE." }

  $artifactPath = Join-Path $OutputDirectory "CodexAuroraSkin-Setup-v$version.exe"
  if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "Inno Setup did not create the expected artifact: $artifactPath"
  }
  $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
  $checksumPath = "$artifactPath.sha256"
  [System.IO.File]::WriteAllText(
    $checksumPath,
    "$artifactHash  $([System.IO.Path]::GetFileName($artifactPath))`r`n",
    [System.Text.UTF8Encoding]::new($false)
  )
  Write-Host "Windows release created: $artifactPath"
  Write-Host "SHA-256 checksum created: $checksumPath"
} finally {
  if (-not $KeepWorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
    Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
  } elseif ($KeepWorkingDirectory) {
    Write-Host "Windows release working directory preserved at: $WorkingDirectory"
  }
}
