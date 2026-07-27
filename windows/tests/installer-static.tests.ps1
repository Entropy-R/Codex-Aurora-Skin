[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$installerRoot = Join-Path $windowsRoot 'installer'
$definitionPath = Join-Path $installerRoot 'codex-aurora-skin.iss'
$builderPath = Join-Path $installerRoot 'build-release.ps1'
$bootstrapPath = Join-Path $installerRoot 'setup-bootstrap.ps1'
$installPath = Join-Path $windowsRoot 'scripts\install-aurora-skin.ps1'
$launcherSourcePath = Join-Path $installerRoot 'manager-launcher.cs'
$manifestPath = Join-Path $installerRoot 'node-runtime.json'
$builderAst = $null

foreach ($scriptPath in @($builderPath, $bootstrapPath, $installPath)) {
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Required installer PowerShell does not exist: $scriptPath"
  }
  $tokens = $null
  $parseErrors = $null
  $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
  )
  if ($parseErrors.Count -gt 0) {
    throw "Installer PowerShell failed to parse: $scriptPath"
  }
  if ($scriptPath -ceq $builderPath) { $builderAst = $scriptAst }
}

$manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
if ("$($manifest.version)" -cne '22.23.1' -or
  "$($manifest.platform)" -cne 'win' -or
  "$($manifest.architecture)" -cne 'x64' -or
  "$($manifest.url)" -cne 'https://nodejs.org/dist/v22.23.1/node-v22.23.1-win-x64.zip' -or
  "$($manifest.sha256)" -cne '7df0bc9375723f4a86b3aa1b7cc73342423d9677a8df4538aca31a049e309c29' -or
  "$($manifest.nodeEntry)" -cne 'node-v22.23.1-win-x64/node.exe' -or
  "$($manifest.licenseEntry)" -cne 'node-v22.23.1-win-x64/LICENSE') {
  throw 'Pinned Node.js manifest is incomplete or changed unexpectedly.'
}

$definition = [System.IO.File]::ReadAllText($definitionPath)
$builder = [System.IO.File]::ReadAllText($builderPath)
$bootstrap = [System.IO.File]::ReadAllText($bootstrapPath)
$install = [System.IO.File]::ReadAllText($installPath)
$launcher = [System.IO.File]::ReadAllText($launcherSourcePath)
if ($definition.Contains('-ExecutionPolicy Bypass') -or
  $builder.Contains('-ExecutionPolicy Bypass') -or
  $bootstrap.Contains('-ExecutionPolicy Bypass') -or
  $install.Contains('-ExecutionPolicy Bypass')) {
  throw 'The installer layer must never bypass the PowerShell execution policy.'
}
if ($definition.Contains('ssPostInstall')) {
  throw 'Installer initialization must not rely on non-fatal ssPostInstall exceptions.'
}
foreach ($requiredDefinition in @(
  'PrivilegesRequired=lowest',
  'ArchitecturesAllowed=x64compatible',
  'OutputBaseFilename=CodexAuroraSkin-Setup-v{#AppVersion}',
  'Source: "{#StageRoot}\payload\*"',
  'DestDir: "{app}\payload"',
  'Filename: "{app}\CodexAuroraSkin.Launcher.exe"',
  'Flags: nowait postinstall skipifsilent',
  'english.ConfirmUninstall=Uninstall will close Codex',
  'Name: "chinesesimplified"; MessagesFile: "{#StageRoot}\languages\ChineseSimplified.isl"',
  'chinesesimplified.ConfirmUninstall=',
  '-ExecutionPolicy RemoteSigned',
  'procedure CurStepChanged(CurStep: TSetupStep);',
  "if CurStep <> ssInstall then",
  "ExtractTemporaryFiles('{tmp}\setup-bootstrap.ps1');",
  "ExtractTemporaryFiles('{tmp}\payload\*');",
  "RunBootstrap(TemporaryBootstrap, '-Install', WizardSilent, ExitCode)",
  "RaiseException('Codex Aurora Skin initialization could not be started.');",
  'procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);',
  'if CurUninstallStep <> usUninstall then',
  "RunBootstrap(ExpandConstant('{app}\setup-bootstrap.ps1'), '-Uninstall', True, ExitCode)",
  "'Codex Aurora Skin could not restore Codex (exit code ' +",
  "IntToStr(ExitCode) + '). No installed files were removed.'"
)) {
  if (-not $definition.Contains($requiredDefinition)) {
    throw "Inno Setup definition is missing a release safety contract: $requiredDefinition"
  }
}

$uninstallStepIndex = $definition.IndexOf(
  'if CurUninstallStep <> usUninstall then',
  [System.StringComparison]::Ordinal
)
$runBootstrapIndex = $definition.IndexOf(
  "RunBootstrap(ExpandConstant('{app}\setup-bootstrap.ps1'), '-Uninstall', True, ExitCode)",
  [System.StringComparison]::Ordinal
)
$uninstallFailureIndex = $definition.LastIndexOf(
  "'Codex Aurora Skin could not restore Codex (exit code ' +",
  [System.StringComparison]::Ordinal
)
if ($uninstallStepIndex -lt 0 -or $runBootstrapIndex -le $uninstallStepIndex -or
  $uninstallFailureIndex -le $runBootstrapIndex -or
  $definition.Contains('function InitializeUninstall(): Boolean;')) {
  throw 'Uninstall restoration must run after confirmation and abort before file deletion on failure.'
}
if ($definition.Contains('Name: "startup"') -or $definition.Contains('{userstartup}')) {
  throw 'The installer must not create a login startup task or shortcut.'
}
$fileSources = [regex]::Matches($definition, '(?m)^Source: .*$')
if ($fileSources.Count -ne 7 -or
  -not $fileSources[0].Value.Contains('{#StageRoot}\setup-bootstrap.ps1') -or
  -not $fileSources[0].Value.Contains('Flags: dontcopy noencryption') -or
  -not $fileSources[1].Value.Contains('{#StageRoot}\payload\*') -or
  -not $fileSources[1].Value.Contains('Flags: dontcopy noencryption') -or
  -not $fileSources[2].Value.Contains('{#StageRoot}\setup-bootstrap.ps1') -or
  -not $fileSources[3].Value.Contains('{#StageRoot}\CodexAuroraSkin.Launcher.exe') -or
  -not $fileSources[4].Value.Contains('{#StageRoot}\LICENSE.txt') -or
  -not $fileSources[5].Value.Contains('{#StageRoot}\NOTICE.md') -or
  -not $fileSources[6].Value.Contains('{#StageRoot}\payload\*') -or
  $definition.Contains('[UninstallRun]')) {
  throw 'The installed app must contain the launcher, bootstrap, notices, and one managed-engine seed payload.'
}

foreach ($legacyMigrationContract in @(
  'config.before-dream-skin.toml',
  'config.before-aurora-skin.toml',
  'config.before-dream-skin.toml.appearance.json',
  'config.before-aurora-skin.toml.appearance.json'
)) {
  if (-not $install.Contains($legacyMigrationContract)) {
    throw "Windows legacy migration contract is missing: $legacyMigrationContract"
  }
}
if ($definition.Contains(
    'Name: "{group}\Codex Aurora Skin"; Filename: "{#PowerShellPath}"'
  ) -or
  -not $launcher.Contains('UseShellExecute = false') -or
  -not $launcher.Contains('CreateNoWindow = true') -or
  -not $launcher.Contains('WindowStyle = ProcessWindowStyle.Hidden') -or
  -not $launcher.Contains('process.WaitForExit()') -or
  -not $launcher.Contains('TryGetManagerUrl(sessionPath, out managerUrl)') -or
  -not $launcher.Contains('request.Proxy = null') -or
  -not $launcher.Contains('request.Headers[HttpRequestHeader.Authorization]') -or
  -not $launcher.Contains('UseShellExecute = true') -or
  -not $launcher.Contains('-ExecutionPolicy RemoteSigned') -or
  -not $launcher.Contains('-LaunchManager')) {
  throw 'The primary Start menu entry must use the no-console native launcher.'
}

foreach ($requiredBuilderContract in @(
  'Release versions differ:',
  'Get-FileHash -LiteralPath $archivePath -Algorithm SHA256',
  'Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256',
  '$checksumPath = "$artifactPath.sha256"',
  'Copy-ZipEntry -Archive $zip -EntryName "$($manifest.nodeEntry)"',
  'Copy-ZipEntry -Archive $zip -EntryName "$($manifest.licenseEntry)"',
  '$publicPresetImageSha256',
  '$publicPresetThemeSha256',
  '$innoChineseLanguageSha256',
  '$innoSetupLicenseSha256',
  'Copy-Item -LiteralPath $innoChineseLanguagePath',
  "'/target:winexe'",
  '$launcherSourcePath',
  '$launcherOutputPath',
  "'preset-red-white-abstract'",
  "'library\preset-red-white-abstract",
  '$stagedPublicThemeHash',
  'Staged installer payload did not retain the reviewed public release theme.',
  "'LICENSE.txt'",
  "'NOTICE.md'",
  "Write-AuroraSkinIcon -Path",
  '"CodexAuroraSkin-Setup-v$version.exe"'
)) {
  if (-not $builder.Contains($requiredBuilderContract)) {
    throw "Windows release builder is missing a required operation: $requiredBuilderContract"
  }
}

foreach ($requiredRepairContract in @(
  '[switch]$Install',
  '$needsInstall = $Install',
  '$requiredEngineFiles',
  'assets\codex-aurora-skin.ico',
  'library\preset-red-white-abstract\theme.json',
  'library\preset-red-white-abstract\theme.json',
  'manager\server.mjs',
  'scripts\launch-manager.ps1',
  'scripts\start-aurora-skin.ps1',
  'runtime\node\node.exe',
  'runtime\node\LICENSE',
  '$missingEngineFiles.Count -eq 0',
  'A newer Codex Aurora Skin',
  'The installer payload is missing its bundled Node.js runtime'
)) {
  if (-not $bootstrap.Contains($requiredRepairContract)) {
    throw "Installer same-version repair coverage is missing: $requiredRepairContract"
  }
}

foreach ($requiredUninstallBinding in @(
  '$restoreParameters = @{',
  'Uninstall = $true',
  'ForceRestart = $true',
  'NoRelaunch = $true',
  '$restoreParameters.RestoreBaseTheme = $true',
  '& $engine.Restore @restoreParameters'
)) {
  if (-not $bootstrap.Contains($requiredUninstallBinding)) {
    throw "Installer restore parameter binding is missing: $requiredUninstallBinding"
  }
}
if ($bootstrap.Contains('@restoreArguments')) {
  throw 'Installer restore switches must not use positional array splatting.'
}

$iconGenerator = $builderAst.Find({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -ceq 'Write-AuroraSkinIcon'
}, $true)
if ($null -eq $iconGenerator) { throw 'Windows release builder has no deterministic icon generator.' }
. ([scriptblock]::Create($iconGenerator.Extent.Text))
$iconTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
  'codex-aurora-skin-icon-test-' + [guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $iconTestRoot | Out-Null
try {
  $firstIcon = Join-Path $iconTestRoot 'first.ico'
  $secondIcon = Join-Path $iconTestRoot 'second.ico'
  Write-AuroraSkinIcon -Path $firstIcon
  Write-AuroraSkinIcon -Path $secondIcon
  if ((Get-FileHash -LiteralPath $firstIcon -Algorithm SHA256).Hash -cne
    (Get-FileHash -LiteralPath $secondIcon -Algorithm SHA256).Hash) {
    throw 'Generated Windows icon is not deterministic.'
  }

  $icon = [System.IO.File]::ReadAllBytes($firstIcon)
  $sizes = @(16, 24, 32, 48, 64, 256)
  if ($icon.Length -le 6 + (16 * $sizes.Count) -or
    [System.BitConverter]::ToUInt16($icon, 0) -ne 0 -or
    [System.BitConverter]::ToUInt16($icon, 2) -ne 1 -or
    [System.BitConverter]::ToUInt16($icon, 4) -ne $sizes.Count) {
    throw 'Generated Windows icon has an invalid ICO directory.'
  }
  for ($index = 0; $index -lt $sizes.Count; $index++) {
    $entryOffset = 6 + (16 * $index)
    $expectedDimensionByte = if ($sizes[$index] -eq 256) { 0 } else { $sizes[$index] }
    $imageLength = [System.BitConverter]::ToUInt32($icon, $entryOffset + 8)
    $imageOffset = [System.BitConverter]::ToUInt32($icon, $entryOffset + 12)
    if ($icon[$entryOffset] -ne $expectedDimensionByte -or
      $icon[$entryOffset + 1] -ne $expectedDimensionByte -or
      [System.BitConverter]::ToUInt16($icon, $entryOffset + 4) -ne 1 -or
      [System.BitConverter]::ToUInt16($icon, $entryOffset + 6) -ne 32 -or
      $imageLength -le 40 -or $imageOffset + $imageLength -gt $icon.Length -or
      [System.BitConverter]::ToUInt32($icon, $imageOffset) -ne 40 -or
      [System.BitConverter]::ToInt32($icon, $imageOffset + 4) -ne $sizes[$index] -or
      [System.BitConverter]::ToInt32($icon, $imageOffset + 8) -ne (2 * $sizes[$index])) {
      throw "Generated Windows icon contains an invalid $($sizes[$index])px image."
    }
  }
} finally {
  Remove-Item -LiteralPath $iconTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: Windows installer manifest, policy, bootstrap, uninstall, startup, and build contracts.'
