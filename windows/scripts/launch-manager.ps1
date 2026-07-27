[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexAuroraSkin'
$engine = Get-AuroraSkinRuntimeEnginePaths -StateRoot $StateRoot
$node = Get-AuroraSkinNodeRuntime
$arguments = @(
  $engine.Manager,
  '--platform', 'windows',
  '--engine-root', $engine.Root,
  '--state-root', $StateRoot,
  '--active-root', (Join-Path $StateRoot 'active-theme'),
  '--node', $node.Path,
  '--injector', (Join-Path $engine.Scripts 'injector.mjs'),
  '--start', $engine.Start,
  '--restore', $engine.Restore
)
$argumentLine = ($arguments | ForEach-Object {
  ConvertTo-AuroraSkinProcessArgument -Value "$_"
}) -join ' '
Start-Process -FilePath $node.Path -ArgumentList $argumentLine -WindowStyle Hidden | Out-Null
