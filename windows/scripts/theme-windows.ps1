if (-not (Get-Command Read-AuroraSkinUtf8File -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'config-utf8.ps1')
}

$script:AuroraSkinMaxImageBytes = 16 * 1024 * 1024

function Assert-AuroraSkinNoReparseComponents {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($fullPath)
  $current = $fullPath
  while ($true) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Managed Aurora Skin path contains a junction or symbolic link: $current"
      }
    }
    $currentNormalized = $current.TrimEnd('\')
    $rootNormalized = $root.TrimEnd('\')
    if ($currentNormalized.Equals($rootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) { break }
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) { break }
    $current = $parent
  }
}

function Ensure-AuroraSkinManagedDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "Managed Aurora Skin path escaped its state root: $fullPath"
  }
  Assert-AuroraSkinNoReparseComponents -Path $fullPath
  if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
    throw "Managed Aurora Skin path is a file, not a directory: $fullPath"
  }
  New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
  Assert-AuroraSkinNoReparseComponents -Path $fullPath
  if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
    throw "Managed Aurora Skin directory could not be created: $fullPath"
  }
}

function Get-AuroraSkinValidatedImageMetadata {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Get-Command Get-AuroraSkinNodeRuntime -ErrorAction SilentlyContinue)) {
    throw 'Node.js runtime validation is unavailable for image metadata checks.'
  }
  $node = Get-AuroraSkinNodeRuntime
  $metadataScript = Join-Path $PSScriptRoot 'image-metadata.mjs'
  $output = @(& $node.Path $metadataScript '--check' ([System.IO.Path]::GetFullPath($Path)) 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "Image metadata is invalid or exceeds the 16384px / 50MP safety limit: $Path"
  }
  try { $metadata = ($output -join "`n") | ConvertFrom-Json -ErrorAction Stop } catch {
    throw "Image metadata helper returned invalid output: $Path"
  }
  if ($null -eq $metadata -or $null -eq $metadata.width -or $null -eq $metadata.height) {
    throw "Image metadata is invalid or exceeds the 16384px / 50MP safety limit: $Path"
  }
}

function Assert-AuroraSkinImageFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$SkipImageMetadata
  )
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Image does not exist: $fullPath"
  }
  $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
  if ($extension -notin @('.png', '.jpg', '.jpeg', '.webp')) {
    throw "Unsupported image format: $extension"
  }
  $length = (Get-Item -LiteralPath $fullPath -Force).Length
  if ($length -lt 1) { throw 'Theme image cannot be empty.' }
  if ($length -gt $script:AuroraSkinMaxImageBytes) {
    throw 'Theme image exceeds the 16 MB limit.'
  }
  if (-not $SkipImageMetadata) {
    Get-AuroraSkinValidatedImageMetadata -Path $fullPath
  }
}

function Get-AuroraSkinThemePaths {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'))
  $fullRoot = [System.IO.Path]::GetFullPath($StateRoot)
  return [pscustomobject]@{
    Root = $fullRoot
    Active = Join-Path $fullRoot 'active-theme'
    Saved = Join-Path $fullRoot 'themes'
    Images = Join-Path $fullRoot 'images'
    PauseFile = Join-Path $fullRoot 'paused'
    State = Join-Path $fullRoot 'state.json'
  }
}

function Test-AuroraSkinThemePathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    $inside = $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $inside) { return $false }

    $current = $fullPath.TrimEnd('\')
    while ($true) {
      if (-not (Test-Path -LiteralPath $current)) { return $false }
      $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $false
      }
      if ($current.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
      }
      $parent = [System.IO.Path]::GetDirectoryName($current)
      if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
      }
      $current = $parent.TrimEnd('\')
    }
  } catch {
    return $false
  }
}

function Read-AuroraSkinTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    [switch]$SkipImageMetadata
  )
  $directory = [System.IO.Path]::GetFullPath($ThemeDirectory)
  Assert-AuroraSkinNoReparseComponents -Path $directory
  $themePath = Join-Path $directory 'theme.json'
  Assert-AuroraSkinNoReparseComponents -Path $themePath
  if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw "Theme metadata is missing: $themePath"
  }
  try {
    $theme = (Read-AuroraSkinUtf8File -Path $themePath) | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Theme metadata is invalid JSON: $themePath"
  }
  if ($null -eq $theme -or $theme -is [string] -or $theme -is [array] -or -not $theme.image) {
    throw "Theme metadata must be an object with a relative image path: $themePath"
  }
  $image = "$($theme.image)"
  if ([System.IO.Path]::IsPathRooted($image)) { throw 'Theme image path must be relative.' }
  $imagePath = [System.IO.Path]::GetFullPath((Join-Path $directory $image))
  if (-not (Test-AuroraSkinThemePathWithin -Path $imagePath -Root $directory) -or
    -not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
    throw 'Theme image must remain inside its theme directory and exist.'
  }
  Assert-AuroraSkinImageFile -Path $imagePath -SkipImageMetadata:$SkipImageMetadata
  return [pscustomobject]@{
    Directory = $directory
    ThemePath = $themePath
    ImagePath = $imagePath
    Theme = $theme
  }
}

function Write-AuroraSkinTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    [Parameter(Mandatory = $true)][object]$Theme
  )
  Assert-AuroraSkinNoReparseComponents -Path $ThemeDirectory
  New-Item -ItemType Directory -Force -Path $ThemeDirectory | Out-Null
  Assert-AuroraSkinNoReparseComponents -Path $ThemeDirectory
  $json = $Theme | ConvertTo-Json -Depth 8
  $themePath = Join-Path $ThemeDirectory 'theme.json'
  Assert-AuroraSkinNoReparseComponents -Path $themePath
  Write-AuroraSkinUtf8FileAtomically -Path $themePath -Content ($json + "`r`n")
}

function Get-AuroraSkinActiveThemeAppearance {
  param([Parameter(Mandatory = $true)][string]$ThemeDirectory)
  try {
    $appearance = "$((Read-AuroraSkinTheme -ThemeDirectory $ThemeDirectory).Theme.appearance)"
    if ($appearance -in @('light', 'dark')) { return $appearance }
  } catch {}
  return 'auto'
}

function Initialize-AuroraSkinThemeStore {
  param(
    [Parameter(Mandatory = $true)][string]$SkillRoot,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  )
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  foreach ($directory in @($paths.Root, $paths.Active, $paths.Saved, $paths.Images)) {
    Ensure-AuroraSkinManagedDirectory -Path $directory -Root $paths.Root
  }
  $assetRoot = Join-Path $SkillRoot 'assets'
  $bundledTheme = Read-AuroraSkinTheme -ThemeDirectory $assetRoot
  $assetImage = $bundledTheme.ImagePath
  $assetImageName = [System.IO.Path]::GetFileName($assetImage)
  $bundledPresetId = "$($bundledTheme.Theme.id)"
  if ($bundledPresetId -cnotmatch '^preset-[A-Za-z0-9_-]{1,72}$') {
    throw "Bundled theme id must be a safe preset id: $bundledPresetId"
  }
  $activeTheme = Join-Path $paths.Active 'theme.json'
  Assert-AuroraSkinNoReparseComponents -Path $activeTheme
  if (-not (Test-Path -LiteralPath $activeTheme -PathType Leaf)) {
    Ensure-AuroraSkinManagedDirectory -Path $paths.Active -Root $paths.Root
    Assert-AuroraSkinNoReparseComponents -Path (Join-Path $paths.Active $assetImageName)
    $activeImage = Join-Path $paths.Active $assetImageName
    Copy-Item -LiteralPath $assetImage -Destination $activeImage -Force
    Assert-AuroraSkinNoReparseComponents -Path $activeImage
    Assert-AuroraSkinImageFile -Path $activeImage
    $imageArchive = Join-Path $paths.Images $assetImageName
    Assert-AuroraSkinNoReparseComponents -Path $imageArchive
    Copy-Item -LiteralPath $assetImage -Destination $imageArchive -Force
    Assert-AuroraSkinNoReparseComponents -Path $imageArchive
    Assert-AuroraSkinImageFile -Path $imageArchive
    Assert-AuroraSkinNoReparseComponents -Path $activeTheme
    Copy-Item -LiteralPath (Join-Path $assetRoot 'theme.json') -Destination $activeTheme -Force
  }
  $retiredPresetDirectory = Join-Path $paths.Saved 'preset-romantic-rose'
  Assert-AuroraSkinNoReparseComponents -Path $retiredPresetDirectory
  if (Test-Path -LiteralPath $retiredPresetDirectory) {
    Remove-Item -LiteralPath $retiredPresetDirectory -Recurse -Force
  }
  $presetDirectory = Join-Path $paths.Saved $bundledPresetId
  $presetTheme = Join-Path $presetDirectory 'theme.json'
  Assert-AuroraSkinNoReparseComponents -Path $presetDirectory
  Assert-AuroraSkinNoReparseComponents -Path $presetTheme
  # Refresh the saved copy on every run (matching macOS seeding) so preset
  # metadata upgrades — e.g. the #183 appearance pin — reach existing installs.
  Ensure-AuroraSkinManagedDirectory -Path $presetDirectory -Root $paths.Root
  $presetImage = Join-Path $presetDirectory $assetImageName
  Assert-AuroraSkinNoReparseComponents -Path $presetImage
  Copy-Item -LiteralPath $assetImage -Destination $presetImage -Force
  Assert-AuroraSkinNoReparseComponents -Path $presetImage
  Assert-AuroraSkinImageFile -Path $presetImage
  Assert-AuroraSkinNoReparseComponents -Path $presetTheme
  Copy-Item -LiteralPath (Join-Path $assetRoot 'theme.json') -Destination $presetTheme -Force
  # Refresh the staged active copy of official presets too; otherwise metadata
  # staged by an older engine (e.g. pre-#183 appearance "auto") keeps steering
  # the appearanceTheme pin after upgrades.
  if (Test-Path -LiteralPath $activeTheme -PathType Leaf) {
    $activeId = ''
    try {
      $activeId = "$((Read-AuroraSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata).Theme.id)"
    } catch {}
    $refreshSource = $null
    if ($activeId -ceq $bundledPresetId) { $refreshSource = $assetRoot }
    if ($null -ne $refreshSource) {
      $sourcePack = Read-AuroraSkinTheme -ThemeDirectory $refreshSource
      $sourceJson = Read-AuroraSkinUtf8File -Path $sourcePack.ThemePath
      $activeJson = Read-AuroraSkinUtf8File -Path $activeTheme
      if ($sourceJson -cne $activeJson) {
        $sourceImageName = [System.IO.Path]::GetFileName($sourcePack.ImagePath)
        $refreshedImage = Join-Path $paths.Active $sourceImageName
        Assert-AuroraSkinNoReparseComponents -Path $refreshedImage
        Copy-Item -LiteralPath $sourcePack.ImagePath -Destination $refreshedImage -Force
        Assert-AuroraSkinNoReparseComponents -Path $refreshedImage
        Assert-AuroraSkinImageFile -Path $refreshedImage
        Copy-Item -LiteralPath $sourcePack.ThemePath -Destination $activeTheme -Force
      }
    }
  }
  $null = Read-AuroraSkinTheme -ThemeDirectory $paths.Active
  return $paths
}

function New-AuroraSkinThemeImageName {
  param([Parameter(Mandatory = $true)][string]$Extension)
  return 'art-' + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 8) + $Extension.ToLowerInvariant()
}

function Set-AuroraSkinActiveTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [AllowNull()][object]$Theme,
    [string]$Name,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  )
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-AuroraSkinManagedDirectory -Path $paths.Active -Root $paths.Root
  Ensure-AuroraSkinManagedDirectory -Path $paths.Images -Root $paths.Root
  $source = [System.IO.Path]::GetFullPath($ImagePath)
  Assert-AuroraSkinImageFile -Path $source
  $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
  $oldImage = $null
  try { $oldImage = (Read-AuroraSkinTheme -ThemeDirectory $paths.Active).ImagePath } catch {}
  if ($null -eq $Theme) {
    $Theme = [pscustomobject]@{
      id = 'custom'
      name = '自定义主题'
      appearance = 'auto'
      art = [pscustomobject]@{ focusX = $null; focusY = $null; safeArea = 'auto'; taskMode = 'auto' }
      palette = [pscustomobject]@{}
    }
  }
  $imageName = New-AuroraSkinThemeImageName -Extension $extension
  $target = Join-Path $paths.Active $imageName
  $temporary = Join-Path $paths.Active ('.dream-tmp-' + [guid]::NewGuid().ToString('N') + $extension)
  try {
    Assert-AuroraSkinNoReparseComponents -Path $target
    Assert-AuroraSkinNoReparseComponents -Path $temporary
    Copy-Item -LiteralPath $source -Destination $temporary -Force
    Assert-AuroraSkinNoReparseComponents -Path $temporary
    Assert-AuroraSkinImageFile -Path $temporary
    Move-Item -LiteralPath $temporary -Destination $target -Force
    Assert-AuroraSkinNoReparseComponents -Path $target
    Assert-AuroraSkinImageFile -Path $target
    $Theme | Add-Member -NotePropertyName image -NotePropertyValue $imageName -Force
    if ($Name) { $Theme | Add-Member -NotePropertyName name -NotePropertyValue $Name -Force }
    if (-not $Theme.id) { $Theme | Add-Member -NotePropertyName id -NotePropertyValue 'custom' -Force }
    if (-not $Theme.appearance) { $Theme | Add-Member -NotePropertyName appearance -NotePropertyValue 'auto' -Force }
    if (-not $Theme.art) {
      $Theme | Add-Member -NotePropertyName art -NotePropertyValue `
        ([pscustomobject]@{ focusX = $null; focusY = $null; safeArea = 'auto'; taskMode = 'auto' }) -Force
    }
    if (-not $Theme.palette) {
      $Theme | Add-Member -NotePropertyName palette -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    Write-AuroraSkinTheme -ThemeDirectory $paths.Active -Theme $Theme
  } finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
  $sameImage = $oldImage -and ([System.IO.Path]::GetFullPath($oldImage) -ieq [System.IO.Path]::GetFullPath($target))
  if ($oldImage -and -not $sameImage -and
    (Test-AuroraSkinThemePathWithin -Path $oldImage -Root $paths.Active)) {
    Remove-Item -LiteralPath $oldImage -Force -ErrorAction SilentlyContinue
  }
  $imageArchive = Join-Path $paths.Images $imageName
  Assert-AuroraSkinNoReparseComponents -Path $imageArchive
  Copy-Item -LiteralPath $target -Destination $imageArchive -Force
  Assert-AuroraSkinNoReparseComponents -Path $imageArchive
  Assert-AuroraSkinImageFile -Path $imageArchive
  return Read-AuroraSkinTheme -ThemeDirectory $paths.Active
}

function Save-AuroraSkinCurrentTheme {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  )
  $trimmed = $Name.Trim()
  if (-not $trimmed -or $trimmed.Length -gt 80 -or $trimmed -match '[\u0000-\u001f]') {
    throw 'Theme name must be between 1 and 80 visible characters.'
  }
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-AuroraSkinManagedDirectory -Path $paths.Saved -Root $paths.Root
  $active = Read-AuroraSkinTheme -ThemeDirectory $paths.Active
  $id = (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
  $destination = Join-Path $paths.Saved $id
  Ensure-AuroraSkinManagedDirectory -Path $destination -Root $paths.Root
  $extension = [System.IO.Path]::GetExtension($active.ImagePath).ToLowerInvariant()
  $imageName = 'art' + $extension
  $destinationImage = Join-Path $destination $imageName
  Assert-AuroraSkinNoReparseComponents -Path $destinationImage
  Copy-Item -LiteralPath $active.ImagePath -Destination $destinationImage -Force
  Assert-AuroraSkinNoReparseComponents -Path $destinationImage
  Assert-AuroraSkinImageFile -Path $destinationImage
  $theme = $active.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $theme.id = $id
  $theme.name = $trimmed
  $theme.image = $imageName
  Write-AuroraSkinTheme -ThemeDirectory $destination -Theme $theme
  return Read-AuroraSkinTheme -ThemeDirectory $destination
}

function Get-AuroraSkinSavedThemes {
  param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'),
    [switch]$SkipImageMetadata
  )
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-AuroraSkinManagedDirectory -Path $paths.Saved -Root $paths.Root
  if (-not (Test-Path -LiteralPath $paths.Saved -PathType Container)) { return @() }
  $themes = @()
  foreach ($directory in Get-ChildItem -LiteralPath $paths.Saved -Directory -ErrorAction SilentlyContinue) {
    try {
      $loaded = Read-AuroraSkinTheme -ThemeDirectory $directory.FullName -SkipImageMetadata:$SkipImageMetadata
      $themes += [pscustomobject]@{
        Id = "$($loaded.Theme.id)"
        Name = if ($loaded.Theme.name) { "$($loaded.Theme.name)" } else { $directory.Name }
        Path = $directory.FullName
      }
    } catch {}
  }
  return @($themes | Sort-Object Name)
}

function Use-AuroraSkinSavedTheme {
  param(
    [Parameter(Mandatory = $true)][string]$ThemeDirectory,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  )
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  Ensure-AuroraSkinManagedDirectory -Path $paths.Saved -Root $paths.Root
  $directory = [System.IO.Path]::GetFullPath($ThemeDirectory)
  if (-not (Test-AuroraSkinThemePathWithin -Path $directory -Root $paths.Saved)) {
    throw 'Saved theme must remain inside the Aurora Skin themes folder.'
  }
  $saved = Read-AuroraSkinTheme -ThemeDirectory $directory
  $theme = $saved.Theme | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  return Set-AuroraSkinActiveTheme -ImagePath $saved.ImagePath -Theme $theme -StateRoot $StateRoot
}

function Set-AuroraSkinPaused {
  param(
    [Parameter(Mandatory = $true)][bool]$Paused,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  )
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $paths.Root -Root $paths.Root
  if ($Paused) {
    Assert-AuroraSkinNoReparseComponents -Path $paths.PauseFile
    Write-AuroraSkinUtf8FileAtomically -Path $paths.PauseFile -Content "paused`r`n"
  } else {
    if (Test-Path -LiteralPath $paths.PauseFile) { Assert-AuroraSkinNoReparseComponents -Path $paths.PauseFile }
    Remove-Item -LiteralPath $paths.PauseFile -Force -ErrorAction SilentlyContinue
  }
  return $Paused
}

function Test-AuroraSkinPaused {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'))
  return (Test-Path -LiteralPath (Get-AuroraSkinThemePaths -StateRoot $StateRoot).PauseFile -PathType Leaf)
}

function Get-AuroraSkinLiveSessionContext {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'))
  $paths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  $state = $null
  try { $state = Read-AuroraSkinState -Path $paths.State } catch { $state = $null }
  if ($null -eq $state -or -not $state.port -or -not $state.browserId) { return $null }
  $port = 0
  if (-not [int]::TryParse("$($state.port)", [ref]$port)) { return $null }
  Assert-AuroraSkinPort -Port $port
  $browserId = "$($state.browserId)".Trim()
  if (-not (Test-AuroraSkinBrowserId -Value $browserId)) { return $null }
  if (-not (Get-Command Get-AuroraSkinNodeRuntime -ErrorAction SilentlyContinue) -or
    -not (Get-Command Invoke-AuroraSkinNative -ErrorAction SilentlyContinue)) {
    return $null
  }
  $node = Get-AuroraSkinNodeRuntime
  $injector = Join-Path $PSScriptRoot 'injector.mjs'
  if (-not (Test-Path -LiteralPath $injector)) { return $null }
  return [pscustomobject]@{
    Paths = $paths
    State = $state
    Port = $port
    BrowserId = $browserId
    NodePath = $node.Path
    Injector = $injector
  }
}

function New-AuroraSkinOperationToken {
  $pidPart = [string]$PID
  $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $seq = Get-Random -Minimum 1 -Maximum 99999999
  return "${pidPart}:${ms}:${seq}"
}

function Show-AuroraSkinOperationUi {
  param(
    [Parameter(Mandatory = $true)][object]$Session,
    [Parameter(Mandatory = $true)][ValidateSet('begin', 'finish')][string]$Phase,
    [string]$Kind = 'apply',
    [string]$Token,
    [ValidateSet('success', 'error', 'cancelled')][string]$UiState = 'success',
    [string]$Message = '',
    [int]$TimeoutMs = 3000
  )
  $argumentList = @($Session.Injector, "--port", "$($Session.Port)", "--browser-id", $Session.BrowserId, "--timeout-ms", "$TimeoutMs")
  if ($Phase -eq 'begin') {
    if ($Kind -notin @('apply', 'pause', 'switch')) { throw "Invalid operation kind: $Kind" }
    $token = if ($Token) { $Token } else { New-AuroraSkinOperationToken }
    $argumentList += @('--begin-operation', '--operation-kind', $Kind, '--operation-token', $token)
    $probe = Invoke-AuroraSkinNative -FilePath $Session.NodePath -ArgumentList $argumentList -DiscardStderr
    $printed = (($probe.Output -join "`n").Trim() -split "`n" | Select-Object -Last 1).Trim()
    if ($probe.ExitCode -ne 0 -or -not $printed) {
      return [pscustomobject]@{ Ok = $false; Token = $token; Message = '无法在 Codex 窗口显示进度。' }
    }
    return [pscustomobject]@{ Ok = $true; Token = $printed; Message = '' }
  }
  if (-not $Token) { throw 'Finish operation requires a token.' }
  if ($Message.Length -gt 240 -or $Message -match "[\r\n]") { throw 'Invalid operation message.' }
  $argumentList += @(
    '--finish-operation',
    '--operation-ui-state', $UiState,
    '--operation-message', $Message,
    '--operation-token', $Token
  )
  $probe = Invoke-AuroraSkinNative -FilePath $Session.NodePath -ArgumentList $argumentList -DiscardStderr
  return [pscustomobject]@{
    Ok = ($probe.ExitCode -eq 0)
    Token = $Token
    Message = if ($probe.ExitCode -eq 0) { '' } else { '无法更新 Codex 窗口内的操作状态。' }
  }
}

# Mirror macOS pause: mark paused, show in-app loading, then strip the live skin over CDP.
# Writing only the pause file leaves CSS in the renderer until the watcher polls.
function Invoke-AuroraSkinLiveRemove {
  param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'),
    [int]$TimeoutMs = 8000
  )
  if ($TimeoutMs -lt 250 -or $TimeoutMs -gt 120000) {
    throw "Invalid live-remove timeout: $TimeoutMs"
  }
  $session = Get-AuroraSkinLiveSessionContext -StateRoot $StateRoot
  if ($null -eq $session) {
    return [pscustomobject]@{
      Attempted = $false
      Removed = $false
      Message = '没有可连接的活动会话；已记录暂停，当前窗口可能仍显示皮肤。'
    }
  }

  $token = $null
  $begin = Show-AuroraSkinOperationUi -Session $session -Phase begin -Kind pause -TimeoutMs 3000
  if ($begin.Ok) { $token = $begin.Token }

  $argumentList = @(
    $session.Injector,
    '--remove',
    '--port', "$($session.Port)",
    '--browser-id', $session.BrowserId,
    '--timeout-ms', "$TimeoutMs"
  )
  if ($token) { $argumentList += @('--operation-token', $token) }
  if (Test-Path -LiteralPath $session.Paths.Active) {
    $argumentList += @('--theme-dir', $session.Paths.Active)
  }

  $removal = Invoke-AuroraSkinNative -FilePath $session.NodePath -ArgumentList $argumentList -DiscardStderr
  if ($removal.ExitCode -eq 0) {
    if ($token) {
      $null = Show-AuroraSkinOperationUi -Session $session -Phase finish -Token $token `
        -UiState success -Message '皮肤已暂停' -TimeoutMs 1500
    }
    return [pscustomobject]@{
      Attempted = $true
      Removed = $true
      Message = '皮肤已暂停'
    }
  }
  if ($token) {
    $null = Show-AuroraSkinOperationUi -Session $session -Phase finish -Token $token `
      -UiState error -Message '暂停失败，请重试' -TimeoutMs 1500
  }
  return [pscustomobject]@{
    Attempted = $true
    Removed = $false
    Message = '已记录暂停，但卸下当前皮肤失败；可重试暂停或完全恢复。'
  }
}
