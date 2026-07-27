[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

function Copy-AuroraSkinLegacyUserData {
  param([Parameter(Mandatory = $true)][string]$DestinationRoot)

  $legacyRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
  if (-not (Test-Path -LiteralPath $legacyRoot -PathType Container) -or
    (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
    return
  }

  $legacyStatePath = Join-Path $legacyRoot 'state.json'
  if (Test-Path -LiteralPath $legacyStatePath -PathType Leaf) {
    try {
      $legacyState = Get-Content -LiteralPath $legacyStatePath -Raw | ConvertFrom-Json
      $legacyPid = [int]$legacyState.injectorPid
      if ($legacyPid -gt 0) {
        $legacyProcess = Get-Process -Id $legacyPid -ErrorAction SilentlyContinue
        if ($null -ne $legacyProcess) {
          throw 'The legacy Codex Dream Skin injector is still running. Restore and close it before migrating to Codex Aurora Skin.'
        }
      }
    } catch {
      if ($_.Exception.Message -like 'The legacy Codex Dream Skin injector*') { throw }
      Write-Warning "Legacy runtime state could not be inspected; only passive user data will be considered: $($_.Exception.Message)"
    }
  }

  $reparsePoint = Get-ChildItem -LiteralPath $legacyRoot -Recurse -Force -ErrorAction Stop |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } |
    Select-Object -First 1
  if ($null -ne $reparsePoint) {
    throw "Legacy theme data contains a reparse point and cannot be migrated safely: $($reparsePoint.FullName)"
  }

  New-Item -ItemType Directory -Path $DestinationRoot | Out-Null
  foreach ($directoryName in @('active-theme', 'themes', 'images')) {
    $source = Join-Path $legacyRoot $directoryName
    $destination = Join-Path $DestinationRoot $directoryName
    if ((Test-Path -LiteralPath $source -PathType Container) -and
      -not (Test-Path -LiteralPath $destination)) {
      Copy-Item -LiteralPath $source -Destination $destination -Recurse
    }
  }
  foreach ($fileName in @('overrides.json')) {
    $source = Join-Path $legacyRoot $fileName
    $destination = Join-Path $DestinationRoot $fileName
    if ((Test-Path -LiteralPath $source -PathType Leaf) -and
      -not (Test-Path -LiteralPath $destination)) {
      Copy-Item -LiteralPath $source -Destination $destination
    }
  }

  # 旧备份必须改用新品牌文件名，否则 Aurora 恢复会把旧皮肤状态当成官方基线。
  foreach ($backupName in @(
    @{ Source = 'config.before-dream-skin.toml'; Destination = 'config.before-aurora-skin.toml' },
    @{ Source = 'config.before-dream-skin.toml.appearance.json'; Destination = 'config.before-aurora-skin.toml.appearance.json' }
  )) {
    $source = Join-Path $legacyRoot $backupName.Source
    $destination = Join-Path $DestinationRoot $backupName.Destination
    if ((Test-Path -LiteralPath $source -PathType Leaf) -and
      -not (Test-Path -LiteralPath $destination)) {
      Copy-Item -LiteralPath $source -Destination $destination
    }
  }
}

$operationLock = Enter-AuroraSkinOperationLock
try {
  Assert-AuroraSkinPort -Port $Port
  $null = Get-AuroraSkinNodeRuntime
  $registeredInstalls = @(Get-AuroraSkinRegisteredCodexInstalls)
  if ($registeredInstalls.Count -eq 0) {
    throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.'
  }
  foreach ($registeredCodex in $registeredInstalls) {
    if ((Get-AuroraSkinCodexProcesses -Codex $registeredCodex).Count -gt 0) {
      throw 'Close Codex before installing Aurora Skin so the runtime can be upgraded safely.'
    }
  }

  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'
  Copy-AuroraSkinLegacyUserData -DestinationRoot $StateRoot
  $themePaths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $themePaths.Root -Root $themePaths.Root
  $StatePath = Join-Path $StateRoot 'state.json'
  $existingState = Read-AuroraSkinState -Path $StatePath
  $savedPathCandidate = Get-AuroraSkinCodexStatePathCandidate -State $existingState
  $savedCodex = Resolve-AuroraSkinCodexInstallFromState -State $existingState -RegisteredInstalls $registeredInstalls
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and
    (Get-AuroraSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0) {
    throw 'The saved Codex path is still running but no longer matches a registered Store package. Close it manually before installing.'
  }
  $engine = Install-AuroraSkinRuntimeEngine -SkillRoot $SkillRoot -StateRoot $StateRoot
  $legacyBackup = Join-Path $StateRoot 'config.before-aurora-skin.toml'
  if (Test-Path -LiteralPath $legacyBackup -PathType Leaf) {
    $archive = Join-Path $StateRoot 'config.before-aurora-skin.archived.toml'
    if (Test-Path -LiteralPath $archive) {
      $archive = Join-Path $StateRoot (
        'config.before-aurora-skin.archived.' + (Get-Date -Format 'yyyyMMddHHmmss') + '.toml'
      )
    }
    try {
      $null = Move-AuroraSkinLegacyConfigToOfficialDefaults `
        -ConfigPath (Join-Path $HOME '.codex\config.toml') `
        -BackupPath $legacyBackup -ArchivePath $archive
    } catch {
      Write-Warning "Legacy Codex appearance settings were not migrated; the backup was preserved: $($_.Exception.Message)"
    }
  }

  if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startScript = $engine.LaunchManager
    $restoreScript = $engine.Restore
    $portArgument = if ($PortExplicit) { " -Port $Port" } else { '' }

    foreach ($folder in @($desktop, $startMenu)) {
      $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex Aurora Skin.lnk'))
      $shortcut.TargetPath = $powershell
      $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$startScript`""
      $shortcut.WorkingDirectory = $engine.Root
      $shortcut.Description = 'Launch the official Codex app with Codex Aurora Skin'
      $shortcut.Save()
    }

    $restore = $shell.CreateShortcut((Join-Path $desktop 'Codex Aurora Skin - Restore.lnk'))
    $restore.TargetPath = $powershell
    $restore.Arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`"$portArgument -RestoreBaseTheme -PromptRestart"
    $restore.WorkingDirectory = $engine.Root
    $restore.Description = 'Restore the official Codex appearance and close the CDP session'
    $restore.Save()

  }

  if ($NoShortcuts) {
    Write-Host "Codex Aurora Skin installed at $($engine.Root). Run $($engine.LaunchManager) to open it."
  } else {
    Write-Host 'Codex Aurora Skin installed. The launch shortcut asks before restarting an open Codex window.'
  }
} finally {
  Exit-AuroraSkinOperationLock -Mutex $operationLock
}
