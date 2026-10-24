; Standalone build of the custom welcome page only, for visual iteration:
; compile, run, screenshot, and tune the layout without running the real
; installer. The welcome function must stay in sync with the copy inside
; src-tauri/nsis/installer.nsi (they are pasted, not shared, because the
; bundler's template processing doesn't follow includes).
Unicode true
ManifestDPIAware true
ManifestDPIAwareness PerMonitorV2
SetCompressor /SOLID "lzma"

; The icons dir and the output exe path are injected by scripts/preview-welcome.ps1
; so this file stays free of machine-specific absolute paths.
!ifndef BATPLAYER_ICONS
  !error "compile via scripts/preview-welcome.ps1 (needs /DBATPLAYER_ICONS=<src-tauri icons dir>)"
!endif
!ifndef BATPLAYER_OUT
  !error "compile via scripts/preview-welcome.ps1 (needs /DBATPLAYER_OUT=<output exe>)"
!endif

!define MUI_BGCOLOR "0D1018"
!define MUI_TEXTCOLOR "E8EAF0"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${BATPLAYER_ICONS}\installer-header.bmp"
!define MUI_CUSTOMFUNCTION_GUIINIT BatPlayerGuiInit
!include MUI2.nsh

Name "BatPlayer - Welcome Preview"
OutFile "${BATPLAYER_OUT}"
Icon "${BATPLAYER_ICONS}\icon.ico"
RequestExecutionLevel user

Var WelcomeDialog
Var WelcomeLanguage
Var WelcomeLogo
Var WelcomeLogoImg
Var WelcomeTitle
Var WelcomeSubtitle
Var WelcomeInstallButton
Var WelcomeDpi

Page custom BatPlayerWelcomePage

!insertmacro MUI_LANGUAGE "English"

Section ""
  DetailPrint "preview only - nothing installs"
SectionEnd

Function BatPlayerGuiInit
  ; Beyond MUI's own theming, the outer frame keeps a few light-painted
  ; statics (the plain dialog background and thin divider lines). Sweep the
  ; static range and recolor them dark so no light strip survives at the
  ; window edges; page content overrides these colors where it matters.
  StrCpy $0 1000
  sweep_frame_statics:
    System::Call 'user32::GetDlgItem(p $HWNDPARENT, i r0) p.r1'
    ${If} $1 != 0
      ${If} $0 == 1028
      ${OrIf} $0 == 1035
      ${OrIf} $0 == 1036
      ${OrIf} $0 == 1045
        ; Etched edge lines/borders draw system colors no brush can change;
        ; hide them outright.
        System::Call 'user32::ShowWindow(p r1, i 0)'
      ${Else}
        SetCtlColors $1 "E8EAF0" "0D1018"
      ${EndIf}
    ${EndIf}
    IntOp $0 $0 + 1
    IntCmp $0 1300 sweep_frame_statics_done sweep_frame_statics sweep_frame_statics
  sweep_frame_statics_done:
  ; The dialog's own erase background is not a child control at all.
  SetCtlColors $HWNDPARENT "E8EAF0" "0D1018"
  ; Ask DWM for the dark window frame so the caption border/separator and
  ; system chrome follow the theme; attribute changed id between builds.
  System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 20, *i 1, i 4) i.r9'
  ${If} $9 != 0
    System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 19, *i 1, i 4) i.r9'
  ${EndIf}
FunctionEnd

Function BatPlayerWelcomePage
  ${If} $PassiveMode = 1
    Abort
  ${EndIf}

  nsDialogs::Create 1018
  Pop $WelcomeDialog
  ${If} $WelcomeDialog == error
    Abort
  ${EndIf}

  ; Strip the dialog's 3-D edge: the sunken light border NSIS gives page
  ; dialogs reads as a stray full-width hairline over the dark theme.
  System::Call 'user32::GetWindowLong(p $WelcomeDialog, i -20) i.r0'
  IntOp $0 $0 & 0xFFFFFCFF
  System::Call 'user32::SetWindowLong(p $WelcomeDialog, i -20, i r0)'
  System::Call 'user32::SetWindowPos(p $WelcomeDialog, p 0, i 0, i 0, i 0, i 0, i 0x0023)'

  ; Hide the standard buttons plus header text and branding; 1034 (the band's
  ; dark background) and 1046 (the branded header image) must stay, they carry
  ; the themed top of the window.
  StrCpy $0 1
  loop_welcome_chrome:
    GetDlgItem $1 $HWNDPARENT $0
    ShowWindow $1 ${SW_HIDE}
    IntOp $0 $0 + 1
    IntCmp $0 4 welcome_chrome_done loop_welcome_chrome loop_welcome_chrome
  welcome_chrome_done:
  StrCpy $0 1028
  Call HideWelcomeChromeControl
  StrCpy $0 1035
  Call HideWelcomeChromeControl
  StrCpy $0 1037
  Call HideWelcomeChromeControl
  StrCpy $0 1038
  Call HideWelcomeChromeControl
  StrCpy $0 1039
  Call HideWelcomeChromeControl
  StrCpy $0 1045
  Call HideWelcomeChromeControl
  StrCpy $0 1256
  Call HideWelcomeChromeControl

  ; Runtime fonts follow dialog DPI rather than a fixed pixel height,
  ; otherwise text shrinks logically on scaled displays.
  System::Call 'user32::GetDpiForWindow(p $HWNDPARENT) i $WelcomeDpi'

  SetCtlColors $WelcomeDialog "F0F1F4" "0D1018"

  ${NSD_CreateDropList} 76% 6u 21% 14u ""
  Pop $WelcomeLanguage
  ${NSD_CB_AddString} $WelcomeLanguage "English"
  ${NSD_CB_AddString} $WelcomeLanguage "العربية"
  ${NSD_CB_SetSelectionIndex} $WelcomeLanguage 0
  SetCtlColors $WelcomeLanguage "E8EAF0"
  ; Opt the dropdown into the dark variable-com utilities theme where the OS
  ; provides it; falls back silently to standard styling otherwise.
  System::Call 'uxtheme::SetWindowTheme(p $WelcomeLanguage, w "DarkMode_Explorer", p 0)'

  ${NSD_CreateBitmap} 25% 8u 50% 60u ""
  Pop $WelcomeLogo
  File "/oname=$PLUGINSDIR\welcome-logo.bmp" "${BATPLAYER_ICONS}\installer-welcome.bmp"
  ${NSD_SetStretchedImage} $WelcomeLogo "$PLUGINSDIR\welcome-logo.bmp" $WelcomeLogoImg

  ${NSD_CreateLabel} 0 74u 100% 14u "BatPlayer"
  Pop $WelcomeTitle
  ${NSD_AddStyle} $WelcomeTitle ${SS_CENTER}
  SetCtlColors $WelcomeTitle "F5F5F7" "transparent"
  IntOp $0 $WelcomeDpi * 15
  IntOp $0 $0 / 96
  CreateFont $1 "Segoe UI" $0 700
  SendMessage $WelcomeTitle ${WM_SETFONT} $1 1

  ${NSD_CreateLabel} 0 92u 100% 10u "Your media. Your pace."
  Pop $WelcomeSubtitle
  ${NSD_AddStyle} $WelcomeSubtitle ${SS_CENTER}
  SetCtlColors $WelcomeSubtitle "A8ABB5" "transparent"

  ${NSD_CreateButton} 30% 106u 40% 16u "Install BatPlayer"
  Pop $WelcomeInstallButton
  SetCtlColors $WelcomeInstallButton "111318" "FFD400"
  IntOp $0 $WelcomeDpi * 15
  IntOp $0 $0 / 96
  CreateFont $1 "Segoe UI" $0 700
  SendMessage $WelcomeInstallButton ${WM_SETFONT} $1 1
  ${NSD_OnClick} $WelcomeInstallButton BatPlayerBeginInstall

  ${NSD_CreateLabel} 0 126u 100% 10u "Free, open-source media player  •  MIT License"
  Pop $0
  ${NSD_AddStyle} $0 ${SS_CENTER}
  SetCtlColors $0 "858995" "transparent"

  nsDialogs::Show
FunctionEnd

Function HideWelcomeChromeControl
  GetDlgItem $1 $HWNDPARENT $0
  ShowWindow $1 ${SW_HIDE}
FunctionEnd

Function BatPlayerBeginInstall
  ${NSD_CB_GetSelectionIndex} $WelcomeLanguage $0
  ${If} $0 = 1
    StrCpy $LANGUAGE ${LANG_ARABIC}
  ${Else}
    StrCpy $LANGUAGE ${LANG_ENGLISH}
  ${EndIf}
  SendMessage $HWNDPARENT ${WM_COMMAND} 1 0
FunctionEnd
