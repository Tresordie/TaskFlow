# v1.12.39 dev helper: click inside the TaskFlow window at a position relative
# to the window's top-left corner, so a page switch can be driven without a
# human at the keyboard. Pairs with cap_window.ps1.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\click_window.ps1 -X 60 -Y 300
param([int]$X = 0, [int]$Y = 0, [string]$Proc = "taskflow")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W2 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int dx, int dy, int d, int e);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
}
"@
$procs = Get-Process | Where-Object { $_.ProcessName -like "*$Proc*" -and $_.MainWindowHandle -ne 0 }
if (-not $procs) { Write-Output "no window"; exit 1 }
$h = ($procs | Select-Object -First 1).MainWindowHandle
[void][W2]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 300
$rc = New-Object W2+R
[void][W2]::GetWindowRect($h, [ref]$rc)
$abs = $rc.L + $X; $abo = $rc.T + $Y
[void][W2]::SetCursorPos($abs, $abo)
Start-Sleep -Milliseconds 200
[void][W2]::mouse_event(2, 0, 0, 0, 0)   # left down
[void][W2]::mouse_event(4, 0, 0, 0, 0)   # left up
Write-Output "click at window-relative ($X,$Y) -> screen ($abs,$abo)"
