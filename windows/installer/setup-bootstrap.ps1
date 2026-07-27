[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$LaunchManager,
  [switch]$Uninstall,
  [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$payloadRoot = Join-Path $PSScriptRoot 'payload'
$payloadScripts = Join-Path $payloadRoot 'scripts'
$commonPath = Join-Path $payloadScripts 'common-windows.ps1'
$themePath = Join-Path $payloadScripts 'theme-windows.ps1'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'

function Show-AuroraSkinBootstrapMessage {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('Info', 'Error')][string]$Kind = 'Info'
  )
  if ($Silent) { return }
  Add-Type -AssemblyName System.Windows.Forms
  $icon = if ($Kind -eq 'Error') {
    [System.Windows.Forms.MessageBoxIcon]::Error
  } else {
    [System.Windows.Forms.MessageBoxIcon]::Information
  }
  [void][System.Windows.Forms.MessageBox]::Show(
    $Message,
    'Codex Aurora Skin',
    [System.Windows.Forms.MessageBoxButtons]::OK,
    $icon
  )
}

function Wait-AuroraSkinCodexClosedForSetup {
  while ($true) {
    $registered = @(Get-AuroraSkinRegisteredCodexInstalls)
    $running = @($registered | Where-Object { (Get-AuroraSkinCodexProcesses -Codex $_).Count -gt 0 })
    if ($running.Count -eq 0) { return }
    if ($Silent) { throw 'Close Codex before installing or updating Codex Aurora Skin.' }
    Add-Type -AssemblyName System.Windows.Forms
    $choice = [System.Windows.Forms.MessageBox]::Show(
      'Codex is currently running. Close it, then click Retry to continue setup.',
      'Codex Aurora Skin Setup',
      [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
      [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($choice -ne [System.Windows.Forms.DialogResult]::Retry) {
      throw 'Setup was cancelled because Codex is still running.'
    }
  }
}

try {
  if ($Install -and ($LaunchManager -or $Uninstall)) {
    throw 'Choose exactly one installer bootstrap action.'
  }
  if (-not (Test-Path -LiteralPath $commonPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw 'The installer payload is incomplete.'
  }
  . $commonPath
  . $themePath

  $engine = Get-AuroraSkinRuntimeEnginePaths -StateRoot $stateRoot
  if ($Uninstall) {
    Stop-AuroraSkinManagerProcess -StateRoot $stateRoot -RequireStopped
    $restoreRequired = (Test-Path -LiteralPath $engine.Root -PathType Container) -or
      (Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-aurora-skin.toml') -PathType Leaf)
    if ($restoreRequired -and -not (Test-Path -LiteralPath $engine.Restore -PathType Leaf)) {
      throw 'The installed restore engine is missing. Reinstall Codex Aurora Skin, then uninstall again so Codex can be restored safely.'
    }
    if ($restoreRequired) {
      $restoreParameters = @{
        Uninstall = $true
        ForceRestart = $true
        NoRelaunch = $true
      }
      if (Test-Path -LiteralPath (Join-Path $stateRoot 'config.before-aurora-skin.toml') -PathType Leaf) {
        $restoreParameters.RestoreBaseTheme = $true
      }
      & $engine.Restore @restoreParameters
    }
    if (Test-Path -LiteralPath $engine.Root -PathType Container) {
      Remove-AuroraSkinRuntimeTree -Path $engine.Root -StateRoot $stateRoot
    }
    exit 0
  }

  $payloadNode = Join-Path $payloadRoot 'runtime\node\node.exe'
  $payloadNodeLicense = Join-Path $payloadRoot 'runtime\node\LICENSE'
  if (-not (Test-Path -LiteralPath $payloadNode -PathType Leaf) -or
    -not (Test-Path -LiteralPath $payloadNodeLicense -PathType Leaf)) {
    throw 'The installer payload is missing its bundled Node.js runtime. Re-download Setup.exe.'
  }
  $payloadVersion = ([System.IO.File]::ReadAllText((Join-Path $payloadRoot 'VERSION'))).Trim()
  if ($payloadVersion -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw "The installer payload version is invalid: $payloadVersion"
  }
  $installedVersion = if (Test-Path -LiteralPath $engine.Version -PathType Leaf) {
    ([System.IO.File]::ReadAllText($engine.Version)).Trim()
  } else { '' }
  if ($installedVersion -cmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' -and
    ([version]$installedVersion) -gt ([version]$payloadVersion)) {
    throw "A newer Codex Aurora Skin v$installedVersion is already installed. Download that version or newer instead of downgrading to v$payloadVersion."
  }
  $requiredEngineFiles = @(
    'VERSION',
    'assets\codex-aurora-skin.ico',
    'assets\aurora-skin.css',
    'assets\renderer-inject.js',
    'assets\selectors.json',
    'library\catalog.json',
    'library\integrity.json',
    'library\preset-red-white-abstract\theme.json',
    'manager\server.mjs',
    'manager\web\index.html',
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
  $missingEngineFiles = @($requiredEngineFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $engine.Root $_) -PathType Leaf)
  })
  $engineComplete = $missingEngineFiles.Count -eq 0
  $needsInstall = $Install -or $payloadVersion -cne $installedVersion -or
    -not $engineComplete

  if ($needsInstall) {
    Wait-AuroraSkinCodexClosedForSetup
    Stop-AuroraSkinManagerProcess -StateRoot $stateRoot -RequireStopped
    & (Join-Path $payloadScripts 'install-aurora-skin.ps1') -NoShortcuts
    $engine = Get-AuroraSkinRuntimeEnginePaths -StateRoot $stateRoot
    $committedVersion = if (Test-Path -LiteralPath $engine.Version -PathType Leaf) {
      ([System.IO.File]::ReadAllText($engine.Version)).Trim()
    } else { '' }
    $missingEngineFiles = @($requiredEngineFiles | Where-Object {
      -not (Test-Path -LiteralPath (Join-Path $engine.Root $_) -PathType Leaf)
    })
    if ($committedVersion -cne $payloadVersion -or $missingEngineFiles.Count -gt 0) {
      throw 'Runtime installation did not commit a complete managed engine.'
    }
  }

  if ($LaunchManager) {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $argumentLine = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' +
      (ConvertTo-AuroraSkinProcessArgument -Value $engine.LaunchManager)
    Start-Process -FilePath $powershell -ArgumentList $argumentLine -WindowStyle Hidden | Out-Null
  }
} catch {
  Show-AuroraSkinBootstrapMessage -Message $_.Exception.Message -Kind Error
  Write-Error $_
  exit 1
}
