$script:AuroraSkinUtf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
$script:AuroraSkinLegacyAppearanceTheme = 'appearanceTheme = "light"'
$script:AuroraSkinManagedLightCodeTheme = 'appearanceLightCodeThemeId = "codex"'
$script:AuroraSkinManagedLightChromeTheme = 'appearanceLightChromeTheme = { accent = "#B65CFF", contrast = 64, fonts = { code = "Cascadia Code", ui = "Microsoft YaHei UI" }, ink = "#4A235F", opaqueWindows = true, semanticColors = { diffAdded = "#BCE8CF", diffRemoved = "#F7B8CE", skill = "#C47BFF" }, surface = "#FFF4FA" }'

function ConvertFrom-AuroraSkinUtf8Bytes {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
    [Parameter(Mandatory = $true)][string]$Path
  )

  try {
    $offset = if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { 3 } else { 0 }
    $content = $script:AuroraSkinUtf8NoBom.GetString($Bytes, $offset, $Bytes.Length - $offset)
    if ($content.IndexOf([char]0) -ge 0) {
      throw "Refusing to rewrite a config file containing NUL characters (possibly BOM-less UTF-16): $Path"
    }
    return $content
  } catch [System.Text.DecoderFallbackException] {
    throw "Refusing to rewrite a config file that is not valid UTF-8: $Path"
  }
}

function Test-AuroraSkinBytesEqual {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Left,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Right
  )
  if ($Left.Length -ne $Right.Length) { return $false }
  for ($index = 0; $index -lt $Left.Length; $index++) {
    if ($Left[$index] -ne $Right[$index]) { return $false }
  }
  return $true
}

function Assert-AuroraSkinFileUnchanged {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()][byte[]]$ExpectedBytes
  )
  if ($null -eq $ExpectedBytes) {
    if (Test-Path -LiteralPath $Path) { throw "File changed during the operation; retry without other writers: $Path" }
    return
  }
  if (-not (Test-Path -LiteralPath $Path)) { throw "File disappeared during the operation; retry: $Path" }
  $currentBytes = [System.IO.File]::ReadAllBytes($Path)
  if (-not (Test-AuroraSkinBytesEqual -Left $ExpectedBytes -Right $currentBytes)) {
    throw "File changed during the operation; retry without other writers: $Path"
  }
}

function Get-AuroraSkinNewLine {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
  if ($Content.Contains("`r`n")) { return "`r`n" }
  return "`n"
}

function Read-AuroraSkinUtf8File {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  return (ConvertFrom-AuroraSkinUtf8Bytes -Bytes $bytes -Path $Path)
}

function Write-AuroraSkinUtf8FileAtomically {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Content,

    [AllowNull()]
    [byte[]]$ExpectedBytes
  )

  $bytes = $script:AuroraSkinUtf8NoBom.GetBytes($Content)
  if ($PSBoundParameters.ContainsKey('ExpectedBytes')) {
    Write-AuroraSkinBytesAtomically -Path $Path -Bytes $bytes -ExpectedBytes $ExpectedBytes
  } else {
    Write-AuroraSkinBytesAtomically -Path $Path -Bytes $bytes
  }
}

function Remove-AuroraSkinAtomicArtifact {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([System.IO.File]::Exists($Path)) {
    [System.IO.File]::Delete($Path)
  }
}

function Write-AuroraSkinBytesAtomically {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
    [AllowNull()][byte[]]$ExpectedBytes
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $directory = [System.IO.Path]::GetDirectoryName($fullPath)
  if (-not [System.IO.Directory]::Exists($directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $fileName = [System.IO.Path]::GetFileName($fullPath)
  $operationId = "$PID.$([guid]::NewGuid().ToString('N'))"
  $temporary = Join-Path $directory ".$fileName.$operationId.tmp"
  $replacementBackup = Join-Path $directory ".$fileName.$operationId.replace-backup"

  try {
    [System.IO.File]::WriteAllBytes($temporary, $Bytes)
    if ($PSBoundParameters.ContainsKey('ExpectedBytes')) {
      Assert-AuroraSkinFileUnchanged -Path $fullPath -ExpectedBytes $ExpectedBytes
    }
    if ([System.IO.File]::Exists($fullPath)) {
      [System.IO.File]::Replace($temporary, $fullPath, $replacementBackup)
    } else {
      [System.IO.File]::Move($temporary, $fullPath)
    }
  } finally {
    foreach ($artifact in @($temporary, $replacementBackup)) {
      try {
        Remove-AuroraSkinAtomicArtifact -Path $artifact
      } catch {
        try {
          Write-Warning "Could not remove temporary atomic config artifact '$artifact': $($_.Exception.Message)"
        } catch {
          # Cleanup must never mask the result of the atomic write.
        }
      }
    }
  }
}

function Get-AuroraSkinTomlKeyTokenPattern {
  param([Parameter(Mandatory = $true)][string]$Key)
  $bare = [regex]::Escape($Key)
  $doubleQuoted = [regex]::Escape('"' + $Key + '"')
  $singleQuoted = [regex]::Escape("'" + $Key + "'")
  return "(?:$bare|$doubleQuoted|$singleQuoted)"
}

function ConvertTo-AuroraSkinTomlAsciiEscapeProbe {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $result = $Value
  $characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-'.ToCharArray()
  foreach ($character in $characters) {
    $code = ([int][char]$character).ToString('x2')
    $pattern = '(?i)\\(?:u00' + $code + '|U000000' + $code + ')'
    $result = [regex]::Replace($result, $pattern, [string]$character)
  }
  return $result
}

function Get-AuroraSkinTomlArrayBracketBalance {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

  $quote = $null
  $escaped = $false
  $balance = 0
  for ($index = 0; $index -lt $Line.Length; $index++) {
    $character = $Line[$index]
    if ($null -eq $quote) {
      if ($character -eq '#') { break }
      if ($character -eq '"' -or $character -eq "'") { $quote = $character }
      elseif ($character -eq '[') { $balance++ }
      elseif ($character -eq ']') { $balance-- }
      continue
    }
    if ($quote -eq '"') {
      if ($escaped) { $escaped = $false; continue }
      if ($character -eq '\') { $escaped = $true; continue }
    }
    if ($character -eq $quote) { $quote = $null }
  }
  return $balance
}

function Assert-AuroraSkinTomlLineEditingSafe {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

  if ($Content.Contains('"""') -or $Content.Contains("'''")) {
    throw 'Refusing to rewrite TOML containing multiline strings; use single-line values before installing Aurora Skin.'
  }
  foreach ($match in [regex]::Matches($Content, '(?m)^[^\r\n]*=[\t ]*\[[^\r\n]*\r?$')) {
    if ((Get-AuroraSkinTomlArrayBracketBalance -Line $match.Value) -ne 0) {
      throw 'Refusing to rewrite TOML containing multiline arrays; use single-line arrays before installing Aurora Skin.'
    }
  }

  $probe = ConvertTo-AuroraSkinTomlAsciiEscapeProbe -Value $Content
  if ($probe -cne $Content) {
    $desktopToken = Get-AuroraSkinTomlKeyTokenPattern -Key 'desktop'
    $desktopShape = "(?m)^[\t ]*(?:\[\[?[\t ]*$desktopToken[\t ]*(?:\]|\.)|$desktopToken[\t ]*(?:\.|=))"
    $rawDesktopShapes = [regex]::Matches($Content, $desktopShape).Count
    $probedDesktopShapes = [regex]::Matches($probe, $desktopShape).Count
    if ($probedDesktopShapes -gt $rawDesktopShapes) {
      throw 'Refusing to rewrite an escaped TOML key equivalent to desktop; normalize the key spelling first.'
    }
  }
}

function Get-AuroraSkinDesktopSectionPattern {
  $desktopToken = Get-AuroraSkinTomlKeyTokenPattern -Key 'desktop'
  return "(?ms)^[\t ]*\[[\t ]*$desktopToken[\t ]*\][\t ]*(?:#[^\r\n]*)?(?:\r?\n|(?=\z))(?<body>.*?)(?=^[\t ]*\[\[?|\z)"
}

function Test-AuroraSkinDesktopNestedTable {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
    [Parameter(Mandatory = $true)][string]$Key
  )

  $desktopToken = Get-AuroraSkinTomlKeyTokenPattern -Key 'desktop'
  $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $Key
  return [regex]::IsMatch(
    $Content,
    "(?m)^[\t ]*\[[\t ]*$desktopToken[\t ]*\.[\t ]*$keyToken[\t ]*(?:\]|\.)"
  )
}

function Assert-AuroraSkinDesktopShapeSupported {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

  Assert-AuroraSkinTomlLineEditingSafe -Content $Content
  $sectionPattern = Get-AuroraSkinDesktopSectionPattern
  if ([regex]::Matches($Content, $sectionPattern).Count -gt 1) {
    throw 'Refusing to rewrite multiple equivalent [desktop] tables.'
  }

  $desktopToken = Get-AuroraSkinTomlKeyTokenPattern -Key 'desktop'
  if ([regex]::IsMatch($Content, "(?m)^[\t ]*\[\[[\t ]*$desktopToken[\t ]*(?:\]\]|\.)")) {
    throw 'Refusing to rewrite a config that represents desktop as an array of tables.'
  }
  foreach ($key in @('appearanceTheme', 'appearanceLightCodeThemeId')) {
    if (Test-AuroraSkinDesktopNestedTable -Content $Content -Key $key) {
      throw "Refusing to replace '$key' because it is represented as a nested desktop table."
    }
  }

  $firstTable = [regex]::Match($Content, '(?m)^[\t ]*\[\[?')
  $rootContent = if ($firstTable.Success) { $Content.Substring(0, $firstTable.Index) } else { $Content }
  if ([regex]::IsMatch($rootContent, "(?m)^[\t ]*$desktopToken[\t ]*(?:\.|=)")) {
    throw 'Refusing to rewrite root dotted or inline desktop keys; normalize them to a [desktop] table first.'
  }

  $desktop = Get-AuroraSkinDesktopSection -Content $Content
  if ($null -ne $desktop) {
    $bodyProbe = ConvertTo-AuroraSkinTomlAsciiEscapeProbe -Value $desktop.Body
    foreach ($key in @('appearanceTheme', 'appearanceLightCodeThemeId', 'appearanceLightChromeTheme')) {
      $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $key
      $settingShape = "(?m)^[\t ]*$keyToken[\t ]*(?:\.|=)"
      if ($key -eq 'appearanceLightChromeTheme' -and
        (Test-AuroraSkinDesktopNestedTable -Content $Content -Key $key) -and
        [regex]::IsMatch($desktop.Body, $settingShape)) {
        throw "Refusing to rewrite '$key' because both a scalar and nested table are present."
      }
      if ([regex]::Matches($bodyProbe, $settingShape).Count -gt
        [regex]::Matches($desktop.Body, $settingShape).Count) {
        throw "Refusing to rewrite an escaped TOML key equivalent to '$key'."
      }
      if ([regex]::IsMatch($desktop.Body, "(?m)^[\t ]*$keyToken[\t ]*\.")) {
        throw "Refusing to replace dotted '$key' keys in the [desktop] table."
      }
    }
  }
}

function Get-AuroraSkinDesktopSection {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

  $match = [regex]::Match($Content, (Get-AuroraSkinDesktopSectionPattern))
  if (-not $match.Success) { return $null }
  return [pscustomobject]@{
    Body = $match.Groups['body'].Value
    BodyStart = $match.Groups['body'].Index
    BodyLength = $match.Groups['body'].Length
    SectionStart = $match.Index
    SectionLength = $match.Length
  }
}

function Add-AuroraSkinDesktopSection {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
    [Parameter(Mandatory = $true)][string]$NewLine
  )

  if ($Content.Length -eq 0) { return "[desktop]$NewLine" }
  $separator = if ($Content.EndsWith("`n")) { $NewLine } else { $NewLine + $NewLine }
  return $Content + $separator + "[desktop]$NewLine"
}

function Set-AuroraSkinSectionSetting {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Body,
    [Parameter(Mandatory = $true)][string]$Key,
    [AllowNull()][object]$Line,
    [Parameter(Mandatory = $true)][string]$NewLine
  )

  $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $Key
  $pattern = "(?m)^[\t ]*$keyToken[\t ]*=[^\r\n]*(?:\r?\n|(?=\z))"
  $matcher = [regex]::new($pattern)
  if ($matcher.Matches($Body).Count -gt 1) {
    throw "Refusing to rewrite duplicate '$Key' entries in the [desktop] section."
  }
  if ($null -eq $Line) { return $matcher.Replace($Body, '', 1) }
  $normalizedLine = $Line.TrimEnd("`r", "`n") + $NewLine
  if ($matcher.IsMatch($Body)) {
    $literalReplacement = $normalizedLine.Replace('$', '$$')
    return $matcher.Replace($Body, $literalReplacement, 1)
  }
  $separator = if ($Body.Length -eq 0 -or $Body.EndsWith("`n")) { '' } else { $NewLine }
  return $Body + $separator + $normalizedLine
}

function Get-AuroraSkinSectionSettingLine {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Body,
    [Parameter(Mandatory = $true)][string]$Key
  )
  $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $Key
  $matches = [regex]::Matches($Body, "(?m)^[\t ]*$keyToken[\t ]*=.*$")
  if ($matches.Count -gt 1) { throw "Refusing to inspect duplicate '$Key' entries in the [desktop] section." }
  if ($matches.Count -eq 0) { return $null }
  return $matches[0].Value.Trim()
}

function Test-AuroraSkinLegacyManagedLightTrio {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
  $desktop = Get-AuroraSkinDesktopSection -Content $Content
  if ($null -eq $desktop) { return $false }
  return (
    (Get-AuroraSkinSectionSettingLine -Body $desktop.Body -Key 'appearanceTheme') -ceq
      $script:AuroraSkinLegacyAppearanceTheme -and
    (Get-AuroraSkinSectionSettingLine -Body $desktop.Body -Key 'appearanceLightCodeThemeId') -ceq
      $script:AuroraSkinManagedLightCodeTheme -and
    (Get-AuroraSkinSectionSettingLine -Body $desktop.Body -Key 'appearanceLightChromeTheme') -ceq
      $script:AuroraSkinManagedLightChromeTheme
  )
}

function Get-AuroraSkinAppearanceMarkerPath {
  param([Parameter(Mandatory = $true)][string]$BackupPath)
  return "$BackupPath.appearance.json"
}

function Read-AuroraSkinAppearanceMarker {
  param([Parameter(Mandatory = $true)][string]$BackupPath)
  $markerPath = Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath
  if (-not (Test-Path -LiteralPath $markerPath)) { return $null }
  try {
    $marker = (Read-AuroraSkinUtf8File -Path $markerPath) | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Aurora Skin appearance marker is unreadable; config was preserved: $markerPath"
  }
  if ($null -eq $marker -or $marker -is [string] -or $marker -is [array]) {
    throw "Aurora Skin appearance marker is invalid; config was preserved: $markerPath"
  }
  $schemaVersion = 0
  try { $schemaVersion = [int]$marker.schemaVersion } catch { $schemaVersion = 0 }
  # v1 markers are always unmanaged; v2 markers may pin appearanceTheme.
  $validUnmanagedV1 = $schemaVersion -eq 1 -and $marker.appearanceThemeManaged -is [bool] -and
    -not [bool]$marker.appearanceThemeManaged
  $validV2 = $schemaVersion -eq 2 -and $marker.appearanceThemeManaged -is [bool]
  if (-not ($validUnmanagedV1 -or $validV2)) {
    throw "Aurora Skin appearance marker is invalid; config was preserved: $markerPath"
  }
  return $marker
}

function Write-AuroraSkinAppearanceMarker {
  param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [bool]$Managed = $false
  )
  $markerPath = Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath
  if (Get-Command Assert-AuroraSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-AuroraSkinNoReparseComponents -Path $markerPath
  }
  # Unmanaged markers keep the v1 shape older engines accept; managed pins use
  # schemaVersion 2, which older engines conservatively refuse to act on.
  $schemaVersion = 1
  if ($Managed) { $schemaVersion = 2 }
  $marker = [ordered]@{
    schemaVersion = $schemaVersion
    appearanceThemeManaged = $Managed
  } | ConvertTo-Json
  Write-AuroraSkinUtf8FileAtomically -Path $markerPath -Content ($marker + "`r`n")
}

function Install-AuroraSkinBaseTheme {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$BackupPath,

    [ValidateSet('auto', 'light', 'dark')]
    [string]$AppearanceTheme = 'auto'
  )

  if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Codex config not found: $ConfigPath" }
  if (Get-Command Assert-AuroraSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-AuroraSkinNoReparseComponents -Path $BackupPath
    Assert-AuroraSkinNoReparseComponents -Path (Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath)
  }
  $originalBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
  $content = ConvertFrom-AuroraSkinUtf8Bytes -Bytes $originalBytes -Path $ConfigPath
  $appearanceMarker = Read-AuroraSkinAppearanceMarker -BackupPath $BackupPath
  $appearanceMarkerPath = Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath
  $appearanceMarkerExisted = Test-Path -LiteralPath $appearanceMarkerPath -PathType Leaf
  $backupCreated = $false
  if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-AuroraSkinBytesAtomically -Path $BackupPath -Bytes $originalBytes -ExpectedBytes $null
    $backupCreated = $true
  }

  $writeCompleted = $false
  try {
    Assert-AuroraSkinDesktopShapeSupported -Content $content
    $newLine = Get-AuroraSkinNewLine -Content $content
    $desktop = Get-AuroraSkinDesktopSection -Content $content
    if ($null -eq $desktop) {
      $content = Add-AuroraSkinDesktopSection -Content $content -NewLine $newLine
      $desktop = Get-AuroraSkinDesktopSection -Content $content
    }

    $body = $desktop.Body
    $backupContent = $null
    $pinnedAppearance = $AppearanceTheme -ne 'auto'
    $managedByMarker = $null -ne $appearanceMarker -and [bool]$appearanceMarker.appearanceThemeManaged
    $legacyMigration = $null -eq $appearanceMarker -and (Test-Path -LiteralPath $BackupPath) -and
      (Test-AuroraSkinLegacyManagedLightTrio -Content $content)
    # Put the pre-install appearanceTheme back whenever we stop managing it:
    # either migrating away from the legacy forced-light trio, or un-pinning
    # after a fixed-appearance theme is replaced by an auto one.
    if (-not $pinnedAppearance -and ($legacyMigration -or $managedByMarker)) {
      $backupContent = ConvertFrom-AuroraSkinUtf8Bytes -Bytes ([System.IO.File]::ReadAllBytes($BackupPath)) -Path $BackupPath
      Assert-AuroraSkinDesktopShapeSupported -Content $backupContent
      $backupDesktop = Get-AuroraSkinDesktopSection -Content $backupContent
      $savedAppearance = if ($null -ne $backupDesktop) {
        Get-AuroraSkinSectionSettingLine -Body $backupDesktop.Body -Key 'appearanceTheme'
      } else { $null }
      $body = Set-AuroraSkinSectionSetting -Body $body -Key 'appearanceTheme' -Line $savedAppearance -NewLine $newLine
    }
    if ($pinnedAppearance) {
      # Native token surfaces (dropdowns/popovers) follow appearanceTheme, so a
      # fixed-appearance theme pins it to match; Restore puts the original back.
      $body = Set-AuroraSkinSectionSetting -Body $body -Key 'appearanceTheme' `
        -Line ('appearanceTheme = "{0}"' -f $AppearanceTheme) -NewLine $newLine
    }
    $settings = [ordered]@{
      appearanceLightCodeThemeId = $script:AuroraSkinManagedLightCodeTheme
      appearanceLightChromeTheme = $script:AuroraSkinManagedLightChromeTheme
    }
    $hasNestedLightChromeTheme = Test-AuroraSkinDesktopNestedTable `
      -Content $content -Key 'appearanceLightChromeTheme'
    foreach ($key in $settings.Keys) {
      if ($key -eq 'appearanceLightChromeTheme' -and $hasNestedLightChromeTheme) { continue }
      $body = Set-AuroraSkinSectionSetting -Body $body -Key $key -Line $settings[$key] -NewLine $newLine
    }

    $content = $content.Substring(0, $desktop.BodyStart) + $body +
      $content.Substring($desktop.BodyStart + $desktop.BodyLength)
    # Commit the metadata first. A config commit must never exist without the
    # marker that tells restore exactly which appearance keys we own.
    Write-AuroraSkinAppearanceMarker -BackupPath $BackupPath -Managed $pinnedAppearance
    Write-AuroraSkinUtf8FileAtomically -Path $ConfigPath -Content $content -ExpectedBytes $originalBytes
    $writeCompleted = $true
  } catch {
    if (-not $writeCompleted) {
      $configUnchanged = $false
      try {
        $configUnchanged = (Test-Path -LiteralPath $ConfigPath -PathType Leaf) -and
          (Test-AuroraSkinBytesEqual -Left $originalBytes -Right ([System.IO.File]::ReadAllBytes($ConfigPath)))
      } catch {
        $configUnchanged = $false
      }
      if ($configUnchanged) {
        $markerCleanupSucceeded = $true
        if (-not $appearanceMarkerExisted -and (Test-Path -LiteralPath $appearanceMarkerPath)) {
          try {
            Remove-Item -LiteralPath $appearanceMarkerPath -Force -ErrorAction Stop
          } catch {
            $markerCleanupSucceeded = $false
          }
        }
        if ($markerCleanupSucceeded -and $backupCreated) {
          Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
      }
    }
    throw
  }
}

function Restore-AuroraSkinBaseTheme {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$BackupPath
  )

  if (-not (Test-Path -LiteralPath $BackupPath)) { throw 'No pre-install config backup is available.' }
  if (Get-Command Assert-AuroraSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-AuroraSkinNoReparseComponents -Path $BackupPath
    Assert-AuroraSkinNoReparseComponents -Path (Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath)
  }
  $backupBytes = [System.IO.File]::ReadAllBytes($BackupPath)
  $backupContent = ConvertFrom-AuroraSkinUtf8Bytes -Bytes $backupBytes -Path $BackupPath
  $currentBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
  $currentContent = ConvertFrom-AuroraSkinUtf8Bytes -Bytes $currentBytes -Path $ConfigPath
  Assert-AuroraSkinDesktopShapeSupported -Content $backupContent
  Assert-AuroraSkinDesktopShapeSupported -Content $currentContent
  $newLine = Get-AuroraSkinNewLine -Content $currentContent
  $backupDesktop = Get-AuroraSkinDesktopSection -Content $backupContent
  $currentDesktop = Get-AuroraSkinDesktopSection -Content $currentContent
  if ($null -eq $currentDesktop) {
    $currentContent = Add-AuroraSkinDesktopSection -Content $currentContent -NewLine $newLine
    $currentDesktop = Get-AuroraSkinDesktopSection -Content $currentContent
  }

  $body = $currentDesktop.Body
  $appearanceMarker = Read-AuroraSkinAppearanceMarker -BackupPath $BackupPath
  $restoreLegacyAppearance = $null -eq $appearanceMarker -and
    (Test-AuroraSkinLegacyManagedLightTrio -Content $currentContent)
  $restoreManagedAppearance = $null -ne $appearanceMarker -and
    [bool]$appearanceMarker.appearanceThemeManaged
  $restoreKeys = @('appearanceLightCodeThemeId', 'appearanceLightChromeTheme')
  if ($restoreLegacyAppearance -or $restoreManagedAppearance) {
    $restoreKeys = @('appearanceTheme') + $restoreKeys
  }
  $hasNestedLightChromeTheme = Test-AuroraSkinDesktopNestedTable `
    -Content $currentContent -Key 'appearanceLightChromeTheme'
  foreach ($key in $restoreKeys) {
    if ($key -eq 'appearanceLightChromeTheme' -and $hasNestedLightChromeTheme) { continue }
    $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $key
    $pattern = "(?m)^[\t ]*$keyToken[\t ]*=[^\r\n]*(?:\r?\n|(?=\z))"
    $saved = if ($null -ne $backupDesktop) { [regex]::Match($backupDesktop.Body, $pattern) } else { $null }
    $line = if ($null -ne $saved -and $saved.Success) { $saved.Value } else { $null }
    $body = Set-AuroraSkinSectionSetting -Body $body -Key $key -Line $line -NewLine $newLine
  }
  if ($null -eq $backupDesktop -and [string]::IsNullOrWhiteSpace($body)) {
    $currentContent = $currentContent.Remove($currentDesktop.SectionStart, $currentDesktop.SectionLength)
  } else {
    $currentContent = $currentContent.Substring(0, $currentDesktop.BodyStart) + $body +
      $currentContent.Substring($currentDesktop.BodyStart + $currentDesktop.BodyLength)
  }
  Write-AuroraSkinUtf8FileAtomically -Path $ConfigPath -Content $currentContent -ExpectedBytes $currentBytes
}

function Restore-AuroraSkinConfigBackup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$RecoveryBackupPath
  )

  if (-not (Test-Path -LiteralPath $BackupPath)) { throw 'No pre-install config backup is available.' }
  $backupBytes = [System.IO.File]::ReadAllBytes($BackupPath)
  $null = ConvertFrom-AuroraSkinUtf8Bytes -Bytes $backupBytes -Path $BackupPath
  $currentBytes = $null
  if (Test-Path -LiteralPath $ConfigPath) {
    $currentBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
    Write-AuroraSkinBytesAtomically -Path $RecoveryBackupPath -Bytes $currentBytes -ExpectedBytes $null
  }

  Write-AuroraSkinBytesAtomically -Path $ConfigPath -Bytes $backupBytes -ExpectedBytes $currentBytes
}

function Archive-AuroraSkinConfigBackup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$ArchivePath
  )

  if (-not (Test-Path -LiteralPath $BackupPath)) { return }
  if (Test-Path -LiteralPath $ArchivePath) { throw "Config backup archive already exists: $ArchivePath" }
  Move-Item -LiteralPath $BackupPath -Destination $ArchivePath -ErrorAction Stop
  Remove-Item -LiteralPath (Get-AuroraSkinAppearanceMarkerPath -BackupPath $BackupPath) -Force -ErrorAction SilentlyContinue
}

function Move-AuroraSkinLegacyConfigToOfficialDefaults {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$ArchivePath
  )

  if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { return $false }
  if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Archive-AuroraSkinConfigBackup -BackupPath $BackupPath -ArchivePath $ArchivePath
    return $false
  }

  $currentBytes = [System.IO.File]::ReadAllBytes($ConfigPath)
  $currentContent = ConvertFrom-AuroraSkinUtf8Bytes -Bytes $currentBytes -Path $ConfigPath
  $backupContent = Read-AuroraSkinUtf8File -Path $BackupPath
  Assert-AuroraSkinDesktopShapeSupported -Content $currentContent
  Assert-AuroraSkinDesktopShapeSupported -Content $backupContent
  $currentDesktop = Get-AuroraSkinDesktopSection -Content $currentContent
  $backupDesktop = Get-AuroraSkinDesktopSection -Content $backupContent
  $changed = $false

  if ($null -ne $currentDesktop) {
    $newLine = Get-AuroraSkinNewLine -Content $currentContent
    $body = $currentDesktop.Body
    $managedValues = [ordered]@{
      appearanceTheme = $script:AuroraSkinLegacyAppearanceTheme
      appearanceLightCodeThemeId = $script:AuroraSkinManagedLightCodeTheme
      appearanceLightChromeTheme = $script:AuroraSkinManagedLightChromeTheme
    }
    foreach ($entry in $managedValues.GetEnumerator()) {
      $keyToken = Get-AuroraSkinTomlKeyTokenPattern -Key $entry.Key
      $pattern = "(?m)^[\t ]*$keyToken[\t ]*=[^\r\n]*(?:\r?\n|(?=\z))"
      $currentMatch = [regex]::Match($body, $pattern)
      if (-not $currentMatch.Success -or
        $currentMatch.Value.Trim() -cne "$($entry.Value)".Trim()) {
        # Preserve user-modified values; migrate only exact legacy-managed assignments.
        continue
      }
      $saved = if ($null -ne $backupDesktop) {
        [regex]::Match($backupDesktop.Body, $pattern)
      } else { $null }
      $savedLine = if ($null -ne $saved -and $saved.Success) { $saved.Value } else { $null }
      $body = Set-AuroraSkinSectionSetting -Body $body -Key $entry.Key -Line $savedLine -NewLine $newLine
      $changed = $true
    }
    if ($changed) {
      $updated = $currentContent.Substring(0, $currentDesktop.BodyStart) + $body +
        $currentContent.Substring($currentDesktop.BodyStart + $currentDesktop.BodyLength)
      Write-AuroraSkinUtf8FileAtomically -Path $ConfigPath -Content $updated -ExpectedBytes $currentBytes
    }
  }

  Archive-AuroraSkinConfigBackup -BackupPath $BackupPath -ArchivePath $ArchivePath
  return $changed
}
