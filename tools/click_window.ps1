# v1.12.39 dev helper: click inside the TaskFlow window at a position relative
# to the window's top-left corner, so a page switch can be driven without a
# human at the keyboard. Pairs with cap_window.ps1.
#
# v1.12.42: SAFETY FIRST. A blind SetForegroundWindow can fail (another app owns
# the foreground), and then the click lands on whatever is under those screen
# coordinates — which is exactly how this script once clicked into a running
# game. It now does the Alt + AttachThreadInput handshake and REFUSES to click
# unless TaskFlow is verifiably the foreground window.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\click_window.ps1 -X 60 -Y 300
param([int]$X = 0, [int]$Y = 0, [string]$Proc = "taskflow")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W2 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(IntPtr a, IntPtr b, bool f);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, int flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int dx, int dy, int d, int e);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
}
"@
$procs = Get-Process | Where-Object { $_.ProcessName -like "*$Proc*" -and $_.MainWindowHandle -ne 0 }
if (-not $procs) { Write-Output "no window"; exit 1 }
$h = ($procs | Select-Object -First 1).MainWindowHandle
if ([W2]::IsIconic($h)) { [void][W2]::ShowWindow($h, 9) }
[void][W2]::ShowWindow($h, 5)

$fg = [W2]::GetForegroundWindow()
$cur = [W2]::GetCurrentThreadId()
$fgTid = [W2]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
$tid = [W2]::GetWindowThreadProcessId($h, [IntPtr]::Zero)
[void][W2]::AttachThreadInput($cur, $fgTid, $true)
[void][W2]::AttachThreadInput($cur, $tid, $true)
[void][W2]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
[void][W2]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
[void][W2]::SetForegroundWindow($h)
[void][W2]::BringWindowToTop($h)
[void][W2]::AttachThreadInput($cur, $fgTid, $false)
[void][W2]::AttachThreadInput($cur, $tid, $false)
Start-Sleep -Milliseconds 400

if ([W2]::GetForegroundWindow() -ne $h) {
  Write-Output "ABORT: TaskFlow is not the foreground window - refusing to click blind"
  exit 2
}

$rc = New-Object W2+R
[void][W2]::GetWindowRect($h, [ref]$rc)
$abs = $rc.L + $X; $abo = $rc.T + $Y
[void][W2]::SetCursorPos($abs, $abo)
Start-Sleep -Milliseconds 200
[void][W2]::mouse_event(2, 0, 0, 0, 0)   # left down
[void][W2]::mouse_event(4, 0, 0, 0, 0)   # left up
Write-Output "click at window-relative ($X,$Y) -> screen ($abs,$abo)"
