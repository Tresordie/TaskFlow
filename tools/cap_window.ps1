# v1.12.35 dev helper: raise a window, grab its client rect and save a PNG so a
# visual change can be eyeballed without a human at the keyboard. The release
# build prints nothing, and widget tests cannot see overlap — this is what
# caught the KPI icon sitting on top of its own label.
#
# v1.12.42: two safety fixes learned the hard way, when another app held the
# foreground and the script screenshotted *that* window instead:
#   * the raise now uses the Alt-key + AttachThreadInput trick and then
#     VERIFIES the handle is really the foreground window;
#   * if it is not, the grab falls back to PrintWindow (renders the window into
#     a bitmap even while occluded) instead of CopyFromScreen, so a capture can
#     never be a picture of somebody else's app.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\cap_window.ps1
param([string]$Out = "$env:TEMP\taskflow-cap.png", [string]$Proc = "taskflow")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string a, string b);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowThreadProcessId(IntPtr h, IntPtr p);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(IntPtr a, IntPtr b, bool f);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, int flags, IntPtr extra);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, int flags);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
}
"@
$procs = Get-Process | Where-Object { $_.ProcessName -like "*$Proc*" -and $_.MainWindowHandle -ne 0 }
if (-not $procs) { Write-Output "no window"; exit 1 }
$p = $procs | Select-Object -First 1
$h = $p.MainWindowHandle
if ([W]::IsIconic($h)) { [void][W]::ShowWindow($h, 9) }
[void][W]::ShowWindow($h, 5)

# Foreground hand-off: Windows only lets the current foreground process give the
# right away, so poke it with an Alt press and bridge the input queues.
$fg = [W]::GetForegroundWindow()
$cur = [W]::GetCurrentThreadId()
$fgTid = [W]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
$tid = [W]::GetWindowThreadProcessId($h, [IntPtr]::Zero)
[void][W]::AttachThreadInput($cur, $fgTid, $true)
[void][W]::AttachThreadInput($cur, $tid, $true)
[void][W]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)   # alt down
[void][W]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)   # alt up
[void][W]::SetForegroundWindow($h)
[void][W]::BringWindowToTop($h)
[void][W]::AttachThreadInput($cur, $fgTid, $false)
[void][W]::AttachThreadInput($cur, $tid, $false)
Start-Sleep -Milliseconds 700

$rc = New-Object W+R
[void][W]::GetWindowRect($h, [ref]$rc)
$w = $rc.Rt - $rc.L; $ht = $rc.B - $rc.T
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
if ([W]::GetForegroundWindow() -eq $h) {
  $g.CopyFromScreen($rc.L, $rc.T, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
  $how = "screen"
} else {
  $g.Dispose()
  # Occluded: render the window itself. PW_RENDERFULLCONTENT (2) is what makes
  # DirectComposition / GPU-composited content (Flutter) come out.
  $g2 = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g2.GetHdc()
  [void][W]::PrintWindow($h, $hdc, 2)
  $g2.ReleaseHdc($hdc); $g2.Dispose()
  $how = "printwindow"
  Write-Output "WARN: not foreground (another app holds it) - used PrintWindow"
}
$bmp.Save($Out)
$g.Dispose(); $bmp.Dispose()
Write-Output "$Out ${w}x${ht} ($how)"
