<#
  Walks mica Setup the way a person does: real mouse clicks on "options", "install" and "close".
  Buttons are found by their accessible name, then clicked with SendInput at the centre of the button.
    windows/scripts/setup-click.ps1 -Setup windows\artifacts\mica-3.0.0-win-x64-setup.exe
#>
param([Parameter(Mandatory)] [string] $Setup, [int] $Timeout = 120, [string] $Report = (Join-Path $env:TEMP 'mica-setup-click'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
New-Item -ItemType Directory -Force $Report | Out-Null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    SetCursorPos(x + 1, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(80);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
[Mouse]::SetProcessDPIAware() | Out-Null
$root = [System.Windows.Automation.AutomationElement]::RootElement
$any = [System.Windows.Automation.Condition]::TrueCondition

function Find-Named($window, [string[]] $names, [int] $seconds = 20) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($element in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $any)) {
      $name = $element.Current.Name
      # Title bar caption buttons are Buttons named "Close"; mica's own controls are not, so they are skipped.
      if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { continue }
      if ($name -and ($names | Where-Object { $_ -ieq $name }) -and -not $element.Current.IsOffscreen) { return $element }
    }
    Start-Sleep -Milliseconds 300
  }
  throw "element not found: $($names -join ', ')"
}

function Show-State($window, [string] $label) {
  $file = Join-Path $Report "$label.png"
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  [System.Drawing.Graphics]::FromImage($bitmap).CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($file); $bitmap.Dispose()
  Write-Host "--- $label (screenshot $file)"
  if ($window) {
    foreach ($element in $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $any)) {
      $c = $element.Current
      if ($c.Name) { Write-Host ("  {0} '{1}' {2} offscreen={3}" -f $c.ControlType.ProgrammaticName, $c.Name, $c.BoundingRectangle, $c.IsOffscreen) }
    }
  }
}

function Click-Named($window, [string[]] $names) {
  $element = Find-Named $window $names
  Start-Sleep -Milliseconds 700 # let the appear animation settle
  $r = $element.Current.BoundingRectangle
  Write-Host "click '$($element.Current.Name)' at $([int]($r.X + $r.Width / 2)), $([int]($r.Y + $r.Height / 2))"
  [Mouse]::Click([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2))
  Start-Sleep -Milliseconds 1500
  Show-State $window "after-$($element.Current.Name)"
}

$exe = Join-Path $env:LOCALAPPDATA 'Programs\mica\mica.exe'
$process = Start-Process -FilePath $Setup -PassThru
try {
  $window = $null
  $deadline = (Get-Date).AddSeconds(60)
  while (-not $window -and (Get-Date) -lt $deadline) {
    $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
    if (-not $window) { Start-Sleep -Milliseconds 500 }
  }
  if (-not $window) { throw 'setup window did not appear' }
  [Mouse]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle) | Out-Null
  Start-Sleep -Seconds 2
  Show-State $window 'start'

  Click-Named $window @('параметры', 'options')
  Find-Named $window @('ярлык на рабочем столе', 'desktop shortcut') | Out-Null
  Write-Host 'options opened'

  Click-Named $window @('установить', 'обновить', 'install', 'update')
  Find-Named $window @('открыть mica', 'open mica') $Timeout | Out-Null
  Write-Host 'install finished'
  Click-Named $window @('закрыть', 'close')
  if (-not $process.WaitForExit($Timeout * 1000)) { throw 'setup did not close after the close button' }
  if (-not (Test-Path $exe)) { throw "mica.exe not installed at $exe" }
  Write-Host "installed by clicks: $exe"
}
catch {
  Show-State $window 'failure'
  throw
}
finally {
  if (-not $process.HasExited) { $process.Kill() }
}
