<#
  Builds mica for Windows: tests, Native AOT app, single-file setup with the app embedded, SHA-256 file.

    windows/scripts/build.ps1                 # x64 Release
    windows/scripts/build.ps1 -Arch arm64
    windows/scripts/build.ps1 -SkipTests

  Output: windows/artifacts/mica-<version>-win-<arch>-setup.exe and .sha256 next to it.
  Needs the .NET 10 SDK and the Windows SDK build tools (pulled by NuGet). Python 3 for the shared checks.
#>
param(
  [ValidateSet('x64', 'arm64')] [string] $Arch = 'x64',
  [ValidateSet('Release', 'Debug')] [string] $Configuration = 'Release',
  [switch] $SkipTests
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$windows = Join-Path $root 'windows'
$artifacts = Join-Path $windows 'artifacts'
$version = (Get-Content (Join-Path $root 'shared\version.txt')).Trim()
$rid = "win-$Arch"
New-Item -ItemType Directory -Force $artifacts | Out-Null

python (Join-Path $root 'scripts\check-parity.py')
if ($LASTEXITCODE -ne 0) { throw 'shared parity checks failed' }

if (-not $SkipTests) {
  dotnet test (Join-Path $windows 'tests\Mica.Core.Tests\Mica.Core.Tests.csproj') -c $Configuration
  if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
}

$appOut = Join-Path $artifacts "app-$Arch"
if (Test-Path $appOut) { Remove-Item -Recurse -Force $appOut }
dotnet publish (Join-Path $windows 'src\Mica.App\Mica.App.csproj') -c $Configuration -r $rid -p:Platform=$Arch -o $appOut
if ($LASTEXITCODE -ne 0) { throw 'app publish failed' }
Get-ChildItem $appOut -Filter *.pdb -Recurse | Remove-Item -Force

$payload = Join-Path $artifacts "payload-$Arch.zip"
if (Test-Path $payload) { Remove-Item -Force $payload }
Compress-Archive -Path (Join-Path $appOut '*') -DestinationPath $payload -CompressionLevel Optimal

$setupOut = Join-Path $artifacts "setup-$Arch"
if (Test-Path $setupOut) { Remove-Item -Recurse -Force $setupOut }
dotnet publish (Join-Path $windows 'src\Mica.Setup\Mica.Setup.csproj') -c $Configuration -r $rid -p:Platform=$Arch -p:PayloadZip=$payload -o $setupOut
if ($LASTEXITCODE -ne 0) { throw 'setup publish failed' }

$name = "mica-$version-win-$Arch-setup.exe"
$setup = Join-Path $artifacts $name
Copy-Item (Join-Path $setupOut 'mica-setup.exe') $setup -Force
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path "$setup.sha256" -Value "$hash  $name" -NoNewline -Encoding ascii

$appSize = (Get-ChildItem $appOut -Recurse | Measure-Object Length -Sum).Sum
$setupSize = (Get-Item $setup).Length
Write-Host ("app folder: {0:N1} MB, setup: {1:N1} MB" -f ($appSize / 1MB), ($setupSize / 1MB))
Write-Host $setup
