# v1.12.35 dev helper: raise a window, grab its client rect and save a PNG so a
# visual change can be eyeballed without a human at the keyboard. The release
# build prints nothing, and widget tests cannot see overlap — this is what
# caught the KPI icon sitting on top of its own label.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\cap_window.ps1
param([string]$Out = "$env:TEMP\taskflow-cap.png", [string]$Proc = "taskflow")
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string a, string b);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
}
"@
$procs = Get-Process | Where-Object { $_.ProcessName -like "*$Proc*" -and $_.MainWindowHandle -ne 0 }
if (-not $procs) { Write-Output "no window"; exit 1 }
$p = $procs | Select-Object -First 1
$h = $p.MainWindowHandle
[void][W]::ShowWindow($h, 9)
[void][W]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 700
$rc = New-Object W+R
[void][W]::GetWindowRect($h, [ref]$rc)
$w = $rc.Rt - $rc.L; $ht = $rc.B - $rc.T
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($rc.L, $rc.T, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
$bmp.Save($Out)
$g.Dispose(); $bmp.Dispose()
Write-Output "$Out ${w}x${ht}"
