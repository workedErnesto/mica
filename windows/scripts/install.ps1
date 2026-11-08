<#
  Development install on Windows, the counterpart of macos/scripts/install.sh: builds, closes a running mica through
  its normal path, installs quietly for the current user and starts mica again if it was open.
#>
param([ValidateSet('x64', 'arm64')] [string] $Arch = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }))
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build.ps1') -Arch $Arch
$version = (Get-Content (Join-Path $PSScriptRoot '..\..\shared\version.txt')).Trim()
$setup = Join-Path $PSScriptRoot "..\artifacts\mica-$version-win-$Arch-setup.exe"
$running = Get-Process mica -ErrorAction SilentlyContinue
foreach ($p in $running) { $null = $p.CloseMainWindow() }
if ($running) { $running | Wait-Process -Timeout 20 -ErrorAction SilentlyContinue }
if (Get-Process mica -ErrorAction SilentlyContinue) { throw 'mica did not quit, install stopped' }
Start-Process -FilePath $setup -ArgumentList '--quiet' -Wait
$exe = Join-Path $env:LOCALAPPDATA 'Programs\mica\mica.exe'
if (-not (Test-Path $exe)) { throw 'install failed: mica.exe is missing' }
if ($running) { Start-Process $exe }
Write-Host "installed $exe"
