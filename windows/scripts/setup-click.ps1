<#
  Walks mica Setup the way a person does: real mouse clicks through options, back, install and close.
  Buttons are found by AutomationId and clicked with the system mouse at their centre, after checking that
  the point really belongs to the Setup window. A screenshot and the UI Automation tree are saved after each step.
    windows/scripts/setup-click.ps1 -Setup windows\artifacts\mica-3.0.1-win-x64-setup.exe
#>
param([Parameter(Mandatory)] [string] $Setup, [int] $Timeout = 120, [string] $Report = (Join-Path $env:TEMP 'mica-setup-click'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
New-Item -ItemType Directory -Force $Report | Out-Null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Desk {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  public static void Raise(IntPtr hwnd) { SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040); SetForegroundWindow(hwnd); }
  public static uint OwnerAt(int x, int y) {
    var top = GetAncestor(WindowFromPoint(new POINT { X = x, Y = y }), 2);
    uint pid; GetWindowThreadProcessId(top, out pid); return pid;
  }
  public static void Click(int x, int y) {
    SetCursorPos(x - 1, y); System.Threading.Thread.Sleep(150);
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(80);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
[Desk]::SetProcessDPIAware() | Out-Null
$automation = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]
$exe = Join-Path $env:LOCALAPPDATA 'Programs\mica\mica.exe'
$process = $null

function Get-Windows {
  $condition = New-Object System.Windows.Automation.PropertyCondition($automation::ProcessIdProperty, $process.Id)
  $automation::RootElement.FindAll($scope::Children, $condition)
}

function Find-Id([string] $id, [int] $seconds = 20) {
  $condition = New-Object System.Windows.Automation.PropertyCondition($automation::AutomationIdProperty, $id)
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($window in Get-Windows) {
      $element = $window.FindFirst($scope::Descendants, $condition)
      if ($element -and -not $element.Current.IsOffscreen) { return $element }
    }
    Start-Sleep -Milliseconds 300
  }
  throw "element not found: $id"
}

function Find-Name([string[]] $names, [int] $seconds = 10) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($window in Get-Windows) {
      foreach ($element in $window.FindAll($scope::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        $name = $element.Current.Name
        if ($name -and ($names | Where-Object { $_ -ieq $name }) -and -not $element.Current.IsOffscreen) { return $element }
      }
    }
    Start-Sleep -Milliseconds 300
  }
  throw "text not found: $($names -join ', ')"
}

function Save-State([string] $label) {
  $file = Join-Path $Report "$label.png"
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  [System.Drawing.Graphics]::FromImage($bitmap).CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($file); $bitmap.Dispose()
  Write-Host "--- $label"
  if (-not $process -or $process.HasExited) { return }
  foreach ($window in Get-Windows) {
    foreach ($element in $window.FindAll($scope::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
      $c = $element.Current
      if ($c.Name -or $c.AutomationId) { Write-Host ("  {0} id='{1}' '{2}' {3} offscreen={4}" -f $c.ControlType.ProgrammaticName, $c.AutomationId, $c.Name, $c.BoundingRectangle, $c.IsOffscreen) }
    }
  }
}

function Click-Id([string] $id) {
  $element = Find-Id $id
  Start-Sleep -Milliseconds 700 # the page slides in; click where it comes to rest
  $r = $element.Current.BoundingRectangle
  $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
  $owner = [Desk]::OwnerAt($x, $y)
  if ($owner -ne $process.Id) {
    $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName
    throw "another window covers Setup at $x, $y (process $owner $name)"
  }
  Write-Host "click $id at $x, $y"
  [Desk]::Click($x, $y)
  Start-Sleep -Milliseconds 1200
  Save-State "after-$id"
}

$process = Start-Process -FilePath $Setup -PassThru
try {
  Find-Id 'setup.install' 60 | Out-Null
  [Desk]::Raise([IntPtr](Get-Windows)[0].Current.NativeWindowHandle)
  Start-Sleep -Seconds 1
  Save-State 'start'

  Click-Id 'setup.options'
  Find-Name @('ярлык на рабочем столе', 'desktop shortcut') | Out-Null
  Find-Name @('сделать браузером по умолчанию', 'make the default browser') | Out-Null
  Click-Id 'setup.back'
  Click-Id 'setup.options'
  Click-Id 'setup.install'
  Find-Id 'setup.open' $Timeout | Out-Null
  Click-Id 'setup.close'
  if (-not $process.WaitForExit(30000)) { throw 'Setup did not close after the close button' }
  if (-not (Test-Path $exe)) { throw "mica.exe not installed at $exe" }
  Write-Host "installed by clicks: $exe"
}
catch {
  Save-State 'failure'
  throw
}
finally {
  if ($process -and -not $process.HasExited) { $process.Kill() }
}
