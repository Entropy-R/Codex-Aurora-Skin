[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [switch]$PromptRestart,
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

$operationLock = Enter-AuroraSkinOperationLock
try {
  Assert-AuroraSkinPort -Port $Port
  if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
  $node = Get-AuroraSkinNodeRuntime
  $currentCodex = Get-AuroraSkinCodexInstall
  $codex = $currentCodex
  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'
  $themePaths = Get-AuroraSkinThemePaths -StateRoot $StateRoot
  Ensure-AuroraSkinManagedDirectory -Path $themePaths.Root -Root $themePaths.Root
  $StatePath = Join-Path $StateRoot 'state.json'
  $StdoutPath = Join-Path $StateRoot 'injector.log'
  $StderrPath = Join-Path $StateRoot 'injector-error.log'
  $VerifyPath = Join-Path $StateRoot 'verify.log'
  if (-not (Test-Path -LiteralPath $themePaths.Active -PathType Container)) {
    throw 'No active theme is available. Open Codex Aurora Skin once to initialize the offline library.'
  }
  $pauseWasSet = Test-AuroraSkinPaused -StateRoot $StateRoot

  $previousState = Read-AuroraSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-AuroraSkinPort -Port $savedPort
    $Port = $savedPort
  }
  $savedPathCandidate = Get-AuroraSkinCodexStatePathCandidate -State $previousState
  $savedCodex = Get-AuroraSkinCodexInstallFromState -State $previousState
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and
    (Test-AuroraSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-AuroraSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = (Get-AuroraSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-AuroraSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state was preserved.'
    }
  }

  $currentProcesses = Get-AuroraSkinCodexProcesses -Codex $currentCodex
  $codexToStop = $currentCodex
  $cdpIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $currentCodex
  if ($null -eq $cdpIdentity) {
    # After a Store auto-update the running (older) package still owns the
    # verified endpoint while Get-AuroraSkinCodexInstall already resolves to
    # the new one.  Adopt the running install instead of restarting it.
    $runningRegistered = Get-AuroraSkinVerifiedCdpIdentityForAnyRegistered -Port $Port
    if ($null -ne $runningRegistered) {
      $cdpIdentity = $runningRegistered.Identity
      $codex = $runningRegistered.Codex
      $codexToStop = $runningRegistered.Codex
    }
  }
  $savedIsDifferent = [bool]($null -ne $savedCodex -and
    -not (Test-AuroraSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  if ($savedIsDifferent) {
    $savedProcesses = Get-AuroraSkinCodexProcesses -Codex $savedCodex
    $savedOwnsPort = Test-AuroraSkinCodexPortOwner -Port $Port -Codex $savedCodex
    if ($currentProcesses.Count -gt 0 -and ($savedProcesses.Count -gt 0 -or $savedOwnsPort)) {
      throw 'Multiple registered Codex package versions are active. Close them manually before starting Aurora Skin.'
    }
    if ($savedProcesses.Count -gt 0 -or $savedOwnsPort) {
      if ($savedOwnsPort -and $savedProcesses.Count -eq 0) {
        throw 'The saved Codex listener is active but its process cannot be managed safely; state was preserved.'
      }
      $savedIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $codexToStop = $savedCodex
        $cdpIdentity = $savedIdentity
        Write-Warning 'Reapplying Aurora Skin to the still-running registered Codex version; the current Store version will be used after that app exits.'
      } else {
        $codexToStop = $savedCodex
        $currentProcesses = $savedProcesses
      }
    }
  }
  $debugReady = $null -ne $cdpIdentity
  $codexProcesses = if (Test-AuroraSkinPathEqual -Left $codexToStop.Executable -Right $currentCodex.Executable) {
    $currentProcesses
  } else {
    Get-AuroraSkinCodexProcesses -Codex $codexToStop
  }
  $closedExistingCodex = $false
  if (-not $debugReady -and $codexProcesses.Count -gt 0) {
    $restartAuthorized = [bool]$RestartExisting
    if (-not $restartAuthorized -and $PromptRestart) {
      $restartAuthorized = Confirm-AuroraSkinRestart -Message 'Codex must restart once to enable Aurora Skin. Unsaved input may be lost. Restart now?'
      if (-not $restartAuthorized) {
        Write-Host 'Aurora Skin launch was cancelled; Codex was not changed.'
        exit 0
      }
    }
    if (-not $restartAuthorized) {
      throw 'Codex is open without a verified Aurora Skin CDP endpoint. Close it first or explicitly use -RestartExisting.'
    }
    Stop-AuroraSkinCodex -Codex $codexToStop -AllowForce
    $closedExistingCodex = $true
    $codex = $currentCodex
  }

  $launchedWithCdp = $false
  $debugLaunchAttempted = $false
  $debugLaunch = $null
  $debugLaunchBaselineProcessIds = @()
  try {
    if ($null -eq (Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $codex)) {
      if (-not (Test-AuroraSkinPortAvailable -Port $Port)) {
        if ($PortExplicit) { throw "Port $Port is already occupied by an unverified listener. Choose another port." }
        $Port = Select-AuroraSkinPort -PreferredPort $Port
      }
      $arguments = @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
      if ($ProfilePath) {
        New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
        $arguments += "--user-data-dir=$ProfilePath"
      }
      $debugLaunchAttempted = $true
      $debugLaunchBaselineProcessIds = @(
        Get-AuroraSkinCodexProcesses -Codex $codex | ForEach-Object { [int]$_.ProcessId }
      )
      $debugLaunch = Start-AuroraSkinCodexForDebugging -Codex $codex -Arguments $arguments `
        -Port $Port -PreserveProcessIds $debugLaunchBaselineProcessIds
      $launchedWithCdp = $true
      if ($debugLaunch.Strategy -eq 'direct-store-executable') {
        Write-Warning 'Codex package activation did not preserve the CDP arguments; using the validated Store executable fallback for this session.'
      }
    }

    $deadline = (Get-Date).AddSeconds(45)
    $cdpIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    while ($null -eq $cdpIdentity) {
      $argumentStatus = Get-AuroraSkinCodexDebugArgumentStatus `
        -Processes @(Get-AuroraSkinCodexProcesses -Codex $codex) -Port $Port
      if ($argumentStatus -eq 'protocol-redirected') {
        throw "Codex $($codex.Version) converted the CDP argument into a codex:// navigation path instead of opening a debugging endpoint."
      }
      if ((Get-Date) -ge $deadline) {
        if ($null -ne $debugLaunch -and $debugLaunch.Strategy -eq 'direct-store-executable') {
          throw "The validated direct Store executable fallback did not expose a verified loopback CDP endpoint on port $Port within 45 seconds. Codex $($codex.Version) may disable CDP in this production runtime; no protected app files or permissions were changed."
        }
        throw "Codex did not expose a verified loopback CDP endpoint on port $Port within 45 seconds."
      }
      Start-Sleep -Milliseconds 400
      $cdpIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $codex
    }
  } catch {
    $launchError = $_
    if ($debugLaunchAttempted) {
      try {
        Stop-AuroraSkinCodex -Codex $codex `
          -PreserveProcessIds $debugLaunchBaselineProcessIds -AllowForce
      } catch {
        Write-Warning 'Launch rollback could not fully close the failed CDP session.'
      }
    }
    if (($closedExistingCodex -or $debugLaunchAttempted) -and
      (Get-AuroraSkinCodexProcesses -Codex $codex).Count -eq 0) {
      if ($debugLaunchAttempted) {
        Write-Warning 'Aurora Skin launch failed; reopening Codex without a debugging port.'
      }
      try { $null = Start-AuroraSkinCodex -Codex $codex } catch {
        Write-Warning 'Launch rollback could not reopen Codex automatically.'
      }
    }
    throw $launchError
  }

  try {
    $recordedInjectorStopped = Stop-AuroraSkinRecordedInjector -State $previousState
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-AuroraSkinStateFile -Path $StatePath
      Write-Warning "Archived stale Aurora Skin state at $staleStatePath"
    }
  } catch {
    if ($launchedWithCdp) {
      try {
        Stop-AuroraSkinCodex -Codex $codex -AllowForce
        $null = Start-AuroraSkinCodex -Codex $codex
      } catch {
        Write-Warning 'State validation rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    throw
  }

  # Keep a paused, already-running watcher paused until all state checks and any
  # restart consent have succeeded.  A cancelled prompt must be side-effect free.
  Set-AuroraSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
  $pauseCleared = $true

  if ($ForegroundInjector) {
    try {
      Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
      Exit-AuroraSkinOperationLock -Mutex $operationLock
      $operationLock = $null
      & $node.Path $Injector --watch --port $Port --browser-id $cdpIdentity.BrowserId `
        --theme-dir $themePaths.Active --pause-file $themePaths.PauseFile
      $foregroundExitCode = $LASTEXITCODE
      if ($foregroundExitCode -ne 0 -and $pauseWasSet) {
        Set-AuroraSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null
      }
      exit $foregroundExitCode
    } catch {
      if ($pauseWasSet) {
        try { Set-AuroraSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null } catch {
          Write-Warning 'Foreground startup rollback could not restore the existing paused state.'
        }
      }
      throw
    }
  }

  $state = $null
  $daemon = $null
  try {
    $injectorArgs = @((ConvertTo-AuroraSkinProcessArgument -Value $Injector), '--watch', '--port', "$Port",
      '--browser-id', $cdpIdentity.BrowserId, '--theme-dir',
      (ConvertTo-AuroraSkinProcessArgument -Value $themePaths.Active), '--pause-file',
      (ConvertTo-AuroraSkinProcessArgument -Value $themePaths.PauseFile))
    $daemon = Start-Process -FilePath $node.Path -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Start-Sleep -Milliseconds 500
    if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }

    $injectorStartedAt = Get-AuroraSkinProcessStartedAt -ProcessId $daemon.Id
    if (-not $injectorStartedAt) { throw 'The injector process identity could not be recorded safely.' }
    $state = [pscustomobject]@{
      schemaVersion = 3
      platform = 'windows'
      port = $Port
      injectorPid = $daemon.Id
      injectorStartedAt = $injectorStartedAt
      injectorPath = $Injector
      nodePath = $node.Path
      nodeVersion = $node.Version
      codexExe = $codex.Executable
      codexPackageRoot = $codex.PackageRoot
      codexPackageFullName = $codex.PackageFullName
      codexPackageFamilyName = $codex.PackageFamilyName
      codexVersion = $codex.Version
      browserId = $cdpIdentity.BrowserId
      profilePath = $ProfilePath
      themeDir = $themePaths.Active
      pauseFile = $themePaths.PauseFile
      createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-AuroraSkinState -Path $StatePath -State $state

    # The one-shot verify races Codex's first paint: on a slow machine the
    # shell markers are not rendered yet when the daemon has barely started,
    # and a single early miss used to tear the whole startup down.  The
    # watcher keeps applying in the background, so retry until a deadline.
    $verifyDeadline = (Get-Date).AddSeconds(90)
    while ($true) {
      $verify = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
        $Injector, '--verify', '--port', "$Port",
        '--browser-id', $cdpIdentity.BrowserId, '--theme-dir', $themePaths.Active,
        '--timeout-ms', '30000')
      Write-AuroraSkinUtf8FileAtomically -Path $VerifyPath -Content (($verify.Output -join "`r`n") + "`r`n")
      if ($verify.ExitCode -eq 0) { break }
      if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }
      if ((Get-Date) -ge $verifyDeadline) { throw "Aurora Skin verification failed. See $VerifyPath" }
      Start-Sleep -Seconds 3
    }
  } catch {
    $startupError = $_
    # We own the daemon Process object, so stop it directly: the object is
    # immune to PID reuse, and identity re-validation cannot spuriously
    # refuse.  Slow machines also need more than a moment for teardown; a
    # premature "did not stop" here is what used to leave duelling watchers.
    $injectorStopped = $true
    if ($null -ne $daemon) {
      if (-not $daemon.HasExited) {
        try {
          Stop-Process -InputObject $daemon -Force -ErrorAction Stop
        } catch {
          Write-Warning 'The newly created injector could not be signalled during startup rollback.'
        }
      }
      [void]$daemon.WaitForExit(15000)
      $injectorStopped = $daemon.HasExited
      if (-not $injectorStopped) {
        Write-Warning "The rollback injector has not exited yet: PID $($daemon.Id). State was preserved so the next start can reconcile it."
      }
    }
    if ($injectorStopped -and -not $launchedWithCdp) {
      try {
        $rollbackIdentity = Get-AuroraSkinVerifiedCdpIdentity -Port $Port -Codex $codex
        if ($null -ne $rollbackIdentity -and $rollbackIdentity.BrowserId -ceq $cdpIdentity.BrowserId) {
          $removal = Invoke-AuroraSkinNative -FilePath $node.Path -ArgumentList @(
            $Injector, '--remove', '--port', "$Port",
            '--browser-id', $cdpIdentity.BrowserId, '--timeout-ms', '5000') -DiscardStderr
          if ($removal.ExitCode -ne 0) { throw 'Injector removal returned a failure status.' }
        }
      } catch {
        Write-Warning 'Startup rollback could not remove the partially applied live skin; reload or close Codex to clear it.'
      }
    }
    if ($injectorStopped) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
    if ($launchedWithCdp) {
      try {
        Stop-AuroraSkinCodex -Codex $codex -AllowForce
        $null = Start-AuroraSkinCodex -Codex $codex
      } catch {
        Write-Warning 'Startup rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    if ($pauseWasSet -and $pauseCleared) {
      try {
        Set-AuroraSkinPaused -Paused $true -StateRoot $StateRoot | Out-Null
      } catch {
        Write-Warning 'Startup rollback could not restore the existing paused state.'
      }
    }
    throw $startupError
  }

  Write-Host "Codex Aurora Skin is active on verified loopback port $Port."
} finally {
  if ($null -ne $operationLock) { Exit-AuroraSkinOperationLock -Mutex $operationLock }
}
