[CmdletBinding()]
param([switch]$EngineOnly)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'scripts\common-windows.ps1')
. (Join-Path $Root 'scripts\theme-windows.ps1')

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-aurora-skin-tests-$PID-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
  $runtimeSourceName = 'runtime source ' + (-join @([char]0x6D4B, [char]0x8BD5))
  $runtimeSourceRoot = Join-Path $temporaryRoot $runtimeSourceName
  $runtimeStateRoot = Join-Path $temporaryRoot 'runtime-state'
  New-Item -ItemType Directory -Path $runtimeSourceRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root 'VERSION') -Destination $runtimeSourceRoot -Force
  foreach ($directoryName in @('assets', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $Root $directoryName) -Destination $runtimeSourceRoot `
      -Recurse -Force -ErrorAction Stop
  }
  $repositoryRoot = Split-Path -Parent $Root
  foreach ($directoryName in @('library', 'manager')) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $directoryName) -Destination $runtimeSourceRoot `
      -Recurse -Force -ErrorAction Stop
  }
  $runtimeNodeDirectory = Join-Path $runtimeSourceRoot 'runtime\node'
  New-Item -ItemType Directory -Path $runtimeNodeDirectory -Force | Out-Null
  $pathNode = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $pathNode) { $pathNode = Get-Command node -ErrorAction Stop }
  Copy-Item -LiteralPath $pathNode.Source -Destination (Join-Path $runtimeNodeDirectory 'node.exe') -Force
  [System.IO.File]::WriteAllText(
    (Join-Path $runtimeNodeDirectory 'LICENSE'),
    'Node.js runtime license fixture',
    [System.Text.UTF8Encoding]::new($false)
  )
  $zoneMarkedSourceScript = Join-Path $runtimeSourceRoot 'scripts\start-aurora-skin.ps1'
  Set-Content -LiteralPath $zoneMarkedSourceScript -Stream 'Zone.Identifier' `
    -Value "[ZoneTransfer]`r`nZoneId=3`r`n" -Encoding Ascii
  if (@(Get-Item -LiteralPath $zoneMarkedSourceScript -Stream 'Zone.Identifier').Count -ne 1) {
    throw 'Runtime test could not create an Internet-zone marker on its source fixture.'
  }

  $engine = Install-AuroraSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $runtimeStateRoot
  $sourcePrefix = $runtimeSourceRoot.TrimEnd('\') + '\'
  $runtimeSourceFiles = @((Get-Item -LiteralPath (Join-Path $runtimeSourceRoot 'VERSION'))) + @(
    Get-ChildItem -LiteralPath (Join-Path $runtimeSourceRoot 'assets'), `
      (Join-Path $runtimeSourceRoot 'scripts'), (Join-Path $runtimeSourceRoot 'library'), `
      (Join-Path $runtimeSourceRoot 'manager'), `
      (Join-Path $runtimeSourceRoot 'runtime') `
      -Recurse -File -Force
  )
  $runtimeEngineFiles = @((Get-Item -LiteralPath $engine.Version)) + @(
    Get-ChildItem -LiteralPath (Join-Path $engine.Root 'assets'), `
      (Join-Path $engine.Root 'scripts'), (Join-Path $engine.Root 'library'), `
      (Join-Path $engine.Root 'manager'), `
      (Join-Path $engine.Root 'runtime') `
      -Recurse -File -Force
  )
  if ($runtimeSourceFiles.Count -ne $runtimeEngineFiles.Count -or
    -not (Test-AuroraSkinPathWithin -Path $engine.Start -Root $runtimeStateRoot) -or
    -not (Test-AuroraSkinPathWithin -Path $engine.Restore -Root $runtimeStateRoot) -or
    -not (Test-AuroraSkinPathWithin -Path $engine.LaunchManager -Root $runtimeStateRoot) -or
    -not (Test-Path -LiteralPath (Join-Path $engine.Runtime 'node\node.exe') -PathType Leaf)) {
    throw 'Installed runtime paths are incomplete or still point outside the managed state root.'
  }
  foreach ($sourceFile in $runtimeSourceFiles) {
    $relative = $sourceFile.FullName.Substring($sourcePrefix.Length)
    $installedFile = Join-Path $engine.Root $relative
    if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile.FullName).Hash -cne
      (Get-FileHash -Algorithm SHA256 -LiteralPath $installedFile).Hash) {
      throw "Installed runtime hash does not match its source: $relative"
    }
  }
  if (@(Get-Item -LiteralPath $engine.Start -Stream 'Zone.Identifier' `
    -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Installed runtime retained an Internet-zone marker and cannot use RemoteSigned safely.'
  }

  [System.IO.File]::WriteAllText((Join-Path $engine.Root 'stale-runtime.txt'), 'stale')
  [System.IO.File]::WriteAllText((Join-Path $runtimeSourceRoot 'scripts\runtime-update.test'), 'updated')
  $realRuntimeCleanup = (Get-Command Remove-AuroraSkinRuntimeTree -CommandType Function).ScriptBlock
  $previousWarningPreference = $WarningPreference
  $runtimeCleanupFailure = @{ Triggered = $false }
  try {
    $WarningPreference = 'Stop'
    function Remove-AuroraSkinRuntimeTree {
      param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StateRoot
      )
      if ([System.IO.Path]::GetFileName($Path) -like '.engine-backup-*') {
        $runtimeCleanupFailure.Triggered = $true
        throw 'forced runtime backup cleanup failure'
      }
      & $realRuntimeCleanup -Path $Path -StateRoot $StateRoot
    }

    $runtimeUpdateReportedFailure = $false
    try {
      $engine = Install-AuroraSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $runtimeStateRoot
    } catch {
      $runtimeUpdateReportedFailure = $true
    }
    if (-not $runtimeCleanupFailure.Triggered -or $runtimeUpdateReportedFailure -or
      (Test-Path -LiteralPath (Join-Path $engine.Root 'stale-runtime.txt')) -or
      (Read-AuroraSkinUtf8File -Path (Join-Path $engine.Root 'scripts\runtime-update.test')) -cne 'updated') {
      throw 'Runtime reinstall did not commit cleanly when old-engine cleanup failed.'
    }
  } finally {
    $WarningPreference = $previousWarningPreference
    Set-Item -Path Function:\Remove-AuroraSkinRuntimeTree -Value $realRuntimeCleanup
  }
  foreach ($runtimeBackup in Get-ChildItem -LiteralPath $runtimeStateRoot -Directory -Force |
    Where-Object { $_.Name -like '.engine-backup-*' }) {
    Remove-AuroraSkinRuntimeTree -Path $runtimeBackup.FullName -StateRoot $runtimeStateRoot
  }

  $missingBundledNodeRoot = Join-Path $temporaryRoot 'missing-bundled-node-source'
  Copy-Item -LiteralPath $runtimeSourceRoot -Destination $missingBundledNodeRoot -Recurse -Force
  Remove-Item -LiteralPath (Join-Path $missingBundledNodeRoot 'runtime\node\LICENSE') -Force
  $engineSentinelHash = (Get-FileHash -Algorithm SHA256 `
    -LiteralPath (Join-Path $engine.Root 'scripts\runtime-update.test')).Hash
  $missingBundledNodeRejected = $false
  try {
    $null = Install-AuroraSkinRuntimeEngine -SkillRoot $missingBundledNodeRoot `
      -StateRoot $runtimeStateRoot
  } catch {
    $missingBundledNodeRejected = $true
  }
  if (-not $missingBundledNodeRejected -or
    (Get-FileHash -Algorithm SHA256 `
      -LiteralPath (Join-Path $engine.Root 'scripts\runtime-update.test')).Hash -cne $engineSentinelHash) {
    throw 'An incomplete bundled Node runtime replaced the previously valid managed engine.'
  }

  $invalidRuntimeRoot = Join-Path $temporaryRoot 'invalid-runtime-source'
  New-Item -ItemType Directory -Path $invalidRuntimeRoot | Out-Null
  foreach ($directoryName in @('assets', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $runtimeSourceRoot $directoryName) -Destination $invalidRuntimeRoot `
      -Recurse -Force -ErrorAction Stop
  }
  Remove-Item -LiteralPath (Join-Path $invalidRuntimeRoot 'scripts\start-aurora-skin.ps1') -Force
  $invalidRuntimeRejected = $false
  try {
    $null = Install-AuroraSkinRuntimeEngine -SkillRoot $invalidRuntimeRoot -StateRoot $runtimeStateRoot
  } catch {
    $invalidRuntimeRejected = $true
  }
  if (-not $invalidRuntimeRejected -or
    -not (Test-Path -LiteralPath $engine.Start -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $engine.Root 'scripts\runtime-update.test') -PathType Leaf) -or
    @(Get-ChildItem -LiteralPath $runtimeStateRoot -Force | Where-Object {
      $_.Name -like '.engine-staging-*' -or $_.Name -like '.engine-backup-*'
    }).Count -ne 0) {
    throw 'An invalid runtime source changed the installed engine or left transaction artifacts.'
  }

  $nestedStateRoot = Join-Path $runtimeSourceRoot 'scripts\nested-state'
  $nestedStateRejected = $false
  try {
    $null = Install-AuroraSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $nestedStateRoot
  } catch {
    $nestedStateRejected = $true
  }
  if (-not $nestedStateRejected -or (Test-Path -LiteralPath $nestedStateRoot)) {
    throw 'Runtime install allowed its state root to recurse into the copied source tree.'
  }

  $installSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\install-aurora-skin.ps1')
  $commonSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\common-windows.ps1')
  $hashVerificationIndex = $commonSource.IndexOf(
    'Staged Aurora Skin runtime failed hash verification', [System.StringComparison]::Ordinal
  )
  $unblockIndex = $commonSource.IndexOf(
    'Unblock-File -LiteralPath $runtimeScript.FullName', [System.StringComparison]::Ordinal
  )
  if ($hashVerificationIndex -lt 0 -or $unblockIndex -le $hashVerificationIndex) {
    throw 'Runtime scripts are not unblocked only after staged byte-content verification.'
  }
  foreach ($requiredNodeBehavior in @(
    '$env:CODEX_AURORA_SKIN_NODE',
    'runtime\node\node.exe',
    'runtime\node\LICENSE',
    '$sourceHasBundledRuntime',
    'Get-AuroraSkinValidatedNodeRuntime'
  )) {
    if (-not $commonSource.Contains($requiredNodeBehavior)) {
      throw "Bundled Node.js discovery is missing: $requiredNodeBehavior"
    }
  }
  $engineInstallIndex = $installSource.IndexOf('$engine = Install-AuroraSkinRuntimeEngine', [System.StringComparison]::Ordinal)
  if ($engineInstallIndex -lt 0) {
    throw 'Installer does not install the managed runtime engine.'
  }
  foreach ($requiredShortcutBinding in @(
    '$startScript = $engine.LaunchManager',
    '$restoreScript = $engine.Restore',
    '$shortcut.WorkingDirectory = $engine.Root',
    '$restore.WorkingDirectory = $engine.Root'
  )) {
    if (-not $installSource.Contains($requiredShortcutBinding)) {
      throw "Installer shortcut still depends on its source checkout: $requiredShortcutBinding"
    }
  }
  if ([regex]::Matches($installSource, '-ExecutionPolicy RemoteSigned').Count -lt 2 -or
    $installSource.Contains('-ExecutionPolicy Bypass')) {
    throw 'Installer shortcuts bypass the PowerShell execution policy.'
  }

  Remove-Item -LiteralPath $runtimeSourceRoot -Recurse -Force
  foreach ($installedScript in Get-ChildItem -LiteralPath $engine.Scripts -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      $installedScript.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) {
      throw "Installed runtime script failed to parse after its source checkout was removed: $($installedScript.Name)"
    }
  }
  if (-not (Test-Path -LiteralPath $engine.Start -PathType Leaf) -or
    -not (Test-Path -LiteralPath $engine.Restore -PathType Leaf) -or
    -not (Test-Path -LiteralPath $engine.LaunchManager -PathType Leaf)) {
    throw 'Installed manager, launch, or restore entry point disappeared with the source checkout.'
  }
  Remove-Item -LiteralPath $invalidRuntimeRoot, $runtimeStateRoot -Recurse -Force

  if ($EngineOnly) {
    Write-Host 'PASS: managed runtime staging, replacement, invalid-source guard, and source-independent shortcuts.'
    return
  }

  $atomicTestRoot = Join-Path $temporaryRoot 'atomic-writer'
  New-Item -ItemType Directory -Path $atomicTestRoot | Out-Null
  $atomicReplacePath = Join-Path $atomicTestRoot 'atomic-replace.txt'
  [System.IO.File]::WriteAllText($atomicReplacePath, 'before')
  Write-AuroraSkinUtf8FileAtomically -Path $atomicReplacePath -Content 'after'
  if ((Read-AuroraSkinUtf8File -Path $atomicReplacePath) -cne 'after') {
    throw 'Atomic writer did not replace an existing file under Windows PowerShell.'
  }
  $atomicArtifacts = @(Get-ChildItem -LiteralPath $atomicTestRoot -Force |
    Where-Object { $_.FullName -ne $atomicReplacePath })
  if ($atomicArtifacts.Count -ne 0) {
    throw 'Atomic writer left internal replacement artifacts behind.'
  }
  Remove-Item -LiteralPath $atomicReplacePath -Force
  Remove-Item -LiteralPath $atomicTestRoot -Force

  $realAtomicCleanup = (Get-Command Remove-AuroraSkinAtomicArtifact -CommandType Function).ScriptBlock
  $previousWarningPreference = $WarningPreference
  $cleanupFailure = @{ Triggered = $false }
  try {
    $WarningPreference = 'Stop'
    function Remove-AuroraSkinAtomicArtifact {
      param([Parameter(Mandatory = $true)][string]$Path)
      if ($Path -like '*.replace-backup') {
        $cleanupFailure.Triggered = $true
        throw 'forced atomic replacement-backup cleanup failure'
      }
      if ([System.IO.File]::Exists($Path)) {
        [System.IO.File]::Delete($Path)
      }
    }

    $cleanupFailurePath = Join-Path $temporaryRoot 'atomic-cleanup-failure.txt'
    [System.IO.File]::WriteAllText($cleanupFailurePath, 'before')
    $cleanupFailureReported = $false
    try {
      Write-AuroraSkinUtf8FileAtomically -Path $cleanupFailurePath -Content 'after'
    } catch {
      $cleanupFailureReported = $true
    }
    if (-not $cleanupFailure.Triggered -or $cleanupFailureReported -or
      (Read-AuroraSkinUtf8File -Path $cleanupFailurePath) -cne 'after') {
      throw 'A committed atomic write was reported as failed when cleanup failed.'
    }

    $cleanupConfigPath = Join-Path $temporaryRoot 'cleanup-failure-config.toml'
    $cleanupBackupPath = Join-Path $temporaryRoot 'cleanup-failure-config.before.toml'
    $cleanupOriginal = "model = `"gpt-5`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`n"
    [System.IO.File]::WriteAllText(
      $cleanupConfigPath,
      $cleanupOriginal,
      [System.Text.UTF8Encoding]::new($false, $true)
    )
    $cleanupOriginalBytes = [System.IO.File]::ReadAllBytes($cleanupConfigPath)
    Install-AuroraSkinBaseTheme -ConfigPath $cleanupConfigPath -BackupPath $cleanupBackupPath
    if (-not (Test-Path -LiteralPath $cleanupBackupPath) -or
      -not (Test-AuroraSkinBytesEqual -Left $cleanupOriginalBytes `
        -Right ([System.IO.File]::ReadAllBytes($cleanupBackupPath)))) {
      throw 'Atomic cleanup failure removed or changed the durable pre-install config backup.'
    }
  } finally {
    $WarningPreference = $previousWarningPreference
    Set-Item -Path Function:\Remove-AuroraSkinAtomicArtifact -Value $realAtomicCleanup
  }

  $realAppearanceMarkerWriter = (Get-Command Write-AuroraSkinAppearanceMarker -CommandType Function).ScriptBlock
  try {
    function Write-AuroraSkinAppearanceMarker {
      param([Parameter(Mandatory = $true)][string]$BackupPath)
      throw 'forced appearance-marker write failure'
    }
    $markerFailureConfig = Join-Path $temporaryRoot 'marker-failure-config.toml'
    $markerFailureBackup = Join-Path $temporaryRoot 'marker-failure-config.before.toml'
    $markerFailureOriginal = "model = `"gpt-5`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`n"
    [System.IO.File]::WriteAllText(
      $markerFailureConfig,
      $markerFailureOriginal,
      [System.Text.UTF8Encoding]::new($false, $true)
    )
    $markerFailureBytes = [System.IO.File]::ReadAllBytes($markerFailureConfig)
    $markerFailureRejected = $false
    try {
      Install-AuroraSkinBaseTheme -ConfigPath $markerFailureConfig -BackupPath $markerFailureBackup
    } catch {
      $markerFailureRejected = $true
    }
    if (-not $markerFailureRejected -or
      -not (Test-AuroraSkinBytesEqual -Left $markerFailureBytes `
        -Right ([System.IO.File]::ReadAllBytes($markerFailureConfig))) -or
      (Test-Path -LiteralPath $markerFailureBackup) -or
      (Test-Path -LiteralPath (Get-AuroraSkinAppearanceMarkerPath -BackupPath $markerFailureBackup))) {
      throw 'Appearance-marker failure changed config or discarded transaction consistency.'
    }
  } finally {
    Set-Item -Path Function:\Write-AuroraSkinAppearanceMarker -Value $realAppearanceMarkerWriter
  }

  # A legacy upgrade can already have a durable backup but no appearance
  # marker. If the marker commits and the config commit then fails, the marker
  # must still be removed so restore continues to recognize the legacy light
  # trio and recovers the saved appearanceTheme.
  $realAtomicBytesWriter = (Get-Command Write-AuroraSkinBytesAtomically -CommandType Function).ScriptBlock
  $legacyCommitFailureConfig = Join-Path $temporaryRoot 'legacy-commit-failure.toml'
  $legacyCommitFailureBackup = Join-Path $temporaryRoot 'legacy-commit-failure.before.toml'
  $legacyOriginal = "model = `"gpt-5`"`r`n`r`n[desktop]`r`n$($script:AuroraSkinLegacyAppearanceTheme)`r`n$($script:AuroraSkinManagedLightCodeTheme)`r`n$($script:AuroraSkinManagedLightChromeTheme)`r`n"
  $legacyBackup = "model = `"gpt-5`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`n"
  [System.IO.File]::WriteAllText(
    $legacyCommitFailureConfig,
    $legacyOriginal,
    [System.Text.UTF8Encoding]::new($false, $true)
  )
  [System.IO.File]::WriteAllText(
    $legacyCommitFailureBackup,
    $legacyBackup,
    [System.Text.UTF8Encoding]::new($false, $true)
  )
  $legacyOriginalBytes = [System.IO.File]::ReadAllBytes($legacyCommitFailureConfig)
  $legacyBackupBytes = [System.IO.File]::ReadAllBytes($legacyCommitFailureBackup)
  $legacyCommitFailureRejected = $false
  try {
    function Write-AuroraSkinBytesAtomically {
      param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [AllowNull()][byte[]]$ExpectedBytes
      )
      if ([System.IO.Path]::GetFullPath($Path) -ieq
        [System.IO.Path]::GetFullPath($legacyCommitFailureConfig)) {
        throw 'forced config commit failure after marker write'
      }
      & $realAtomicBytesWriter @PSBoundParameters
    }
    try {
      Install-AuroraSkinBaseTheme -ConfigPath $legacyCommitFailureConfig `
        -BackupPath $legacyCommitFailureBackup
    } catch {
      $legacyCommitFailureRejected = $true
    }
  } finally {
    Set-Item -Path Function:\Write-AuroraSkinBytesAtomically -Value $realAtomicBytesWriter
  }
  if (-not $legacyCommitFailureRejected -or
    -not (Test-AuroraSkinBytesEqual -Left $legacyOriginalBytes `
      -Right ([System.IO.File]::ReadAllBytes($legacyCommitFailureConfig))) -or
    -not (Test-AuroraSkinBytesEqual -Left $legacyBackupBytes `
      -Right ([System.IO.File]::ReadAllBytes($legacyCommitFailureBackup))) -or
    (Test-Path -LiteralPath (Get-AuroraSkinAppearanceMarkerPath -BackupPath $legacyCommitFailureBackup))) {
    throw 'Legacy config commit failure left an appearance marker or changed the recoverable backup.'
  }
  Restore-AuroraSkinBaseTheme -ConfigPath $legacyCommitFailureConfig `
    -BackupPath $legacyCommitFailureBackup
  if ((Read-AuroraSkinUtf8File -Path $legacyCommitFailureConfig) -notmatch 'appearanceTheme = "system"') {
    throw 'Legacy restore did not recover appearanceTheme after marker cleanup.'
  }

  $configPath = Join-Path $temporaryRoot 'config.toml'
  $backupPath = Join-Path $temporaryRoot 'config.before-aurora-skin.toml'
  $projectName = -join @([char]0x4EE3, [char]0x7801, [char]0x9879, [char]0x76EE, [char]0x7532)
  $laterValue = -join @([char]0x4FDD, [char]0x7559)
  $sample = "model = `"gpt-5`"`r`n`r`n[other]`r`nappearanceTheme = `"keep-other`"`r`n`r`n[projects.'C:\$projectName']`r`ntrust_level = `"trusted`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-`$special`"`r`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
  [System.IO.File]::WriteAllText($configPath, $sample, $utf8NoBom)
  $originalBytes = [System.IO.File]::ReadAllBytes($configPath)

  Install-AuroraSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $installed = Read-AuroraSkinUtf8File -Path $configPath
  if (-not $installed.Contains($projectName) -or $installed -notmatch 'appearanceTheme = "system"' -or
    $installed -notmatch 'appearanceLightCodeThemeId = "codex"') {
    throw 'Install changed a non-ASCII project name or failed to preserve the native appearance.'
  }
  if (-not (Test-Path -LiteralPath (Get-AuroraSkinAppearanceMarkerPath -BackupPath $backupPath))) {
    throw 'Install did not record the appearance-preservation marker.'
  }
  $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
  if ([Convert]::ToBase64String($backupBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Install did not preserve an exact pre-change config backup.'
  }

  $written = [System.IO.File]::ReadAllBytes($configPath)
  if ($written.Length -ge 3 -and $written[0] -eq 0xEF -and $written[1] -eq 0xBB -and $written[2] -eq 0xBF) {
    throw 'Config writer added an unexpected UTF-8 BOM.'
  }

  $installed += "afterInstall = `"$laterValue`"`r`n"
  $installed = $installed -replace 'appearanceTheme = "system"', 'appearanceTheme = "dark"'
  Write-AuroraSkinUtf8FileAtomically -Path $configPath -Content $installed
  Restore-AuroraSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $restored = Read-AuroraSkinUtf8File -Path $configPath
  if (-not $restored.Contains($projectName) -or -not $restored.Contains($laterValue)) {
    throw 'Restore changed a project name or unrelated post-install setting.'
  }
  if ($restored -notmatch 'appearanceTheme = "dark"' -or -not $restored.Contains('appearanceLightCodeThemeId = "theme-$special"')) {
    throw 'Restore overwrote the user appearance or failed to restore the light code theme.'
  }
  if ($restored -notmatch '(?ms)^\[other\].*?appearanceTheme = "keep-other"') {
    throw 'Restore changed an appearance key outside the desktop section.'
  }

  $legacyConfigPath = Join-Path $temporaryRoot 'legacy-light.toml'
  $legacyBackupPath = Join-Path $temporaryRoot 'legacy-light.before.toml'
  $legacyCurrent = "[desktop]`r`n$($script:AuroraSkinLegacyAppearanceTheme)`r`n$($script:AuroraSkinManagedLightCodeTheme)`r`n$($script:AuroraSkinManagedLightChromeTheme)`r`n"
  $legacyOriginal = "[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-original`"`r`nappearanceLightChromeTheme = { surface = `"original`" }`r`n"
  [System.IO.File]::WriteAllText($legacyConfigPath, $legacyCurrent, $utf8NoBom)
  [System.IO.File]::WriteAllText($legacyBackupPath, $legacyOriginal, $utf8NoBom)
  Install-AuroraSkinBaseTheme -ConfigPath $legacyConfigPath -BackupPath $legacyBackupPath
  $legacyMigrated = Read-AuroraSkinUtf8File -Path $legacyConfigPath
  if ($legacyMigrated -notmatch 'appearanceTheme = "system"' -or
    $legacyMigrated -notmatch 'appearanceLightCodeThemeId = "codex"') {
    throw 'Exact legacy managed light trio was not migrated to the saved native appearance.'
  }
  $legacyMigrated = $legacyMigrated -replace 'appearanceTheme = "system"', 'appearanceTheme = "dark"'
  Write-AuroraSkinUtf8FileAtomically -Path $legacyConfigPath -Content $legacyMigrated
  Restore-AuroraSkinBaseTheme -ConfigPath $legacyConfigPath -BackupPath $legacyBackupPath
  if ((Read-AuroraSkinUtf8File -Path $legacyConfigPath) -notmatch 'appearanceTheme = "dark"') {
    throw 'A current install restore overwrote the user appearance after legacy migration.'
  }

  $lfConfigPath = Join-Path $temporaryRoot 'config-lf.toml'
  $lfBackupPath = Join-Path $temporaryRoot 'config-lf.before.toml'
  $lfOriginal = "model = `"gpt-5`"`n[projects.'C:\$projectName']`ntrust_level = `"trusted`"`n"
  [System.IO.File]::WriteAllText($lfConfigPath, $lfOriginal, $utf8NoBom)
  Install-AuroraSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfInstalled = Read-AuroraSkinUtf8File -Path $lfConfigPath
  if ($lfInstalled.Contains("`r") -or $lfInstalled -notmatch '(?m)^\[desktop\]$') {
    throw 'Install did not preserve LF line endings or create the desktop section.'
  }
  Restore-AuroraSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfRestored = Read-AuroraSkinUtf8File -Path $lfConfigPath
  if ($lfRestored.Contains("`r") -or $lfRestored -match '(?m)^\[desktop\]$' -or -not $lfRestored.Contains($projectName)) {
    throw 'Restore did not preserve LF content or remove the generated empty desktop section.'
  }

  $quotedConfigPath = Join-Path $temporaryRoot 'config-quoted.toml'
  $quotedBackupPath = Join-Path $temporaryRoot 'config-quoted.before.toml'
  $quotedOriginal = "[`"desktop`"] # retained comment`r`n`"appearanceTheme`" = `"system`"`r`n'appearanceLightCodeThemeId' = `"theme-`$special`"`r`n"
  [System.IO.File]::WriteAllText($quotedConfigPath, $quotedOriginal, $utf8NoBom)
  Install-AuroraSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  $quotedInstalled = Read-AuroraSkinUtf8File -Path $quotedConfigPath
  if ([regex]::Matches($quotedInstalled, '(?m)^\s*\[(?:"desktop"|desktop)\]').Count -ne 1) {
    throw 'A commented or quoted desktop table was duplicated during install.'
  }
  Restore-AuroraSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  if ((Read-AuroraSkinUtf8File -Path $quotedConfigPath) -cne $quotedOriginal) {
    throw 'Quoted desktop keys or a table-header comment were not restored exactly.'
  }

  $nestedConfigPath = Join-Path $temporaryRoot 'config-nested-themes.toml'
  $nestedBackupPath = Join-Path $temporaryRoot 'config-nested-themes.before.toml'
  $nestedTables = "[desktop.appearanceDarkChromeTheme]`r`naccent = `"#112233`"`r`n`r`n[desktop.appearanceDarkChromeTheme.fonts]`r`ncode = `"Cascadia Code`"`r`n`r`n[desktop.appearanceDarkChromeTheme.semanticColors]`r`ndiffAdded = `"#234567`"`r`n`r`n[desktop.appearanceLightChromeTheme]`r`naccent = `"#abcdef`"`r`n`r`n[desktop.appearanceLightChromeTheme.fonts]`r`nui = `"Microsoft YaHei UI`"`r`n`r`n[desktop.appearanceLightChromeTheme.semanticColors]`r`ndiffRemoved = `"#fedcba`"`r`n`r`n[`"desktop`".layout]`r`ndensity = `"compact`"`r`n"
  $nestedOriginal = "[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"github-light`"`r`n`r`n$nestedTables"
  [System.IO.File]::WriteAllText($nestedConfigPath, $nestedOriginal, $utf8NoBom)
  Install-AuroraSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  $nestedInstalled = Read-AuroraSkinUtf8File -Path $nestedConfigPath
  $nestedDesktop = Get-AuroraSkinDesktopSection -Content $nestedInstalled
  if (-not $nestedDesktop.Body.Contains('appearanceTheme = "system"') -or
    -not $nestedDesktop.Body.Contains('appearanceLightCodeThemeId = "codex"')) {
    throw 'Install did not update scalar appearance settings beside nested desktop theme tables.'
  }
  if ([regex]::IsMatch($nestedDesktop.Body, '(?m)^[\t ]*appearanceLightChromeTheme[\t ]*=')) {
    throw 'Install wrote an inline light chrome theme beside the equivalent nested table.'
  }
  if (-not $nestedInstalled.Contains($nestedTables)) {
    throw 'Install changed native Codex chrome theme or unrelated nested desktop tables.'
  }
  Restore-AuroraSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  if ((Read-AuroraSkinUtf8File -Path $nestedConfigPath) -cne $nestedOriginal) {
    throw 'Nested desktop theme tables were not preserved through install and restore.'
  }

  $singleLineArrayPath = Join-Path $temporaryRoot 'config-single-line-array.toml'
  $singleLineArrayBackup = Join-Path $temporaryRoot 'config-single-line-array.before.toml'
  $singleLineArray = "labels = [`"name[1]`", `"#tag]`"]`r`n"
  [System.IO.File]::WriteAllText($singleLineArrayPath, $singleLineArray, $utf8NoBom)
  Install-AuroraSkinBaseTheme -ConfigPath $singleLineArrayPath -BackupPath $singleLineArrayBackup
  if (-not (Read-AuroraSkinUtf8File -Path $singleLineArrayPath).Contains($singleLineArray.TrimEnd())) {
    throw 'A safe single-line array containing bracket text was changed or rejected.'
  }

  foreach ($unsupported in @(
    'desktop.appearanceTheme = "system"',
    'desktop = { appearanceTheme = "system" }',
    '[[desktop]]',
    '[[desktop.layout]]',
    '[desktop.appearanceTheme]',
    '[desktop.appearanceLightCodeThemeId]',
    "[desktop]`r`nappearanceLightChromeTheme = { accent = `"#ffffff`" }`r`n`r`n[desktop.appearanceLightChromeTheme]`r`naccent = `"#000000`"",
    '["desk\u0074op".layout]',
    '["desk\u0074op"]',
    "note = `"`"`"fake`r`n[desktop]`r`nappearanceTheme = `"dark`"`r`n`"`"`"",
    "[desktop]`r`nappearanceTheme = [`r`n  `"light`"`r`n]",
    "[desktop]`r`nlayout = [`r`n  [1, 2],`r`n  [3, 4],`r`n]`r`nappearanceTheme = `"dark`"",
    "[desktop]`r`nlayout = [`"]`",`r`n  [`"[`", `"]`"],`r`n]`r`nappearanceTheme = `"dark`""
  )) {
    $unsupportedPath = Join-Path $temporaryRoot ("unsupported-$([guid]::NewGuid().ToString('N')).toml")
    $unsupportedBackup = "$unsupportedPath.before"
    [System.IO.File]::WriteAllText($unsupportedPath, $unsupported, $utf8NoBom)
    $unsupportedRejected = $false
    try { Install-AuroraSkinBaseTheme -ConfigPath $unsupportedPath -BackupPath $unsupportedBackup } catch { $unsupportedRejected = $true }
    if (-not $unsupportedRejected -or (Test-Path -LiteralPath $unsupportedBackup)) {
      throw "Unsupported TOML desktop representation was not rejected safely: $unsupported"
    }
  }

  $recoveryPath = Join-Path $temporaryRoot 'config.before-recovery.toml'
  Write-AuroraSkinUtf8FileAtomically -Path $configPath -Content 'intentionally changed'
  Restore-AuroraSkinConfigBackup -ConfigPath $configPath -BackupPath $backupPath -RecoveryBackupPath $recoveryPath
  $recoveredBytes = [System.IO.File]::ReadAllBytes($configPath)
  if ([Convert]::ToBase64String($recoveredBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Exact config recovery did not restore the original bytes.'
  }
  if ((Read-AuroraSkinUtf8File -Path $recoveryPath) -cne 'intentionally changed') {
    throw 'Exact config recovery did not preserve the replaced current config.'
  }
  $archivePath = Join-Path $temporaryRoot 'config.restored.toml'
  Archive-AuroraSkinConfigBackup -BackupPath $backupPath -ArchivePath $archivePath
  if ((Test-Path -LiteralPath $backupPath) -or -not (Test-Path -LiteralPath $archivePath)) {
    throw 'Completed config backup was not archived for a safe future reinstall.'
  }
  $secondBaseline = "[desktop]`r`nappearanceTheme = `"dark`"`r`n"
  [System.IO.File]::WriteAllText($configPath, $secondBaseline, $utf8NoBom)
  $secondBaselineBytes = [System.IO.File]::ReadAllBytes($configPath)
  Install-AuroraSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  if (-not (Test-AuroraSkinBytesEqual -Left $secondBaselineBytes -Right ([System.IO.File]::ReadAllBytes($backupPath)))) {
    throw 'Reinstall did not capture a fresh config baseline after completed restore.'
  }

  $invalidPath = Join-Path $temporaryRoot 'invalid.toml'
  $invalidBackupPath = Join-Path $temporaryRoot 'invalid.before.toml'
  [System.IO.File]::WriteAllBytes($invalidPath, [byte[]](0x66, 0x6f, 0x80))
  $rejected = $false
  try { Install-AuroraSkinBaseTheme -ConfigPath $invalidPath -BackupPath $invalidBackupPath } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path -LiteralPath $invalidBackupPath)) {
    throw 'Invalid UTF-8 input was not rejected before backup creation.'
  }
  $utf16Path = Join-Path $temporaryRoot 'utf16.toml'
  $utf16BackupPath = Join-Path $temporaryRoot 'utf16.before.toml'
  [System.IO.File]::WriteAllText($utf16Path, 'model = "gpt-5"', [System.Text.Encoding]::Unicode)
  $utf16Rejected = $false
  try { Install-AuroraSkinBaseTheme -ConfigPath $utf16Path -BackupPath $utf16BackupPath } catch { $utf16Rejected = $true }
  if (-not $utf16Rejected -or (Test-Path -LiteralPath $utf16BackupPath)) {
    throw 'A UTF-16 config was silently transcoded instead of being rejected.'
  }
  $utf16NoBomPath = Join-Path $temporaryRoot 'utf16-no-bom.toml'
  $utf16NoBomBackupPath = Join-Path $temporaryRoot 'utf16-no-bom.before.toml'
  [System.IO.File]::WriteAllBytes($utf16NoBomPath, [System.Text.Encoding]::Unicode.GetBytes('model = "gpt-5"'))
  $utf16NoBomRejected = $false
  try { Install-AuroraSkinBaseTheme -ConfigPath $utf16NoBomPath -BackupPath $utf16NoBomBackupPath } catch { $utf16NoBomRejected = $true }
  if (-not $utf16NoBomRejected -or (Test-Path -LiteralPath $utf16NoBomBackupPath)) {
    throw 'A BOM-less UTF-16 config was silently treated as UTF-8 instead of being rejected.'
  }
  $racePath = Join-Path $temporaryRoot 'race.toml'
  [System.IO.File]::WriteAllText($racePath, 'before', $utf8NoBom)
  $raceExpected = [System.IO.File]::ReadAllBytes($racePath)
  [System.IO.File]::WriteAllText($racePath, 'after', $utf8NoBom)
  $raceRejected = $false
  try { Assert-AuroraSkinFileUnchanged -Path $racePath -ExpectedBytes $raceExpected } catch { $raceRejected = $true }
  if (-not $raceRejected) { throw 'Concurrent config modification was not detected.' }
  $conditionalWriteRejected = $false
  try {
    Write-AuroraSkinUtf8FileAtomically -Path $racePath -Content 'replacement' -ExpectedBytes $raceExpected
  } catch {
    $conditionalWriteRejected = $true
  }
  if (-not $conditionalWriteRejected -or (Read-AuroraSkinUtf8File -Path $racePath) -cne 'after') {
    throw 'Conditional atomic write replaced newer config content.'
  }

  if (-not (Test-AuroraSkinWebSocketUrl -Value 'ws://127.0.0.1:9335/devtools/page/test' -Port 9335)) {
    throw 'PowerShell loopback WebSocket validation rejected a safe target.'
  }
  foreach ($unsafe in @(
    'ws://example.com:9335/devtools/page/test',
    'ws://127.0.0.1:9336/devtools/page/test',
    'wss://127.0.0.1:9335/devtools/page/test',
    'ws://user@127.0.0.1:9335/devtools/page/test',
    'ws://127.0.0.1:9335/unexpected/test',
    'ws://127.0.0.1:9335/devtools/page/test?query=1'
  )) {
    if (Test-AuroraSkinWebSocketUrl -Value $unsafe -Port 9335) { throw "Accepted unsafe CDP target: $unsafe" }
  }
  $safePageTarget = [pscustomobject]@{
    id = 'page-123'
    type = 'page'
    url = 'app://codex/'
    webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123'
  }
  if (-not (Test-AuroraSkinCdpPageTarget -Target $safePageTarget -Port 9335)) {
    throw 'A valid same-ID CDP page target was rejected.'
  }
  foreach ($unsafePageTarget in @(
    [pscustomobject]@{ id = 'page-123'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/browser/page-123' },
    [pscustomobject]@{ id = 'other-page'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' },
    [pscustomobject]@{ id = 123; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/123' },
    [pscustomobject]@{ id = 'page-123'; type = 'other'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' }
  )) {
    if (Test-AuroraSkinCdpPageTarget -Target $unsafePageTarget -Port 9335) {
      throw 'Accepted an inconsistent CDP page target.'
    }
  }
  $watchCommand = '"C:\Program Files\nodejs\node.exe" "C:\Aurora Skin\injector.mjs" --watch --port 9335 --browser-id browser-123'
  if (-not (Test-AuroraSkinCommandLineToken -CommandLine $watchCommand -Token 'C:\Aurora Skin\injector.mjs') -or
    (Test-AuroraSkinCommandLineToken -CommandLine $watchCommand -Token 'Aurora Skin\injector.mjs')) {
    throw 'Injector command-line token validation is not boundary-safe.'
  }
  $forwardedDebugProcess = [pscustomobject]@{
    CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe" --remote-debugging-port=9335'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus -Processes @($forwardedDebugProcess) -Port 9335) -cne 'forwarded') {
    throw 'A raw Chromium debugging argument was not recognized as forwarded.'
  }
  $redirectedDebugProcess = [pscustomobject]@{
    CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe" codex://threads/new?path=--remote-debugging-port%3D9335'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus -Processes @($redirectedDebugProcess) -Port 9335) -cne 'protocol-redirected') {
    throw 'An owl codex:// debugging-argument redirect was not recognized.'
  }
  $unencodedRedirectedDebugProcess = [pscustomobject]@{
    CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe" codex://threads/new?path=--remote-debugging-port=9335'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus `
      -Processes @($unencodedRedirectedDebugProcess) -Port 9335) -cne 'protocol-redirected') {
    throw 'An unencoded debugging flag inside codex:// was confused with a raw Chromium argument.'
  }
  $separateRawDebugProcess = [pscustomobject]@{
    CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe" codex://threads/new --remote-debugging-port=9335'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus `
      -Processes @($separateRawDebugProcess) -Port 9335) -cne 'forwarded') {
    throw 'A separate raw debugging argument was hidden by an ordinary codex:// argument.'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus `
      -Processes @($redirectedDebugProcess, $forwardedDebugProcess) -Port 9335) -cne 'forwarded') {
    throw 'A raw forwarded argument did not take precedence over a protocol-looking helper process.'
  }
  $ordinaryProtocolProcess = [pscustomobject]@{
    CommandLine = '"C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe" codex://threads/new?path=C%3A%5Cwork'
  }
  if ((Get-AuroraSkinCodexDebugArgumentStatus -Processes @($ordinaryProtocolProcess) -Port 9335) -cne 'not-forwarded' -or
    (Get-AuroraSkinCodexDebugArgumentStatus -Processes @() -Port 9335) -cne 'uninspectable') {
    throw 'Debugging argument inspection confused an ordinary protocol launch or an empty process set.'
  }
  if ((Get-AuroraSkinDirectLaunchFailureKind -Exception ([System.UnauthorizedAccessException]::new('denied'))) -cne 'access-denied' -or
    (Get-AuroraSkinDirectLaunchFailureKind -Exception ([System.InvalidOperationException]::new('failed'))) -cne 'start-failed') {
    throw 'Direct Store launch failures were not classified safely.'
  }
  if (-not (Test-AuroraSkinBrowserId -Value 'browser-123') -or
    (Test-AuroraSkinBrowserId -Value 'browser 123')) {
    throw 'CDP browser ID validation is not boundary-safe.'
  }
  $quotedProfile = ConvertTo-AuroraSkinProcessArgument -Value '--user-data-dir=C:\Aurora Skin\Profile\'
  if ($quotedProfile -cne '"--user-data-dir=C:\Aurora Skin\Profile\\"') {
    throw 'Process argument quoting did not protect spaces and a trailing backslash.'
  }
  $argumentLine = ConvertTo-AuroraSkinArgumentLine -Arguments @(
    '--remote-debugging-address=127.0.0.1',
    '--user-data-dir=C:\Aurora Skin\Profile\',
    ''
  )
  if ($argumentLine -cne '--remote-debugging-address=127.0.0.1 "--user-data-dir=C:\Aurora Skin\Profile\\" ""') {
    throw 'Packaged-app argument line quoting failed.'
  }
  Initialize-AuroraSkinPackageLauncher
  if (-not ('CodexAuroraSkin.PackageLauncher' -as [type])) {
    throw 'Packaged-app activation helper did not compile.'
  }
  $invalidActivationRejected = $false
  try { $null = Start-AuroraSkinCodex -Codex ([pscustomobject]@{ AppUserModelId = 'invalid app' }) } catch {
    $invalidActivationRejected = $true
  }
  if (-not $invalidActivationRejected) { throw 'An invalid AppUserModelId reached package activation.' }

  $statePath = Join-Path $temporaryRoot 'state.json'
  $state = [pscustomobject]@{
    schemaVersion = 3
    platform = 'windows'
    port = 9335
    injectorPid = 1234
    injectorStartedAt = '2026-01-01T00:00:00.0000000Z'
    injectorPath = 'C:\Aurora Skin\injector.mjs'
    nodePath = 'C:\Program Files\nodejs\node.exe'
    codexExe = 'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex'
    codexPackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    codexPackageFamilyName = 'OpenAI.Codex_test'
    browserId = 'browser-123'
  }
  Write-AuroraSkinState -Path $statePath -State $state
  $loadedState = Read-AuroraSkinState -Path $statePath
  if ($loadedState.schemaVersion -ne 3 -or $loadedState.port -ne 9335 -or
    $loadedState.browserId -cne 'browser-123') { throw 'State round-trip failed.' }
  $missingIdentityState = [pscustomobject]@{ schemaVersion = 3; platform = 'windows'; port = 9335 }
  Write-AuroraSkinState -Path $statePath -State $missingIdentityState
  $missingIdentityRejected = $false
  try { $null = Read-AuroraSkinState -Path $statePath } catch { $missingIdentityRejected = $true }
  if (-not $missingIdentityRejected) { throw 'Schema 3 accepted a state missing process and package identity.' }
  $legacyState = [pscustomobject]@{ schemaVersion = 2; platform = 'windows'; port = 9335; injectorPid = 1234 }
  Write-AuroraSkinState -Path $statePath -State $legacyState
  if ((Read-AuroraSkinState -Path $statePath).schemaVersion -ne 2) {
    throw 'A supported schema 2 state was rejected.'
  }

  $fakePackageRoot = Join-Path $temporaryRoot 'OpenAI.Codex_1.2.3.4_x64__test'
  $fakeExecutable = Join-Path $fakePackageRoot 'app\ChatGPT.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fakeExecutable) -Force | Out-Null
  [System.IO.File]::WriteAllBytes($fakeExecutable, [byte[]]@())
  $fakePackage = [pscustomobject]@{
    Name = 'OpenAI.Codex'
    InstallLocation = $fakePackageRoot
    PackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    PackageFamilyName = 'OpenAI.Codex_test'
    SignatureKind = 'Store'
    IsDevelopmentMode = $false
    Version = [version]'1.2.3.4'
  }
  $fakeManifest = [pscustomobject]@{
    Package = [pscustomobject]@{
      Applications = [pscustomobject]@{
        Application = @(
          [pscustomobject]@{ Id = 'Other'; Executable = 'other\Other.exe' },
          [pscustomobject]@{ Id = 'App'; Executable = 'app/ChatGPT.exe' }
        )
      }
    }
  }
  $fakeInstall = ConvertTo-AuroraSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest
  if ($null -eq $fakeInstall -or $fakeInstall.PackageFullName -cne $fakePackage.PackageFullName -or
    $fakeInstall.AppUserModelId -cne 'OpenAI.Codex_test!App' -or
    -not (Test-AuroraSkinPathEqual -Left $fakeInstall.Executable -Right $fakeExecutable)) {
    throw 'Registered Appx package identity conversion failed.'
  }
  Assert-AuroraSkinCodexDirectLaunchTarget -Codex $fakeInstall
  $invalidDirectTarget = [pscustomobject]@{
    PackageRoot = $fakeInstall.PackageRoot
    Executable = (Join-Path $fakeInstall.PackageRoot 'other\ChatGPT.exe')
    PackageFullName = $fakeInstall.PackageFullName
    PackageFamilyName = $fakeInstall.PackageFamilyName
    ApplicationId = $fakeInstall.ApplicationId
    AppUserModelId = $fakeInstall.AppUserModelId
    SignatureKind = $fakeInstall.SignatureKind
  }
  $invalidDirectTargetRejected = $false
  try { Assert-AuroraSkinCodexDirectLaunchTarget -Codex $invalidDirectTarget } catch {
    $invalidDirectTargetRejected = $true
  }
  if (-not $invalidDirectTargetRejected) { throw 'Direct launch accepted an executable outside the validated Store manifest path.' }

  $launcherFunctionNames = @(
    'Start-AuroraSkinCodex',
    'Wait-AuroraSkinCodexDebugArgumentStatus',
    'Start-AuroraSkinCodexDirect',
    'Stop-AuroraSkinCodex',
    'Get-AuroraSkinCodexProcesses'
  )
  $originalLauncherFunctions = @{}
  foreach ($functionName in $launcherFunctionNames) {
    $originalLauncherFunctions[$functionName] = (Get-Command $functionName -CommandType Function).ScriptBlock
  }
  try {
    Set-Item 'function:Start-AuroraSkinCodex' -Value { param($Codex, $Arguments) return 101 }
    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value { param($Codex, $Port) return 'forwarded' }
    Set-Item 'function:Start-AuroraSkinCodexDirect' -Value { throw 'Direct fallback must not run for compatible package activation.' }
    Set-Item 'function:Stop-AuroraSkinCodex' -Value {
      param($Codex, [int[]]$PreserveProcessIds, [switch]$AllowForce)
    }
    Set-Item 'function:Get-AuroraSkinCodexProcesses' -Value {
      return @(
        [pscustomobject]@{ ProcessId = 10 },
        [pscustomobject]@{ ProcessId = 20 },
        [pscustomobject]@{ ProcessId = 30 }
      )
    }
    $newProcesses = @(Get-AuroraSkinCodexProcessesExcept -Codex $fakeInstall -PreserveProcessIds @(10, 30))
    if ($newProcesses.Count -ne 1 -or $newProcesses[0].ProcessId -ne 20) {
      throw 'Launch rollback did not preserve the exact pre-launch Codex PID set.'
    }
    $compatibleLaunch = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
      -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    if ($compatibleLaunch.ProcessId -ne 101 -or $compatibleLaunch.Strategy -cne 'package-activation') {
      throw 'Compatible package activation did not remain the preferred launch strategy.'
    }
    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value { param($Codex, $Port) return 'uninspectable' }
    $uninspectableLaunch = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
      -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    if ($uninspectableLaunch.Strategy -cne 'package-activation' -or
      $uninspectableLaunch.ArgumentStatus -cne 'uninspectable') {
      throw 'An uninspectable package process was not kept on the conservative package-activation path.'
    }
    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value { param($Codex, $Port) return 'not-forwarded' }
    $notForwardedLaunch = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
      -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    if ($notForwardedLaunch.Strategy -cne 'package-activation' -or
      $notForwardedLaunch.ArgumentStatus -cne 'not-forwarded') {
      throw 'A command-line observation without explicit protocol redirection triggered an unsafe fallback.'
    }

    $script:dreamSkinDebugStatusCall = 0
    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value {
      param($Codex, $Port)
      $script:dreamSkinDebugStatusCall += 1
      if ($script:dreamSkinDebugStatusCall -eq 1) { return 'protocol-redirected' }
      return 'forwarded'
    }
    Set-Item 'function:Start-AuroraSkinCodexDirect' -Value { param($Codex, $Arguments) return 202 }
    $fallbackLaunch = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
      -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    if ($fallbackLaunch.ProcessId -ne 202 -or $fallbackLaunch.Strategy -cne 'direct-store-executable' -or
      $fallbackLaunch.PackageArgumentStatus -cne 'protocol-redirected') {
      throw 'owl protocol redirection did not use the validated direct Store executable fallback.'
    }

    $script:dreamSkinDebugStatusCall = 0
    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value {
      param($Codex, $Port)
      $script:dreamSkinDebugStatusCall += 1
      if ($script:dreamSkinDebugStatusCall -eq 1) { return 'protocol-redirected' }
      return 'not-forwarded'
    }
    $directArgumentFailureReported = $false
    try {
      $null = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
        -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    } catch {
      $directArgumentFailureReported = $_.Exception.Message.Contains(
        'package activation or validated direct launch')
    }
    if (-not $directArgumentFailureReported) {
      throw 'A direct fallback that also dropped the CDP argument did not fail closed.'
    }

    Set-Item 'function:Wait-AuroraSkinCodexDebugArgumentStatus' -Value { param($Codex, $Port) return 'protocol-redirected' }
    Set-Item 'function:Start-AuroraSkinCodexDirect' -Value {
      throw [System.UnauthorizedAccessException]::new('denied')
    }
    $accessDeniedReported = $false
    try {
      $null = Start-AuroraSkinCodexForDebugging -Codex $fakeInstall `
        -Arguments @('--remote-debugging-port=9335') -Port 9335 -PreserveProcessIds @()
    } catch {
      $accessDeniedReported = $_.Exception.Message.Contains('(access-denied)') -and
        $_.Exception.Message.Contains('protected app package')
    }
    if (-not $accessDeniedReported) { throw 'A blocked direct Store launch did not produce the compatibility error.' }
  } finally {
    foreach ($functionName in $launcherFunctionNames) {
      Set-Item ("function:$functionName") -Value $originalLauncherFunctions[$functionName]
    }
    Remove-Variable -Name dreamSkinDebugStatusCall -Scope Script -ErrorAction SilentlyContinue
  }
  $fakeManifest.Package.Applications.Application[1].Id = 'Invalid App'
  if ($null -ne (ConvertTo-AuroraSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'An invalid packaged-app application ID was accepted.'
  }
  $fakeManifest.Package.Applications.Application[1].Id = 'App'
  $fakeManifest.Package.Applications.Application += [pscustomobject]@{ Id = 'Duplicate'; Executable = 'app\ChatGPT.exe' }
  if ($null -ne (ConvertTo-AuroraSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'An ambiguous packaged-app manifest was accepted.'
  }
  $fakeManifest.Package.Applications.Application = @($fakeManifest.Package.Applications.Application[0..1])
  $fakePackage.SignatureKind = 'Developer'
  if ($null -ne (ConvertTo-AuroraSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'A non-Store Appx package was accepted as official Codex.'
  }
  $fakePackage.SignatureKind = 'Store'
  $pathOnlyState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
  }
  if ($null -eq (Get-AuroraSkinCodexStatePathCandidate -State $pathOnlyState)) {
    throw 'A structurally valid legacy Codex path was not recognized for read-only activity checks.'
  }
  if ($null -eq (Resolve-AuroraSkinCodexInstallFromState -State $pathOnlyState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A legacy state path was not revalidated against a registered Store package.'
  }
  $verifiedPackageState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
    codexPackageFullName = $fakePackage.PackageFullName
    codexPackageFamilyName = $fakePackage.PackageFamilyName
  }
  $resolvedInstall = Resolve-AuroraSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall)
  if ($null -eq $resolvedInstall -or -not $resolvedInstall.RegisteredPackageVerified -or
    $resolvedInstall.AppUserModelId -cne $fakeInstall.AppUserModelId) {
    throw 'State package identity did not resolve against the registered Appx package.'
  }
  $verifiedPackageState.codexPackageFamilyName = 'OpenAI.Codex_wrong'
  if ($null -ne (Resolve-AuroraSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A mismatched Appx package family was accepted from state.'
  }
  Write-AuroraSkinUtf8FileAtomically -Path $statePath -Content '[]'
  $badStateRejected = $false
  try { $null = Read-AuroraSkinState -Path $statePath } catch { $badStateRejected = $true }
  if (-not $badStateRejected) { throw 'A non-object state file was accepted.' }
  $staleStatePath = Archive-AuroraSkinStateFile -Path $statePath
  if ((Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $staleStatePath)) {
    throw 'Stale state was not preserved under an archive name.'
  }

  $migrationConfig = Join-Path $temporaryRoot 'migration-config.toml'
  $migrationBackup = Join-Path $temporaryRoot 'migration-config.before.toml'
  $migrationArchive = Join-Path $temporaryRoot 'migration-config.archived.toml'
  $migrationCurrent = "[desktop]`r`n$($script:AuroraSkinLegacyAppearanceTheme)`r`nappearanceLightCodeThemeId = `"user-custom`"`r`n$($script:AuroraSkinManagedLightChromeTheme)`r`n"
  $migrationOriginal = "[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"original-code`"`r`nappearanceLightChromeTheme = { surface = `"original`" }`r`n"
  [System.IO.File]::WriteAllText($migrationConfig, $migrationCurrent, $utf8NoBom)
  [System.IO.File]::WriteAllText($migrationBackup, $migrationOriginal, $utf8NoBom)
  $null = Move-AuroraSkinLegacyConfigToOfficialDefaults -ConfigPath $migrationConfig `
    -BackupPath $migrationBackup -ArchivePath $migrationArchive
  $migrationResult = Read-AuroraSkinUtf8File -Path $migrationConfig
  if ($migrationResult -notmatch 'appearanceTheme = "system"' -or
    $migrationResult -notmatch 'appearanceLightCodeThemeId = "user-custom"' -or
    $migrationResult -notmatch 'appearanceLightChromeTheme = \{ surface = "original" \}' -or
    (Test-Path -LiteralPath $migrationBackup) -or
    -not (Test-Path -LiteralPath $migrationArchive -PathType Leaf)) {
    throw 'Legacy config migration did not selectively restore managed values and preserve user edits.'
  }

  $themeStateRoot = Join-Path $temporaryRoot 'theme-state'
  $legacyPresetDirectory = Join-Path $themeStateRoot 'themes\preset-romantic-rose'
  $customThemeDirectory = Join-Path $themeStateRoot 'themes\custom-keepme'
  New-Item -ItemType Directory -Force -Path $legacyPresetDirectory, $customThemeDirectory | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $legacyPresetDirectory 'retired-marker'), 'retired', $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $customThemeDirectory 'keep-marker'), 'keep', $utf8NoBom)
  $themePaths = Initialize-AuroraSkinThemeStore -SkillRoot $Root -StateRoot $themeStateRoot
  if ((Test-Path -LiteralPath $legacyPresetDirectory) -or
    -not (Test-Path -LiteralPath (Join-Path $customThemeDirectory 'keep-marker'))) {
    throw 'Theme-store migration did not retire the old preset ID while preserving custom themes.'
  }
  $initialTheme = Read-AuroraSkinTheme -ThemeDirectory $themePaths.Active
  if ($initialTheme.Theme.id -cne 'preset-red-white-abstract' -or
    $initialTheme.Theme.name -cne '红白抽象' -or
    $initialTheme.Theme.appearance -cne 'auto' -or
    $initialTheme.Theme.art.safeArea -cne 'auto' -or
    $initialTheme.Theme.art.taskMode -cne 'auto' -or
    [System.IO.Path]::GetExtension($initialTheme.ImagePath) -cne '.png') {
    throw 'Default Windows theme did not seed the red-white abstract wallpaper contract.'
  }
  $preseededThemes = @(Get-AuroraSkinSavedThemes -StateRoot $themeStateRoot)
  $preseededIds = @($preseededThemes | ForEach-Object { $_.Id })
  if ($preseededThemes.Count -lt 1 -or
    $preseededIds -notcontains 'preset-red-white-abstract') {
    throw 'Windows did not preserve the legacy seed as the rights-cleared default theme.'
  }
  $updatedTheme = Set-AuroraSkinActiveTheme -ImagePath (Join-Path $Root 'assets\red-white-abstract.png') `
    -Theme $null -Name '测试主题' -StateRoot $themeStateRoot
  if ($updatedTheme.Theme.name -cne '测试主题' -or
    $updatedTheme.Theme.id -cne 'custom' -or
    $updatedTheme.Theme.art.safeArea -cne 'auto' -or
    $updatedTheme.Theme.art.taskMode -cne 'auto' -or
    -not (Test-AuroraSkinThemePathWithin -Path $updatedTheme.ImagePath -Root $themePaths.Active)) {
    throw 'Imported image did not reset to the generic adaptive contract inside the managed directory.'
  }
  $null = Initialize-AuroraSkinThemeStore -SkillRoot $Root -StateRoot $themeStateRoot
  $idempotentTheme = Read-AuroraSkinTheme -ThemeDirectory $themePaths.Active
  $afterReinitCount = @(Get-AuroraSkinSavedThemes -StateRoot $themeStateRoot).Count
  if ($idempotentTheme.Theme.id -cne 'custom' -or $afterReinitCount -ne 1) {
    throw 'Theme-store initialization overwrote the active custom theme or duplicated its bundled presets.'
  }

  $releaseFixtureRoot = Join-Path $temporaryRoot 'release-theme-fixture'
  $releaseFixtureAssets = Join-Path $releaseFixtureRoot 'assets'
  $releaseFixtureScripts = Join-Path $releaseFixtureRoot 'scripts'
  $releaseFixturePresets = Join-Path $releaseFixtureRoot 'presets'
  $releaseFixturePresetDirectory = Join-Path $releaseFixturePresets 'preset-red-white-abstract'
  $releaseFixtureState = Join-Path $temporaryRoot 'release-theme-state'
  $repositoryRoot = Split-Path -Parent $Root
  $publicPresetRoot = Join-Path $repositoryRoot 'library\preset-red-white-abstract'
  New-Item -ItemType Directory -Path $releaseFixtureAssets, $releaseFixtureScripts, $releaseFixturePresetDirectory -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root 'VERSION') -Destination $releaseFixtureRoot -Force
  foreach ($releaseAsset in @('aurora-skin.css', 'renderer-inject.js', 'selectors.json')) {
    Copy-Item -LiteralPath (Join-Path $Root "assets\$releaseAsset") `
      -Destination $releaseFixtureAssets -Force
  }
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\common-windows.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\config-utf8.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\image-metadata.mjs') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\injector.mjs') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\install-aurora-skin.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\launch-manager.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\restore-aurora-skin.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\start-aurora-skin.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\theme-windows.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $Root 'scripts\verify-aurora-skin.ps1') -Destination $releaseFixtureScripts -Force
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'library') -Destination $releaseFixtureRoot -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'manager') -Destination $releaseFixtureRoot -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $publicPresetRoot 'background.png') `
    -Destination $releaseFixturePresetDirectory -Force
  Copy-Item -LiteralPath (Join-Path $publicPresetRoot 'theme.json') `
    -Destination $releaseFixturePresetDirectory -Force
  Copy-Item -LiteralPath (Join-Path $publicPresetRoot 'background.png') `
    -Destination (Join-Path $releaseFixtureAssets 'aurora-reference.png') -Force
  $releaseFixtureTheme = (Read-AuroraSkinUtf8File -Path (Join-Path $publicPresetRoot 'theme.json')) |
    ConvertFrom-Json
  $releaseFixtureTheme.image = 'aurora-reference.png'
  Write-AuroraSkinUtf8FileAtomically -Path (Join-Path $releaseFixtureAssets 'theme.json') `
    -Content (($releaseFixtureTheme | ConvertTo-Json -Depth 8) + "`r`n")
  $releaseThemePaths = Initialize-AuroraSkinThemeStore -SkillRoot $releaseFixtureRoot `
    -StateRoot $releaseFixtureState
  $releaseActiveTheme = Read-AuroraSkinTheme -ThemeDirectory $releaseThemePaths.Active
  $releaseSavedThemes = @(Get-AuroraSkinSavedThemes -StateRoot $releaseFixtureState)
  if ($releaseActiveTheme.Theme.id -cne 'preset-red-white-abstract' -or
    $releaseSavedThemes.Count -ne 1 -or
    $releaseSavedThemes[0].Id -cne 'preset-red-white-abstract') {
    throw 'Release-safe bundled theme did not seed dynamically by its validated preset id.'
  }
  $releaseEngine = Install-AuroraSkinRuntimeEngine -SkillRoot $releaseFixtureRoot `
    -StateRoot (Join-Path $temporaryRoot 'release-engine-state')
  if (-not (Test-Path -LiteralPath (Join-Path $releaseEngine.Root 'library\preset-red-white-abstract\theme.json') -PathType Leaf)) {
    throw 'Release-shaped payload could not stage its public preset into the managed engine.'
  }

  $savedTheme = Save-AuroraSkinCurrentTheme -Name '已保存主题' -StateRoot $themeStateRoot
  if ($savedTheme.Theme.name -cne '已保存主题' -or @(Get-AuroraSkinSavedThemes -StateRoot $themeStateRoot).Count -ne 2) {
    throw 'Saved theme creation or discovery failed.'
  }
  $null = Use-AuroraSkinSavedTheme -ThemeDirectory $savedTheme.Directory -StateRoot $themeStateRoot

  $outsideTheme = Join-Path $temporaryRoot 'outside-theme'
  New-Item -ItemType Directory -Path $outsideTheme | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root 'assets\red-white-abstract.png') `
    -Destination (Join-Path $outsideTheme 'red-white-abstract.png')
  Copy-Item -LiteralPath (Join-Path $Root 'assets\theme.json') `
    -Destination (Join-Path $outsideTheme 'theme.json')
  $junctionTheme = Join-Path $themePaths.Saved 'junction-escape'
  $null = New-Item -ItemType Junction -Path $junctionTheme -Target $outsideTheme
  $junctionRejected = $false
  try {
    $null = Use-AuroraSkinSavedTheme -ThemeDirectory $junctionTheme -StateRoot $themeStateRoot
  } catch { $junctionRejected = $true }
  if (-not $junctionRejected) { throw 'Saved-theme junction escaped the managed theme directory.' }
  [System.IO.Directory]::Delete($junctionTheme)

  Set-AuroraSkinPaused -Paused $true -StateRoot $themeStateRoot | Out-Null
  if (-not (Test-AuroraSkinPaused -StateRoot $themeStateRoot)) { throw 'Pause marker was not created.' }
  Set-AuroraSkinPaused -Paused $false -StateRoot $themeStateRoot | Out-Null
  if (Test-AuroraSkinPaused -StateRoot $themeStateRoot) { throw 'Pause marker was not removed.' }

  $oversizedTheme = Join-Path $temporaryRoot 'oversized-theme'
  New-Item -ItemType Directory -Path $oversizedTheme | Out-Null
  $oversizedImage = Join-Path $oversizedTheme 'oversized.jpg'
  $oversizedStream = [System.IO.File]::Open($oversizedImage, [System.IO.FileMode]::CreateNew)
  try { $oversizedStream.SetLength((16 * 1024 * 1024) + 1) } finally { $oversizedStream.Dispose() }
  Write-AuroraSkinUtf8FileAtomically -Path (Join-Path $oversizedTheme 'theme.json') `
    -Content "{`"image`":`"oversized.jpg`"}`r`n"
  $oversizedReadRejected = $false
  try { $null = Read-AuroraSkinTheme -ThemeDirectory $oversizedTheme } catch { $oversizedReadRejected = $true }
  $oversizedSetRejected = $false
  try {
    $null = Set-AuroraSkinActiveTheme -ImagePath $oversizedImage -Theme $null -StateRoot $themeStateRoot
  } catch { $oversizedSetRejected = $true }
  if (-not $oversizedReadRejected -or -not $oversizedSetRejected) {
    throw 'The 16 MB image limit was not enforced before theme copy or payload construction.'
  }

  $oversizedDimensionImage = Join-Path $temporaryRoot 'oversized-dimension.png'
  $pngHeader = New-Object byte[] 24
  [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a) | ForEach-Object -Begin { $i = 0 } -Process { $pngHeader[$i++] = $_ }
  $pngHeader[8] = 0; $pngHeader[9] = 0; $pngHeader[10] = 0; $pngHeader[11] = 13
  [byte[]](0x49, 0x48, 0x44, 0x52) | ForEach-Object -Begin { $i = 12 } -Process { $pngHeader[$i++] = $_ }
  $pngHeader[16] = 0; $pngHeader[17] = 0; $pngHeader[18] = 0x27; $pngHeader[19] = 0x10
  $pngHeader[20] = 0; $pngHeader[21] = 0; $pngHeader[22] = 0x17; $pngHeader[23] = 0x70
  [System.IO.File]::WriteAllBytes($oversizedDimensionImage, $pngHeader)
  $oversizedDimensionRejected = $false
  try { $null = Set-AuroraSkinActiveTheme -ImagePath $oversizedDimensionImage -Theme $null -StateRoot $themeStateRoot } catch { $oversizedDimensionRejected = $true }
  if (-not $oversizedDimensionRejected) { throw 'A 16384px/50MP-invalid import was copied into the active theme.' }

  $reparseStateRoot = Join-Path $temporaryRoot 'reparse-state'
  New-Item -ItemType Directory -Path $reparseStateRoot | Out-Null
  $outsideActive = Join-Path $temporaryRoot 'outside-active'
  New-Item -ItemType Directory -Path $outsideActive | Out-Null
  $reparseActive = Join-Path $reparseStateRoot 'active-theme'
  $null = New-Item -ItemType Junction -Path $reparseActive -Target $outsideActive
  $reparseInitRejected = $false
  try { $null = Initialize-AuroraSkinThemeStore -SkillRoot $Root -StateRoot $reparseStateRoot } catch { $reparseInitRejected = $true }
  if (-not $reparseInitRejected) { throw 'Theme-store initialization followed an active-theme junction.' }
  [System.IO.Directory]::Delete($reparseActive)

  $css = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'assets\aurora-skin.css')
  foreach ($requiredCss in @(
    '--ds-art-brightness',
    'filter: brightness(var(--ds-art-brightness))',
    'data-app-shell-main-surface',
    'data-app-shell-header-edge-scroll',
    '[data-aurora-part="main"]',
    '[data-aurora-part="composer"]',
    'data-composer-surface-variant',
    'data-composer-footer-responsive',
    '_ComposerLayoutBody_',
    '[class~="group/application-menu-top-bar"]',
    '.app-shell-main-content-top-fade',
    ':is(.thread-scroll-container .bg-gradient-to-t.from-token-main-surface-primary, .thread-scroll-container .bg-gradient-to-t.from-surface.via-surface)',
    '--ds-immersive-composer',
    'var(--ds-art-position)',
    'html[data-aurora-skin="active"]',
    '[data-dream-route="home"]',
    '[data-dream-search-band="true"]',
    '[data-dream-search-input="true"]',
    '[data-dream-project-host="true"]'
  )) {
    if (-not $css.Contains($requiredCss)) { throw "Windows immersive CSS is missing: $requiredCss" }
  }
  if ($css.Contains(':has(')) {
    throw 'Runtime CSS must not contain relational :has() selectors.'
  }
  if ($css.Contains('home-suggestion-list-item') -or
    $css.Contains('.aurora-skin-home') -or $css.Contains('.dream-home') -or
    $css.Contains('.dream-task') -or $css.Contains('codex-aurora-skin-chrome')) {
    throw 'Canonical CSS still contains retired marker classes or fossil selectors.'
  }
  $macCssPath = Join-Path (Split-Path -Parent $Root) 'macos\assets\aurora-skin.css'
  if (-not (Test-Path -LiteralPath $macCssPath) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $macCssPath).Hash -cne
    (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'assets\aurora-skin.css')).Hash) {
    throw 'macOS and Windows canonical CSS assets are not byte-identical.'
  }
  $macSelectorsPath = Join-Path (Split-Path -Parent $Root) 'macos\assets\selectors.json'
  if (-not (Test-Path -LiteralPath $macSelectorsPath) -or
    (Get-FileHash -Algorithm SHA256 -LiteralPath $macSelectorsPath).Hash -cne
    (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'assets\selectors.json')).Hash) {
    throw 'macOS and Windows selector contract assets are not byte-identical.'
  }
  $managerSource = Read-AuroraSkinUtf8File -Path (Join-Path $repositoryRoot 'manager\server.mjs')
  foreach ($requiredManagerToken in @(
    '/api/bootstrap',
    '/api/themes/import',
    '/api/session/start',
    '/api/restore',
    'Authorization',
    '127.0.0.1'
  )) {
    if (-not $managerSource.Contains($requiredManagerToken)) {
      throw "Browser manager is missing: $requiredManagerToken"
    }
  }
  $themeWindowsSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\theme-windows.ps1')
  foreach ($requiredLiveRemoveToken in @(
    'function Invoke-AuroraSkinLiveRemove',
    'function Show-AuroraSkinOperationUi',
    "'--remove'",
    "'--browser-id'",
    "'--begin-operation'",
    'Invoke-AuroraSkinNative'
  )) {
    if (-not $themeWindowsSource.Contains($requiredLiveRemoveToken)) {
      throw "Live remove helper is missing required token: $requiredLiveRemoveToken"
    }
  }
  $injectorSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\injector.mjs')
  foreach ($requiredOperationUi in @(
    'chatgpt-aurora-skin-operation',
    'begin-operation',
    'finish-operation',
    '正在暂停皮肤…',
    'presentOperationUi',
    'operationUiExpression'
  )) {
    if (-not $injectorSource.Contains($requiredOperationUi)) {
      throw "Windows injector operation UI is missing: $requiredOperationUi"
    }
  }
  $restoreSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\restore-aurora-skin.ps1')
  if ($restoreSource.Contains('Start-Process -FilePath $relaunchCodex.Executable') -or
    -not $restoreSource.Contains('Start-AuroraSkinCodex -Codex $relaunchCodex')) {
    throw 'Restore still executes the WindowsApps path instead of activating the registered package.'
  }
  $startSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\start-aurora-skin.ps1')
  if ($startSource.Contains('Start-Process -FilePath $codex.Executable') -or
    -not $startSource.Contains('Start-AuroraSkinCodexForDebugging -Codex $codex')) {
    throw 'Start bypasses the guarded package-activation and Store-executable launch strategy.'
  }
  $stateReadIndex = $startSource.IndexOf('$previousState = Read-AuroraSkinState', [System.StringComparison]::Ordinal)
  $restartPromptIndex = $startSource.IndexOf('$restartAuthorized = Confirm-AuroraSkinRestart', [System.StringComparison]::Ordinal)
  $recordedStopIndex = $startSource.IndexOf('$recordedInjectorStopped = Stop-AuroraSkinRecordedInjector', [System.StringComparison]::Ordinal)
  $cancelIndex = $startSource.IndexOf("Write-Host 'Aurora Skin launch was cancelled", [System.StringComparison]::Ordinal)
  $pauseClearIndex = $startSource.IndexOf('Set-AuroraSkinPaused -Paused $false', [System.StringComparison]::Ordinal)
  if ($stateReadIndex -lt 0 -or $pauseClearIndex -le $stateReadIndex -or
    ($restartPromptIndex -ge 0 -and $pauseClearIndex -le $restartPromptIndex) -or
    ($recordedStopIndex -ge 0 -and $pauseClearIndex -le $recordedStopIndex) -or
    ($cancelIndex -ge 0 -and $cancelIndex -ge $pauseClearIndex)) {
    throw 'Start clears the pause marker before state validation or restart consent, or before its cancellation branch.'
  }
  if (-not $startSource.Contains('$pauseWasSet = Test-AuroraSkinPaused') -or
    -not $startSource.Contains('$pauseCleared = $true') -or
    -not $startSource.Contains('Set-AuroraSkinPaused -Paused $true -StateRoot $StateRoot')) {
    throw 'Start does not preserve an existing pause marker when startup rolls back.'
  }
  if (-not $startSource.Contains('$verifyDeadline') -or
    -not $startSource.Contains('Start-Sleep -Seconds 3')) {
    throw 'Start lost the verification retry window; a single early-boot miss must not tear the startup down.'
  }
  if (-not $startSource.Contains('WaitForExit(15000)')) {
    throw 'Startup rollback no longer waits long enough for its own injector to exit; short waits leave duelling watchers.'
  }
  if (-not $startSource.Contains('Get-AuroraSkinVerifiedCdpIdentityForAnyRegistered')) {
    throw 'Start lost the any-registered endpoint fallback for Store auto-updates.'
  }
  $verifyScriptSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\verify-aurora-skin.ps1')
  if (-not $verifyScriptSource.Contains('Get-AuroraSkinVerifiedCdpIdentityForAnyRegistered')) {
    throw 'Verify lost the any-registered endpoint fallback for Store auto-updates.'
  }
  if (-not $verifyScriptSource.Contains(
      ". (Join-Path `$PSScriptRoot 'theme-windows.ps1')")) {
    throw 'Verify must load theme-windows.ps1 before resolving the staged active theme.'
  }
  foreach ($verifyCaller in @(
    @{ Name = 'start-aurora-skin.ps1'; Source = $startSource },
    @{ Name = 'verify-aurora-skin.ps1'; Source = $verifyScriptSource }
  )) {
    $verifyIndex = $verifyCaller.Source.IndexOf("'--verify'", [System.StringComparison]::Ordinal)
    $themeDirIndex = $verifyCaller.Source.IndexOf("'--theme-dir'", [System.StringComparison]::Ordinal)
    if ($verifyIndex -lt 0 -or $themeDirIndex -lt 0) {
      throw "$($verifyCaller.Name) must pass --theme-dir to --verify; the injector's assets fallback compares against the wrong expected theme."
    }
  }
  if (-not (Get-Command Get-AuroraSkinVerifiedCdpIdentityForAnyRegistered -CommandType Function -ErrorAction SilentlyContinue)) {
    throw 'The any-registered CDP identity helper is missing from common-windows.ps1.'
  }

  $rendererSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'assets\renderer-inject.js')
  foreach ($requiredRendererBehavior in @(
    'adoptedStyleSheets', 'CSSStyleSheet', 'artMetadata', 'detectShellAppearance',
    'data-aurora-skin', 'window.navigation', 'selectorsSchema', 'codex-aurora-skin-selectors/1'
  )) {
    if (-not $rendererSource.Contains($requiredRendererBehavior)) {
      throw "Renderer adaptive behavior is missing: $requiredRendererBehavior"
    }
  }
  foreach ($forbiddenRendererBehavior in @(
    'getBoundingClientRect', 'ResizeObserver', 'childList', 'subtree',
    'classList.add', 'classList.remove', 'classList.toggle',
    'syncRouteState', 'samplingNativeShell', '.dream-home-utility'
  )) {
    if ($rendererSource.Contains($forbiddenRendererBehavior)) {
      throw "Unified renderer still contains retired behavior: $forbiddenRendererBehavior"
    }
  }
  $node = Get-AuroraSkinNodeRuntime
  $projectRoot = Split-Path -Parent $Root
  $syncToolPath = Join-Path $projectRoot 'tools\sync-runtime-assets.mjs'
  $syncToolResult = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @($syncToolPath, '--check')
  if ($syncToolResult.ExitCode -ne 0) { throw "Runtime contract tool failed: $syncToolPath" }
  $doctorToolPath = Join-Path $projectRoot 'tools\doctor-selectors.test.mjs'
  $doctorToolResult = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @($doctorToolPath)
  if ($doctorToolResult.ExitCode -ne 0) { throw "Runtime contract tool failed: $doctorToolPath" }
  $injectorSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\injector.mjs')
  foreach ($requiredInjectorBehavior in @(
    'MAX_ART_BYTES', 'createHash', 'readImageMetadata', '50MP safety limit', 'STRONG_THEME_AUDIT_MS',
    'Page.addScriptToEvaluateOnNewDocument', 'Page.removeScriptToEvaluateOnNewDocument', 'earlyPayloadFor'
  )) {
    if (-not $injectorSource.Contains($requiredInjectorBehavior)) {
      throw "Injector theme safety is missing: $requiredInjectorBehavior"
    }
  }
  $themeSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\theme-windows.ps1')
  foreach ($requiredThemeSafety in @(
    '[System.IO.FileAttributes]::ReparsePoint',
    'Ensure-AuroraSkinManagedDirectory',
    'Get-AuroraSkinValidatedImageMetadata',
    '16384px / 50MP safety limit',
    'Assert-AuroraSkinImageFile -Path $temporary',
    'Assert-AuroraSkinImageFile -Path $imageArchive'
  )) {
    if (-not $themeSource.Contains($requiredThemeSafety)) {
      throw "PowerShell theme-store safety is missing: $requiredThemeSafety"
    }
  }
  $commonSource = Read-AuroraSkinUtf8File -Path (Join-Path $Root 'scripts\common-windows.ps1')
  if (-not $commonSource.Contains('State was preserved.')) {
    throw 'Mismatched live injector identity does not fail closed with preserved state.'
  }

  $stderrProbe = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    '-e', "process.stderr.write('aurora-skin-stderr-probe\n'); process.exit(7)")
  if ($stderrProbe.ExitCode -ne 7 -or ($stderrProbe.Output -join "`n") -notmatch 'aurora-skin-stderr-probe') {
    throw "Native stderr was not captured with its real exit code under Stop preference: exit=$($stderrProbe.ExitCode); output=$($stderrProbe.Output -join '<NL>')"
  }
  $discardedProbe = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    '-e', "process.stderr.write('ignored-warning\n'); process.stdout.write('kept-output')") -DiscardStderr
  if ($discardedProbe.ExitCode -ne 0 -or ($discardedProbe.Output -join '') -cne 'kept-output') {
    throw 'Native stderr discard changed stdout or the real exit code.'
  }

  $selfTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--self-test')
  if ($selfTest.ExitCode -ne 0) { throw 'Injector CDP self-test failed.' }
  $payloadTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload', '--theme-dir',
    (Join-Path $projectRoot 'library\preset-red-white-abstract'))
  if ($payloadTest.ExitCode -ne 0) { throw 'Injector self-test failed.' }
  $managedPayloadTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload', '--theme-dir', $themePaths.Active)
  if ($managedPayloadTest.ExitCode -ne 0) { throw 'Managed theme payload validation failed.' }
  $oversizedPayloadTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload', '--theme-dir', $oversizedTheme)
  if ($oversizedPayloadTest.ExitCode -eq 0) { throw 'Node injector accepted an image over the 16 MB limit.' }
  $rendererTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'renderer-inject.test.mjs'))
  if ($rendererTest.ExitCode -ne 0) { throw 'Renderer auxiliary-window regression test failed.' }
  $bootstrapTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'injector-bootstrap.test.mjs'))
  if ($bootstrapTest.ExitCode -ne 0) { throw 'Injector early-bootstrap regression test failed.' }
  $oneShotTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'injector-one-shot.test.mjs'))
  if ($oneShotTest.ExitCode -ne 0) { throw 'Injector one-shot Browser ID regression test failed.' }
  $imageMetadataTest = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'image-metadata.test.mjs'))
  if ($imageMetadataTest.ExitCode -ne 0) { throw 'Image metadata regression test failed.' }

  Write-Host 'PASS: config transactions, restore scoping, state safety, argument quoting, and loopback CDP validation.'
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
