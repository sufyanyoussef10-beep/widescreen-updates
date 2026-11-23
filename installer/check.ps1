param([Parameter(Mandatory = $true)][string]$Setup, [Parameter(Mandatory = $true)][string]$Version, [Parameter(Mandatory = $true)][string]$Zip, [Parameter(Mandatory = $true)][string]$Out)
# The setup program of Widescreen, tried on a clean Windows machine (GitHub's), the way a person would:
#   1. installed without a question, everything in place, started, updated entry, refused while running, removed
#   2. the wizard itself, page by page, with a picture of every page (Next, Next, Install, Finish), then the uninstaller
# Prints PASS / FAIL lines, writes report.json and the pictures into -Out. Exit code 1 when something failed.
# (Windows PowerShell 5.1: it has the classes for pictures of the screen that this needs.)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$Setup = (Resolve-Path $Setup).Path; $Zip = (Resolve-Path $Zip).Path; $Out = (Resolve-Path $Out).Path
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$report = [ordered]@{ facts = [ordered]@{}; checks = New-Object System.Collections.ArrayList }
$script:bad = 0
function Note([string]$name, $ok, $detail) {
  $ok = [bool]$ok
  if (-not $ok) { $script:bad++ }
  [void]$report.checks.Add([ordered]@{ name = $name; ok = $ok; detail = $detail })
  $line = $(if ($ok) { 'PASS ' } else { 'FAIL ' }) + $name
  if (-not $ok -and $null -ne $detail) { $line += '  ' + ($detail | ConvertTo-Json -Compress -Depth 4) }
  Write-Host $line
}
function Fact([string]$k, $v) { $report.facts[$k] = $v; Write-Host ("  {0}: {1}" -f $k, $(if ($v -is [string]) { $v } else { $v | ConvertTo-Json -Compress -Depth 4 })) }
function Run([string]$file, [string]$arguments) {
  $p = if ($arguments) { Start-Process -FilePath $file -ArgumentList $arguments -PassThru } else { Start-Process -FilePath $file -PassThru }
  if (-not $p.WaitForExit(600000)) { try { $p.Kill() } catch { }; return -999 }
  return $p.ExitCode
}
function Safe([string]$name, [scriptblock]$body) { try { & $body } catch { Note $name $false ("the check itself broke: " + $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber) } }

$dir = Join-Path $env:LOCALAPPDATA 'Programs\Widescreen'
$exe = Join-Path $dir 'Widescreen.exe'
$unExe = Join-Path $dir 'Uninstall.exe'
$unKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Widescreen'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Widescreen.lnk'
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Widescreen.lnk'
$dataMark = Join-Path $env:LOCALAPPDATA 'Widescreen\kept-by-the-check.txt'
$shell = New-Object -ComObject WScript.Shell
Add-Type -AssemblyName System.IO.Compression.FileSystem, System.Drawing, System.Windows.Forms

function Stop-App {
  Get-CimInstance Win32_Process -Filter "Name='Widescreen.exe'" | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { } }
  Start-Sleep -Milliseconds 1500
}
function Gone([string]$path, [int]$seconds) { for ($i = 0; $i -lt $seconds * 2; $i++) { if (-not (Test-Path -LiteralPath $path)) { return $true }; Start-Sleep -Milliseconds 500 }; return -not (Test-Path -LiteralPath $path) }
function Installed-State {
  $k = if (Test-Path $unKey) { Get-ItemProperty $unKey } else { $null }
  $lnk = { param($f) if (Test-Path -LiteralPath $f) { $s = $shell.CreateShortcut($f); [ordered]@{ target = $s.TargetPath; startIn = $s.WorkingDirectory } } else { $null } }
  [ordered]@{
    exe = if (Test-Path $exe) { ((Get-Item $exe).VersionInfo.ProductVersion -replace '\+.*$', '') } else { $null }
    uninstaller = (Test-Path $unExe)
    listed = if ($k) { [ordered]@{ name = $k.DisplayName; version = $k.DisplayVersion; folder = $k.InstallLocation; remove = $k.UninstallString; quiet = $k.QuietUninstallString; icon = $k.DisplayIcon; publisher = $k.Publisher; sizeKB = $k.EstimatedSize } } else { $null }
    startMenu = (& $lnk $menu); desktop = (& $lnk $desk)
  }
}

# ---------------------------------------------------------------------------------------------- the machine, the file
Fact 'Windows' ((Get-CimInstance Win32_OperatingSystem).Caption + ' ' + [Environment]::OSVersion.Version)
Fact 'administrator' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$vi = (Get-Item $Setup).VersionInfo
Fact 'setup program' ([ordered]@{ megabytes = [math]::Round((Get-Item $Setup).Length / 1MB, 1); product = $vi.ProductName; version = $vi.ProductVersion; description = $vi.FileDescription; sha256 = (Get-FileHash $Setup -Algorithm SHA256).Hash.ToLowerInvariant() })
Note 'the setup program carries the name and the version of the app' ($vi.ProductName -eq 'Widescreen' -and $vi.ProductVersion -eq $Version) $vi.ProductVersion
Safe 'the icon of the setup program' {
  $bmp = [Drawing.Icon]::ExtractAssociatedIcon($Setup).ToBitmap(); $seen = @{}
  for ($y = 0; $y -lt $bmp.Height; $y++) { for ($x = 0; $x -lt $bmp.Width; $x++) { $c = $bmp.GetPixel($x, $y); if ($c.A -gt 200) { if ($c.R -gt 190 -and $c.G -lt 130 -and $c.B -lt 130) { $seen.red = 1 }; if ($c.B -gt 190 -and $c.R -lt 130) { $seen.blue = 1 }; if ($c.G -gt 180 -and $c.R -gt 150 -and $c.R -lt 215 -and $c.B -lt 160) { $seen.green = 1 } } } }
  $bmp.Save((Join-Path $Out 'icon-of-setup.png'), [Drawing.Imaging.ImageFormat]::Png)
  Note 'the setup program has the icon of the app (the red, green and blue frame)' ($seen.red -and $seen.green -and $seen.blue) (($seen.Keys | Sort-Object) -join ',')
}
$zipFiles = @{}
$z = [IO.Compression.ZipFile]::OpenRead($Zip)
foreach ($e in $z.Entries) { if (-not $e.FullName.EndsWith('/')) { $zipFiles[$e.FullName.Replace('/', '\')] = $e.Length } }
$z.Dispose()
Fact 'files of the app in the release' $zipFiles.Count

# a file in the app's data folder: it has to be there still when everything is over
New-Item -ItemType Directory -Force (Split-Path $dataMark) | Out-Null
Set-Content -LiteralPath $dataMark -Value 'the uninstaller must not touch this folder'

# ---------------------------------------------------------------------------------------------- 1. without a question
Safe 'a silent install' {
  Stop-App
  $code = Run $Setup '/S'
  $st = Installed-State
  Fact 'after the silent install' $st
  Note 'installed without a question: the setup program ends with success' ($code -eq 0) $code
  $missing = @($zipFiles.Keys | Where-Object { $p = Join-Path $dir $_; -not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -ne $zipFiles[$_] })
  Note ("every file of the app is in place (" + $zipFiles.Count + " files), with the uninstaller") ($missing.Count -eq 0 -and $st.uninstaller -and $st.exe -eq $Version) ([ordered]@{ missing = @($missing | Select-Object -First 5); exe = $st.exe; uninstaller = $st.uninstaller })
  $l = $st.listed
  Note 'it is listed under "Installed apps" with name, version, folder, icon and how to remove it' ($l -and $l.name -eq 'Widescreen' -and $l.version -eq $Version -and $l.folder -eq $dir -and $l.remove -eq ('"' + $unExe + '"') -and $l.icon -eq $exe -and $l.sizeKB -gt 50000) $l
  Note 'the Start menu and the desktop each have a shortcut that starts the app in its folder' ($st.startMenu -and $st.startMenu.target -eq $exe -and $st.startMenu.startIn -eq $dir -and $st.desktop -and $st.desktop.target -eq $exe) ([ordered]@{ startMenu = $st.startMenu; desktop = $st.desktop })
}

Safe 'a folder with other files' {
  $other = 'C:\ws-other-things'
  New-Item -ItemType Directory -Force $other | Out-Null
  Set-Content -LiteralPath (Join-Path $other 'mine.txt') -Value 'not Widescreen'
  $code = Run $Setup ('/S /D=' + $other)
  $left = @(Get-ChildItem -LiteralPath $other -Force | ForEach-Object { $_.Name })
  Note 'a folder that already holds other files is refused, and nothing is put into it' ($code -ne 0 -and $left.Count -eq 1 -and $left[0] -eq 'mine.txt') ([ordered]@{ exit = $code; holds = $left })
  $fresh = 'C:\ws own folder\Widescreen'
  $code2 = Run $Setup ('/S /D=' + $fresh)
  $ok2 = (Test-Path -LiteralPath (Join-Path $fresh 'Widescreen.exe')) -and (Test-Path -LiteralPath (Join-Path $fresh 'Uninstall.exe'))
  Note 'a new folder of one''s own choice works (also with a blank in its name)' ($code2 -eq 0 -and $ok2) ([ordered]@{ exit = $code2; installed = $ok2 })
  # ... and back to the proposed folder, for the rest of the check; the copy in the chosen folder is removed by its own uninstaller
  if ($ok2) {
    $p = Start-Process -FilePath (Join-Path $fresh 'Uninstall.exe') -ArgumentList '/S' -PassThru; [void]$p.WaitForExit(60000)
    Note 'its uninstaller removes that folder' (Gone $fresh 40) (Test-Path -LiteralPath $fresh)
  }
  $code3 = Run $Setup '/S'
  Note 'installing again over an existing copy works' ($code3 -eq 0 -and (Installed-State).listed.folder -eq $dir) $code3
}

# ---------------------------------------------------------------------------------------------- the app itself, started
$engine = $null
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') { if (Test-Path $k) { $pv = (Get-ItemProperty $k).pv; if ($pv -and $pv -ne '0.0.0.0') { $engine = $pv } } }
Fact 'WebView2 Runtime on this machine' $(if ($engine) { $engine } else { 'not there' })
if (-not $engine) {
  Safe 'the WebView2 Runtime' {
    $boot = Join-Path $Out 'MicrosoftEdgeWebview2Setup.exe'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $boot -UseBasicParsing
    $code = Run $boot '/silent /install'
    Remove-Item -LiteralPath $boot -Force
    Fact 'WebView2 Runtime installed for the check' $code
  }
}
Safe 'the installed app' {
  Stop-App
  Set-ItemProperty $unKey -Name DisplayVersion -Value '0.0.1'            # as after an update through the Update button: the entry is behind
  $data = Join-Path $Out 'appdata'
  $app = Start-Process -FilePath $exe -ArgumentList ('--devtools-port=9470 "--data-dir=' + $data + '"') -PassThru
  $node = Start-Process -FilePath 'node' -ArgumentList ('"' + (Join-Path $here 'win-check.mjs') + '" "' + $dir + '" "' + $Version + '" "' + $Out + '"') -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Out 'app-check.txt') -RedirectStandardError (Join-Path $Out 'app-check-errors.txt')
  [void]$node.WaitForExit(240000)
  $lines = @(Get-Content -LiteralPath (Join-Path $Out 'app-check.txt') -ErrorAction SilentlyContinue)
  foreach ($l in $lines) { Write-Host $l; if ($l -like 'PASS *') { [void]$report.checks.Add([ordered]@{ name = $l.Substring(5); ok = $true; detail = $null }) } elseif ($l -like 'FAIL *') { $script:bad++; [void]$report.checks.Add([ordered]@{ name = $l.Substring(5); ok = $false; detail = $null }) } }
  Note 'the check of the started app ran to its end' ($node.HasExited -and @($lines | Where-Object { $_ -like 'passed *' }).Count -eq 1) ([ordered]@{ exit = $(if ($node.HasExited) { $node.ExitCode } else { 'still running' }); errors = (Get-Content -LiteralPath (Join-Path $Out 'app-check-errors.txt') -Raw -ErrorAction SilentlyContinue) })
  $listed = (Get-ItemProperty $unKey).DisplayVersion
  Note 'an entry under "Installed apps" that is behind is set to the version that runs' ($listed -eq $Version) $listed
  # while it runs, nothing may be changed under it
  $held = $false; $m = $null
  try { $held = [Threading.Mutex]::TryOpenExisting('Widescreen.Running', [ref]$m) } catch { }
  if ($m) { $m.Dispose() }
  $code = Run $Setup '/S'
  $codeUn = Run $unExe ('/S _?=' + $dir)
  Note 'while Widescreen runs, the setup program and the uninstaller both refuse and change nothing' ($held -and $code -ne 0 -and $codeUn -ne 0 -and (Test-Path $exe) -and -not $app.HasExited) ([ordered]@{ nameHeld = $held; setup = $code; uninstaller = $codeUn; stillRunning = (-not $app.HasExited) })
  Stop-App
}

Safe 'a silent removal' {
  Stop-App
  $p = Start-Process -FilePath $unExe -ArgumentList '/S' -PassThru; [void]$p.WaitForExit(60000)
  $gone = Gone $dir 60
  $st = Installed-State
  Note 'removed without a question: the folder, the entry under "Installed apps" and both shortcuts are gone' ($gone -and -not $st.listed -and -not $st.startMenu -and -not $st.desktop) $st
  Note 'what the app keeps for the person (its data folder) is untouched' (Test-Path -LiteralPath $dataMark) $dataMark
}

# ---------------------------------------------------------------------------------------------- 2. the wizard, page by page
# The wizard is read and pressed with plain window calls (its buttons have fixed numbers: 1 is Next / Install /
# Finish / Close / Uninstall, 2 is Cancel, 3 is Back), so it need not be in front and no key is typed.
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Wiz {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, int m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  static string Text(IntPtr h) { var s = new StringBuilder(2048); GetWindowText(h, s, 2048); return s.ToString(); }
  static string Class(IntPtr h) { var s = new StringBuilder(128); GetClassName(h, s, 128); return s.ToString(); }
  public static IntPtr Find(string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { if (IsWindowVisible(h) && Class(h) == "#32770" && Text(h).Trim() == title) { found = h; return false; }      // (the uninstaller's title ends in a blank) return true; }, IntPtr.Zero);
    return found;
  }
  /// Every control that is shown:  kind | number | on or off | what is written on it
  public static string[] Controls(IntPtr win) {
    var list = new List<string>();
    EnumChildWindows(win, (h, l) => {
      if (!IsWindowVisible(h)) return true;
      string c = Class(h), t = Text(h);
      if (c == "Edit") { var s = new StringBuilder(2048); SendMessage(h, 0x000D, (IntPtr)2048, s); t = s.ToString(); }
      list.Add(c + "|" + GetDlgCtrlID(h) + "|" + (IsWindowEnabled(h) ? "on" : "off") + "|" + t.Replace("\r", " ").Replace("\n", " "));
      return true; }, IntPtr.Zero);
    return list.ToArray();
  }
  static IntPtr MainButton(IntPtr win, int id) {
    IntPtr btn = IntPtr.Zero;
    EnumChildWindows(win, (h, l) => { if (GetParent(h) == win && GetDlgCtrlID(h) == id && Class(h) == "Button") { btn = h; return false; } return true; }, IntPtr.Zero);
    return btn;
  }
  /// What is written on one of the wizard's own buttons ("" when it is not there or switched off).
  public static string Button(IntPtr win, int id) {
    IntPtr b = MainButton(win, id);
    return b != IntPtr.Zero && IsWindowVisible(b) && IsWindowEnabled(b) ? Text(b).Replace("&", "") : "";
  }
  public static bool Press(IntPtr win, int id) {
    IntPtr b = MainButton(win, id);
    if (b == IntPtr.Zero || !IsWindowVisible(b) || !IsWindowEnabled(b)) return false;
    return PostMessage(win, 0x0111, (IntPtr)id, b);            // WM_COMMAND: the button was clicked
  }
  /// Every window that is shown on the desktop: its kind and its title (to see what came up instead of what was expected).
  public static string[] Titles() {
    var list = new List<string>();
    EnumWindows((h, l) => { if (IsWindowVisible(h)) { string t = Text(h); if (t.Length > 0) list.Add(Class(h) + " | " + t); } return true; }, IntPtr.Zero);
    return list.ToArray();
  }
  public static int[] Rect(IntPtr h) { RECT r; GetWindowRect(h, out r); return new[] { r.l, r.t, r.r - r.l, r.b - r.t }; }
  public static void Front(IntPtr h) { SetForegroundWindow(h); }
  public static bool There(IntPtr h) { return IsWindowVisible(h); }
}
'@
function Find-Wizard([string]$title, [int]$seconds) {
  for ($i = 0; $i -lt $seconds * 3; $i++) { $h = [Wiz]::Find($title); if ($h -ne [IntPtr]::Zero) { return $h }; Start-Sleep -Milliseconds 330 }
  return [IntPtr]::Zero
}
function Wait-Main($win, [string]$text, [int]$seconds) { for ($i = 0; $i -lt $seconds * 2; $i++) { if ([Wiz]::Button($win, 1) -like ($text + '*')) { return $true }; Start-Sleep -Milliseconds 500 }; return $false }
function Shot($win, [string]$name) {
  [Wiz]::Front($win)
  Start-Sleep -Milliseconds 700
  $r = [Wiz]::Rect($win)
  $bmp = New-Object System.Drawing.Bitmap $r[2], $r[3]
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r[0], $r[1], 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}
$pages = New-Object System.Collections.ArrayList
function Page($win, [string]$picture) {
  Shot $win $picture
  $c = @([Wiz]::Controls($win))
  $part = { param($kind) @($c | Where-Object { $_ -like ($kind + '|*') } | ForEach-Object { $x = $_ -split '\|', 4; (($x[3] -replace '&', '') -replace '\s+', ' ').Trim() + $(if ($x[2] -eq 'off') { ' (off)' } else { '' }) } | Where-Object { $_ -and $_ -ne '(off)' }) }
  $p = [ordered]@{ picture = $picture; words = (& $part 'Static'); buttons = (& $part 'Button'); fields = (& $part 'Edit'); lists = @($c | Where-Object { $_ -like 'SysTreeView32|*' }).Count }
  [void]$pages.Add($p); return $p
}

Safe 'the wizard' {
  Stop-App
  Start-Process -FilePath $Setup | Out-Null
  $w = Find-Wizard 'Widescreen Setup' 40
  if ($w -eq [IntPtr]::Zero) { Note 'the wizard opens' $false 'no window named "Widescreen Setup" came up'; return }
  $p1 = Page $w 'setup-1-welcome.png'
  Note 'page 1 welcomes: it names the app and its version, and has Next' ((($p1.words -join ' ') -like ('*Widescreen ' + $Version + '*')) -and ([Wiz]::Button($w, 1) -eq 'Next >')) $p1
  [void][Wiz]::Press($w, 1); Start-Sleep -Milliseconds 1000
  $p2 = Page $w 'setup-2-folder.png'
  Note 'page 2 asks for the folder and proposes the person''s own programs folder' (($p2.fields -contains $dir) -and ([Wiz]::Button($w, 1) -eq 'Next >') -and ([Wiz]::Button($w, 3) -eq '< Back')) $p2
  [void][Wiz]::Press($w, 1); Start-Sleep -Milliseconds 1000
  $p3 = Page $w 'setup-3-what-to-add.png'
  Note 'page 3 is the list of what to add (the shortcuts), and has Install' ($p3.lists -eq 1 -and ([Wiz]::Button($w, 1) -eq 'Install')) $p3
  [void][Wiz]::Press($w, 1); Start-Sleep -Milliseconds 400
  try { Shot $w 'setup-3b-installing.png' } catch { }
  $done = Wait-Main $w 'Finish' 240
  $p4 = Page $w 'setup-4-finished.png'
  Note 'the last page says it is installed, offers to start the app, and has Finish' ($done -and (($p4.words -join ' ') -like '*is installed*') -and ($p4.buttons -contains 'Start Widescreen now')) $p4
  $st = Installed-State
  Note 'what the wizard installed is all there: the app, the entry, both shortcuts' ($st.exe -eq $Version -and $st.listed -and $st.listed.version -eq $Version -and $st.startMenu -and $st.desktop) $st
  [void][Wiz]::Press($w, 1)
  $started = $false
  for ($i = 0; $i -lt 60 -and -not $started; $i++) { Start-Sleep -Milliseconds 500; $started = @(Get-CimInstance Win32_Process -Filter "Name='Widescreen.exe'" | Where-Object { $_.ExecutablePath -eq $exe }).Count -gt 0 }
  Note 'Finish starts Widescreen from where it was installed' $started $started
  if ($started) {
    Start-Sleep -Seconds 12
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size); $bmp.Save((Join-Path $Out 'screen-after-finish.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  }
  Stop-App
}

Safe 'the uninstaller' {
  Stop-App
  if (-not (Test-Path -LiteralPath $unExe)) { Note 'the uninstaller is there' $false $unExe; return }
  Start-Process -FilePath $unExe | Out-Null
  $w = Find-Wizard 'Widescreen Uninstall' 40
  if ($w -eq [IntPtr]::Zero) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size); $bmp.Save((Join-Path $Out 'screen-no-uninstaller.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
    Note 'the uninstaller opens' $false ([ordered]@{ wanted = 'Widescreen Uninstall'; windows = @([Wiz]::Titles()); programs = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(Au_|Un_|Uninstall|Widescreen)' } | ForEach-Object { $_.Name + ' ' + $_.CommandLine }) })
    return
  }
  $u1 = Page $w 'remove-1-ask.png'
  Note 'the uninstaller says what it removes and what it leaves, and has Uninstall' ((($u1.words -join ' ') -like '*are not touched*') -and ([Wiz]::Button($w, 1) -eq 'Uninstall')) $u1
  [void][Wiz]::Press($w, 1)
  $done = Wait-Main $w 'Close' 120
  [void](Page $w 'remove-2-done.png')
  [void][Wiz]::Press($w, 1)
  $gone = Gone $dir 60
  $st = Installed-State
  Note 'after it everything is gone again: the folder, the entry, both shortcuts' ($done -and $gone -and -not $st.listed -and -not $st.startMenu -and -not $st.desktop) $st
  Note 'and the data folder of the person is still there' (Test-Path -LiteralPath $dataMark) $dataMark
}

$report.pages = $pages
$passed = @($report.checks | Where-Object { $_.ok }).Count
Write-Host ("passed {0} of {1}" -f $passed, $report.checks.Count)
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Out 'report.json') -Encoding UTF8
exit $(if ($script:bad) { 1 } else { 0 })
