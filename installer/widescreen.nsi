; ======================================================================================================================
; Widescreen for Windows: the setup program.   Welcome > folder > what to add > Install > Finish
;
; Made by .github/workflows/windows.yml on a GitHub Windows machine, from the Widescreen.zip of a release:
;     makensis /DVERSION=1.9.7 /DSOURCE=<the unzipped app> /DOUT=<...>\Widescreen-Setup.exe installer\widescreen.nsi
;
; What it does, and why it is this way:
;  - It installs for the person who runs it (no administrator question), into a folder that Widescreen may change
;    itself (%LOCALAPPDATA%\Programs\Widescreen unless another one is chosen). That is what lets the green Update
;    button of the app put a new version in place.
;  - Start menu and desktop shortcut, an entry under "Installed apps" with an uninstaller.
;  - It never installs over, or removes, a copy that is running: it asks to close Widescreen first (the app holds
;    the name "Widescreen.Running" while it runs).
;  - The uninstaller removes the whole folder of the app. So the folder has to be Widescreen's own: Setup refuses
;    a folder that already holds other files, and the uninstaller only removes a folder that holds Widescreen.exe.
;    Compositions, settings and the copies Widescreen made of media are somewhere else and are never touched.
;  - Silent use, for checks:  Widescreen-Setup.exe /S [/D=folder]      Uninstall.exe /S
; ======================================================================================================================

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!ifndef VERSION
  !error "Give the version:  /DVERSION=1.2.3"
!endif
!ifndef SOURCE
  !error "Give the folder that holds the app:  /DSOURCE=folder"
!endif
!ifndef OUT
  !define OUT "Widescreen-Setup.exe"
!endif

!define APP "Widescreen"
!define EXE "Widescreen.exe"
!define UNKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"
!define RUNNING "Widescreen.Running"
!define PAGEURL "https://github.com/sufyanyoussef10-beep/widescreen-updates"
!define ENGINEKEY "SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
!define ENGINEURL "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

Name "${APP}"
OutFile "${OUT}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "Software\${APP}" "InstallDir"
BrandingText "${APP} ${VERSION}"
ShowInstDetails hide
ShowUninstDetails hide
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "FileDescription" "${APP} Setup"
VIAddVersionKey "CompanyName" "${APP}"
VIAddVersionKey "LegalCopyright" "${APP}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"
!include "x64.nsh"

Var NoEngine

; ---------------------------------------------------------------------------------------------------- the pages
!define MUI_ICON "widescreen.ico"
!define MUI_UNICON "widescreen.ico"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!define MUI_HEADERIMAGE_UNBITMAP "header.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "side.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "side.bmp"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC

!define MUI_WELCOMEPAGE_TITLE "Welcome to ${APP}"
!define MUI_WELCOMEPAGE_TEXT "This installs ${APP} ${VERSION} on this computer.$\r$\n$\r$\n${APP} plays videos, pictures, sound, slides, cameras and websites on LED screens, projectors and monitors.$\r$\n$\r$\nIt is installed for you, so Windows does not ask for an administrator.$\r$\n$\r$\nClick Next to continue."
!insertmacro MUI_PAGE_WELCOME

!define MUI_PAGE_CUSTOMFUNCTION_LEAVE DirLeave
!insertmacro MUI_PAGE_DIRECTORY

!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "${APP} is installed"
!define MUI_FINISHPAGE_TEXT_LARGE
!define MUI_FINISHPAGE_TEXT "${APP} ${VERSION} is on this computer. You find it in the Start menu.$\r$\n$\r$\nNew versions come by themselves: a green Update button then appears in ${APP}'s menu bar.$\r$\n$\r$\nClick Finish to close Setup."
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Start ${APP} now"
!insertmacro MUI_PAGE_FINISH

!define MUI_UNCONFIRMPAGE_TEXT_TOP "${APP} will be removed from this computer. Your compositions, your settings and the copies ${APP} made of your media are not touched."
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ---------------------------------------------------------------------------------------------------- checks
; Is a copy of Widescreen running? Then nothing is changed: its files are in use, and a show may be on.
!macro RunningCheck UN
Function ${UN}CheckRunning
  again:
    System::Call 'kernel32::OpenMutex(i 0x00100000, i 0, t "${RUNNING}") p .r0'
    ${If} $0 != 0
      System::Call 'kernel32::CloseHandle(p r0)'
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${APP} is running.$\r$\n$\r$\nClose it first (nothing is lost: it comes back with your composition), then click Retry." /SD IDCANCEL IDRETRY again
      SetErrorLevel 3
      Abort
    ${EndIf}
FunctionEnd
!macroend
!insertmacro RunningCheck ""
!insertmacro RunningCheck "un."

; The folder must be one of Widescreen's own (the uninstaller removes it whole), and one this person may write to
; (the Update button of the app changes the files in it).
Function CheckFolder
  ${If} ${FileExists} "$INSTDIR\${EXE}"
    Return                                      ; Widescreen is there already: this is its folder
  ${EndIf}
  ${DirState} "$INSTDIR" $0                     ; 0 empty, 1 holds something, -1 not there
  ${If} $0 == 1
    MessageBox MB_OK|MB_ICONEXCLAMATION "This folder already holds other files:$\r$\n$\r$\n$INSTDIR$\r$\n$\r$\nChoose an empty folder or a new one, for example by adding \${APP} at the end." /SD IDOK
    SetErrorLevel 5
    Abort
  ${EndIf}
  ClearErrors
  CreateDirectory "$INSTDIR"
  FileOpen $1 "$INSTDIR\widescreen-setup.tmp" w
  ${If} ${Errors}
    ${If} $0 == -1
      RMDir "$INSTDIR"
    ${EndIf}
    MessageBox MB_OK|MB_ICONEXCLAMATION "Windows does not let you write to this folder:$\r$\n$\r$\n$INSTDIR$\r$\n$\r$\nChoose a folder of your own; the one Setup proposed is a good one. ${APP} has to be able to change its own folder: that is how its Update button works." /SD IDOK
    SetErrorLevel 6
    Abort
  ${EndIf}
  FileClose $1
  Delete "$INSTDIR\widescreen-setup.tmp"
  ${If} $0 == -1
    RMDir "$INSTDIR"                            ; (made for the try only; it is made again when the files go in)
  ${EndIf}
FunctionEnd

Function DirLeave
  Call CheckFolder
FunctionEnd

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "${APP} needs a 64-bit Windows." /SD IDOK
    SetErrorLevel 4
    Abort
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "${APP} needs Windows 10 or Windows 11." /SD IDOK
    SetErrorLevel 4
    Abort
  ${EndIf}
  Call CheckRunning
FunctionEnd

Function un.onInit
  Call un.CheckRunning
FunctionEnd

; ---------------------------------------------------------------------------------------------------- installing
Section "${APP}" SecApp
  SectionIn RO
  Call CheckRunning                             ; (it may have been started while the pages were up)
  Call CheckFolder                              ; (a silent install has no folder page)
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "${SOURCE}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "Software\${APP}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNKEY}" "DisplayName" "${APP}"
  WriteRegStr HKCU "${UNKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNKEY}" "Publisher" "${APP}"
  WriteRegStr HKCU "${UNKEY}" "DisplayIcon" "$INSTDIR\${EXE}"
  WriteRegStr HKCU "${UNKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNKEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegStr HKCU "${UNKEY}" "URLInfoAbout" "${PAGEURL}"
  WriteRegDWORD HKCU "${UNKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNKEY}" "EstimatedSize" "$0"

  ; Widescreen shows its window with Microsoft's browser engine (WebView2). Windows 11 has it; a Windows 10 PC
  ; nearly always has it too. If not, say so now instead of leaving it to the first start.
  StrCpy $NoEngine 0
  ReadRegStr $0 HKLM "${ENGINEKEY}" "pv"
  ${If} $0 == ""
    ReadRegStr $0 HKCU "${ENGINEKEY}" "pv"
  ${EndIf}
  ${If} $0 == ""
  ${OrIf} $0 == "0.0.0.0"
    StrCpy $NoEngine 1
  ${EndIf}
SectionEnd

Section "Start menu shortcut" SecMenu
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
SectionEnd

Section "Desktop shortcut" SecDesk
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\${EXE}" "" "$INSTDIR\${EXE}" 0
SectionEnd

Section "-After"
  ${If} $NoEngine == 1
    MessageBox MB_YESNO|MB_ICONINFORMATION "${APP} is installed. To start, it needs Microsoft's WebView2 Runtime, which this PC does not have yet (Windows 11 has it built in).$\r$\n$\r$\nGet it from Microsoft now? It is a small download; run it, then start ${APP}." /SD IDNO IDNO skip
    ExecShell "open" "${ENGINEURL}"
    skip:
  ${EndIf}
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "The app itself, with what it needs to convert media."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMenu} "${APP} in the Start menu."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesk} "An icon for ${APP} on the desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; ---------------------------------------------------------------------------------------------------- removing
Section "Uninstall"
  SetShellVarContext current
  ; Only a folder that holds Widescreen is removed, and never a whole disk or a folder of Windows or of the person.
  ${If} ${FileExists} "$INSTDIR\${EXE}"
    StrLen $0 "$INSTDIR"
    ${If} $0 > 3
    ${AndIf} "$INSTDIR" != "$PROFILE"
    ${AndIf} "$INSTDIR" != "$DESKTOP"
    ${AndIf} "$INSTDIR" != "$DOCUMENTS"
    ${AndIf} "$INSTDIR" != "$LOCALAPPDATA"
    ${AndIf} "$INSTDIR" != "$APPDATA"
    ${AndIf} "$INSTDIR" != "$PROGRAMFILES"
    ${AndIf} "$INSTDIR" != "$PROGRAMFILES64"
    ${AndIf} "$INSTDIR" != "$WINDIR"
    ${AndIf} "$INSTDIR" != "$LOCALAPPDATA\Programs"
      RMDir /r "$INSTDIR"
    ${EndIf}
  ${EndIf}
  Delete "$SMPROGRAMS\${APP}.lnk"
  Delete "$DESKTOP\${APP}.lnk"
  DeleteRegKey HKCU "${UNKEY}"
  DeleteRegKey HKCU "Software\${APP}"
SectionEnd
