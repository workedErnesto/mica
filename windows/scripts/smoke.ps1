<#
  Runs the installed or published mica with an isolated QA profile and prints the smoke report.
    windows/scripts/smoke.ps1 -Exe windows\artifacts\app-x64\mica.exe
#>
param([string] $Exe = (Join-Path $env:LOCALAPPDATA 'Programs\mica\mica.exe'), [int] $Timeout = 240)
$ErrorActionPreference = 'Stop'
$report = Join-Path $env:LOCALAPPDATA 'mica\QA\smoke-report.json'
if (Test-Path $report) { Remove-Item $report }
$process = Start-Process -FilePath $Exe -ArgumentList '--qa', '--smoke-test', '--exit-after-smoke' -PassThru
if (-not $process.WaitForExit($Timeout * 1000)) { $process.Kill(); throw "smoke test did not finish in $Timeout s" }
if (-not (Test-Path $report)) {
  $log = Join-Path $env:LOCALAPPDATA 'mica\QA\logs\errors.log'
  if (Test-Path $log) { Get-Content $log }
  Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-5)} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -in @('Application Error', '.NET Runtime', 'Windows Error Reporting') } |
    Select-Object -First 10 | Format-List TimeCreated, ProviderName, Message
  throw "smoke report missing, process exit code $($process.ExitCode)"
}
Get-Content $report
$data = Get-Content $report | ConvertFrom-Json
if ($data.failed -gt 0) { throw "$($data.failed) smoke checks failed" }
