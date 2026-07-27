[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-AuroraSkinOperationLock
$verifyExitCode = 1
try {
  $StatePath = Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin\state.json'
  $state = Read-AuroraSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
  Assert-AuroraSkinPort -Port $Port
  $node = Get-AuroraSkinNodeRuntime
  $currentCodex = Get-AuroraSkinCodexInstall
  $codex = $currentCodex
  $cdpIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $codex
  if ($null -eq $cdpIdentity -and $null -ne $state) {
    $savedCodex = Get-AuroraSkinCodexInstallFromState -State $state
    if ($null -ne $savedCodex -and
      -not (Test-AuroraSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable)) {
      $savedIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $cdpIdentity = $savedIdentity
      }
    }
  }
  if ($null -eq $cdpIdentity) {
    # A Store auto-update replaces the "current" package while an older
    # registered version still owns the verified endpoint.
    $runningRegistered = Get-AuroraSkinVerifiedCdpIdentityForAnyRegistered -Port $Port
    if ($null -ne $runningRegistered) {
      $codex = $runningRegistered.Codex
      $cdpIdentity = $runningRegistered.Identity
    }
  }
  if ($null -eq $cdpIdentity) {
    throw "No verified Codex CDP endpoint is active on loopback port $Port."
  }
  if ($null -ne $state -and $state.browserId -and "$($state.browserId)" -cne $cdpIdentity.BrowserId) {
    throw 'The active CDP browser does not match the saved Aurora Skin session; state was preserved.'
  }

  # Without an explicit --theme-dir the injector falls back to the engine's
  # bundled assets theme, so verification compares the live skin against the
  # wrong expected theme and never passes.  Always verify against the staged
  # active theme, exactly like the watcher applies it.
  $themePaths = Get-AuroraSkinThemePaths -StateRoot (Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin')
  $arguments = @($injector, '--verify', '--port', "$Port", '--browser-id', $cdpIdentity.BrowserId,
    '--theme-dir', $themePaths.Active, '--timeout-ms', '30000')
  if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
  & $node.Path @arguments
  $verifyExitCode = $LASTEXITCODE
} finally {
  Exit-AuroraSkinOperationLock -Mutex $operationLock
}
exit $verifyExitCode
