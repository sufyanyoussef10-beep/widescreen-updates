param([Parameter(Mandatory = $true)][string]$Setup, [Parameter(Mandatory = $true)][string]$Version, [Parameter(Mandatory = $true)][string]$Zip, [Parameter(Mandatory = $true)][string]$Out)
# The setup program of Widescreen, tried on a clean Windows machine (GitHub's), the way a person would:
#   1. installed without a question, everything in place, started, updated entry, refused while running, removed
#   2. the wizard itself, page by page, with a picture of every page (Next, Next, Install, Finish), then the uninstaller
# Prints PASS / FAIL lines, writes report.json and the pictures into -Out. Exit code 1 when something failed.
# (Windows PowerShell 5.1: it has the screen and UI automation classes this needs.)
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
Add-Type -AssemblyName System.IO.Compression.FileSystem, System.Drawing, System.Windows.Forms, UIAutomationClient, UIAutomationTypes

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
$auto = [System.Windows.Automation.AutomationElement]
function Find-Wizard([string]$title, [int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) {
    foreach ($w in $auto::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)) {
      try { if ($w.Current.Name -eq $title -and $w.Current.ClassName -eq '#32770') { return $w } } catch { }
    }
    Start-Sleep -Milliseconds 300
  }
  return $null
}
function Controls($win, $type) { $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($auto::ControlTypeProperty, $type))) }
function Words($win) { @(Controls $win ([System.Windows.Automation.ControlType]::Text) | ForEach-Object { try { if (-not $_.Current.IsOffscreen) { ($_.Current.Name -replace '\s+', ' ').Trim() } } catch { } } | Where-Object { $_ }) }
function Buttons($win) { @(Controls $win ([System.Windows.Automation.ControlType]::Button) | ForEach-Object { try { if (-not $_.Current.IsOffscreen) { [ordered]@{ name = ($_.Current.Name -replace '&', ''); enabled = $_.Current.IsEnabled; el = $_ } } } catch { } } | Where-Object { $_ }) }
function Press($win, [string]$starts) {
  foreach ($b in (Buttons $win)) { if ($b.name -like ($starts + '*') -and $b.enabled) { $b.el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $b.name } }
  return $null
}
function Wait-Button($win, [string]$starts, [int]$seconds) { for ($i = 0; $i -lt $seconds * 2; $i++) { foreach ($b in (Buttons $win)) { if ($b.name -like ($starts + '*') -and $b.enabled) { return $true } }; Start-Sleep -Milliseconds 500 }; return $false }
function Shot($win, [string]$name) {
  try { $win.SetFocus() } catch { }
  Start-Sleep -Milliseconds 700
  $r = $win.Current.BoundingRectangle
  $bmp = New-Object System.Drawing.Bitmap ([int]$r.Width), ([int]$r.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}
$pages = New-Object System.Collections.ArrayList
function Page($win, [string]$picture) {
  Shot $win $picture
  $p = [ordered]@{ picture = $picture; words = @(Words $win); buttons = @(Buttons $win | ForEach-Object { $_.name + $(if ($_.enabled) { '' } else { ' (off)' }) }) }
  [void]$pages.Add($p); return $p
}

Safe 'the wizard' {
  Stop-App
  Start-Process -FilePath $Setup | Out-Null
  $w = Find-Wizard 'Widescreen Setup' 40
  if (-not $w) { Note 'the wizard opens' $false 'no window named "Widescreen Setup" came up'; return }
  $p1 = Page $w 'setup-1-welcome.png'
  Note 'page 1 welcomes: it names the app and its version, and has Next' ((($p1.words -join ' ') -like ('*Widescreen ' + $Version + '*')) -and ($p1.buttons -contains 'Next >')) $p1
  [void](Press $w 'Next'); Start-Sleep -Milliseconds 900
  $p2 = Page $w 'setup-2-folder.png'
  $folder = @(Controls $w ([System.Windows.Automation.ControlType]::Edit) | ForEach-Object { try { $_.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { } } | Where-Object { $_ })
  Note 'page 2 asks for the folder and proposes the person''s own programs folder' ($folder -contains $dir -and ($p2.buttons -contains 'Next >')) ([ordered]@{ proposed = $folder; page = $p2 })
  [void](Press $w 'Next'); Start-Sleep -Milliseconds 900
  $p3 = Page $w 'setup-3-what-to-add.png'
  $boxes = @(Controls $w ([System.Windows.Automation.ControlType]::TreeItem) | ForEach-Object { $_.Current.Name }) + @(Controls $w ([System.Windows.Automation.ControlType]::CheckBox) | ForEach-Object { $_.Current.Name })
  Note 'page 3 offers the Start menu and the desktop shortcut, and has Install' ((($boxes -join '|') -like '*Start menu shortcut*') -and (($boxes -join '|') -like '*Desktop shortcut*') -and ($p3.buttons -contains 'Install')) ([ordered]@{ offered = $boxes; page = $p3 })
  [void](Press $w 'Install')
  $done = Wait-Button $w 'Finish' 240
  $p4 = Page $w 'setup-4-finished.png'
  $run = @(Controls $w ([System.Windows.Automation.ControlType]::CheckBox) | ForEach-Object { $_.Current.Name -replace '&', '' })
  Note 'the last page says it is installed, offers to start the app, and has Finish' ($done -and (($p4.words -join ' ') -like '*is installed*') -and ($run -contains 'Start Widescreen now')) ([ordered]@{ finished = $done; offered = $run; page = $p4 })
  $st = Installed-State
  Note 'what the wizard installed is all there: the app, the entry, both shortcuts' ($st.exe -eq $Version -and $st.listed -and $st.listed.version -eq $Version -and $st.startMenu -and $st.desktop) $st
  [void](Press $w 'Finish')
  $started = $false
  for ($i = 0; $i -lt 60 -and -not $started; $i++) { Start-Sleep -Milliseconds 500; $started = @(Get-CimInstance Win32_Process -Filter "Name='Widescreen.exe'" | Where-Object { $_.ExecutablePath -eq $exe }).Count -gt 0 }
  Note 'Finish starts Widescreen from where it was installed' $started $started
  if ($started) {
    Start-Sleep -Seconds 12
    $bmp = New-Object System.Drawing.Bitmap ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width), ([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size); $bmp.Save((Join-Path $Out 'screen-after-finish.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  }
  Stop-App
}

Safe 'the uninstaller' {
  Stop-App
  Start-Process -FilePath $unExe | Out-Null
  $w = Find-Wizard 'Widescreen Uninstall' 40
  if (-not $w) { Note 'the uninstaller opens' $false 'no window named "Widescreen Uninstall" came up'; return }
  $u1 = Page $w 'remove-1-ask.png'
  Note 'the uninstaller says what it removes and what it leaves, and has Uninstall' ((($u1.words -join ' ') -like '*are not touched*') -and ($u1.buttons -contains 'Uninstall')) $u1
  [void](Press $w 'Uninstall')
  $done = Wait-Button $w 'Close' 120
  [void](Page $w 'remove-2-done.png')
  [void](Press $w 'Close')
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
