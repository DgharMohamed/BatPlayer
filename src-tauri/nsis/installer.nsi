Unicode true
ManifestDPIAware true
; Add in `dpiAwareness` `PerMonitorV2` to manifest for Windows 10 1607+ (note this should not affect lower versions since they should be able to ignore this and pick up `dpiAware` `true` set by `ManifestDPIAware true`)
; Currently undocumented on NSIS's website but is in the Docs folder of source tree, see
; https://github.com/kichik/nsis/blob/5fc0b87b819a9eec006df4967d08e522ddd651c9/Docs/src/attributes.but#L286-L300
; https://github.com/tauri-apps/tauri/pull/10106
ManifestDPIAwareness PerMonitorV2

!if "lzma" == "none"
  SetCompress off
!else
  ; Set the compression algorithm. We default to LZMA.
  SetCompressor /SOLID "lzma"
!endif

; Keep above !include to stay ahead of any plugin command
; see https://github.com/tauri-apps/tauri/pull/15422#discussion_r3289239624

ShowInstDetails nevershow
ShowUninstDetails nevershow

!define MUI_BGCOLOR "1E1E1E"
!define MUI_TEXTCOLOR "FFFFFF"
!include MUI2.nsh
!include FileFunc.nsh
!include x64.nsh
!include WordFunc.nsh
!include "utils.nsh"
!include "FileAssociation.nsh"
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"
!include "Win\RestartManager.nsh"
!include "StrFunc.nsh"
${StrCase}
${StrLoc}


!define WEBVIEW2APPGUID "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

!define MANUFACTURER "{{manufacturer}}"
!define PRODUCTNAME "{{product_name}}"
!define VERSION "{{version}}"
!define VERSIONWITHBUILD "{{version_with_build}}"
!define HOMEPAGE "{{homepage}}"
!define INSTALLMODE "{{install_mode}}"
!define LICENSE "{{license}}"
!define INSTALLERICON "{{installer_icon}}"
!define SIDEBARIMAGE "{{sidebar_image}}"
!define HEADERIMAGE "{{header_image}}"
!define UNINSTALLERICON "{{uninstaller_icon}}"
!define UNINSTALLERHEADERIMAGE "{{uninstaller_header_image}}"
!define MAINBINARYNAME "{{main_binary_name}}"
!define MAINBINARYSRCPATH "{{main_binary_path}}"
!define BUNDLEID "{{bundle_id}}"
!define COPYRIGHT "{{copyright}}"
!define OUTFILE "{{out_file}}"
!define ARCH "{{arch}}"
!define ADDITIONALPLUGINSPATH "{{additional_plugins_path}}"
!define ALLOWDOWNGRADES "{{allow_downgrades}}"
!define DISPLAYLANGUAGESELECTOR "{{display_language_selector}}"
!define INSTALLWEBVIEW2MODE "{{install_webview2_mode}}"
!define WEBVIEW2INSTALLERARGS "{{webview2_installer_args}}"
!define WEBVIEW2BOOTSTRAPPERPATH "{{webview2_bootstrapper_path}}"
!define WEBVIEW2INSTALLERPATH "{{webview2_installer_path}}"
!define MINIMUMWEBVIEW2VERSION "{{minimum_webview2_version}}"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCTNAME}"
!define MANUKEY "Software\${MANUFACTURER}"
!define MANUPRODUCTKEY "${MANUKEY}\${PRODUCTNAME}"
!define UNINSTALLERSIGNCOMMAND "{{uninstaller_sign_cmd}}"
!define ESTIMATEDSIZE "{{estimated_size}}"
!define STARTMENUFOLDER "{{start_menu_folder}}"

Var PassiveMode
Var UpdateMode
Var NoShortcutMode
Var WixMode
Var OldMainBinaryName

Name "${PRODUCTNAME}"
BrandingText "${COPYRIGHT}"
OutFile "${OUTFILE}"

; We don't actually use this value as default install path,
; it's just for nsis to append the product name folder in the directory selector
; https://nsis.sourceforge.io/Reference/InstallDir
!define PLACEHOLDER_INSTALL_DIR "placeholder\${PRODUCTNAME}"
InstallDir "${PLACEHOLDER_INSTALL_DIR}"

VIProductVersion "${VERSIONWITHBUILD}"
VIAddVersionKey "ProductName" "${PRODUCTNAME}"
VIAddVersionKey "FileDescription" "${PRODUCTNAME}"
VIAddVersionKey "LegalCopyright" "${COPYRIGHT}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

# additional plugins
!addplugindir "${ADDITIONALPLUGINSPATH}"

; Uninstaller signing command
!if "${UNINSTALLERSIGNCOMMAND}" != ""
  !uninstfinalize '${UNINSTALLERSIGNCOMMAND}'
!endif

; Handle install mode, `perUser`, `perMachine` or `both`
!if "${INSTALLMODE}" == "perMachine"
  RequestExecutionLevel admin
!endif

!if "${INSTALLMODE}" == "currentUser"
  RequestExecutionLevel user
!endif

!if "${INSTALLMODE}" == "both"
  !define MULTIUSER_MUI
  !define MULTIUSER_INSTALLMODE_INSTDIR "${PRODUCTNAME}"
  !define MULTIUSER_INSTALLMODE_COMMANDLINE
  !if "${ARCH}" == "x64"
    !define MULTIUSER_USE_PROGRAMFILES64
  !else if "${ARCH}" == "arm64"
    !define MULTIUSER_USE_PROGRAMFILES64
  !endif
  !define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_KEY "${UNINSTKEY}"
  !define MULTIUSER_INSTALLMODE_DEFAULT_REGISTRY_VALUENAME "CurrentUser"
  !define MULTIUSER_INSTALLMODEPAGE_SHOWUSERNAME
  !define MULTIUSER_INSTALLMODE_FUNCTION RestorePreviousInstallLocation
  !define MULTIUSER_EXECUTIONLEVEL Highest
  !include MultiUser.nsh
!endif

; Installer icon
!if "${INSTALLERICON}" != ""
  !define MUI_ICON "${INSTALLERICON}"
!endif

; Installer sidebar image
!if "${SIDEBARIMAGE}" != ""
  !define MUI_WELCOMEFINISHPAGE_BITMAP "${SIDEBARIMAGE}"
!endif

; Enable header images for installer and uninstaller pages when either image is configured.
!if "${HEADERIMAGE}" != ""
  !define MUI_HEADERIMAGE
!else if "${UNINSTALLERHEADERIMAGE}" != ""
  !define MUI_HEADERIMAGE
!endif

; Installer header image
!if "${HEADERIMAGE}" != ""
  !define MUI_HEADERIMAGE_BITMAP "${HEADERIMAGE}"
!endif

; Uninstaller header image
!if "${UNINSTALLERHEADERIMAGE}" != ""
  !define MUI_HEADERIMAGE_UNBITMAP "${UNINSTALLERHEADERIMAGE}"
!endif

; Uninstaller icon
!if "${UNINSTALLERICON}" != ""
  !define MUI_UNICON "${UNINSTALLERICON}"
!endif

; Define registry key to store installer language
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "${MANUPRODUCTKEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Installer Language"

; Modern Minimalist Dark Gray (#1E1E1E) & Yellow (#FFC107) Theme
!define THEME_PRIMARY_BG   "1E1E1E"
!define THEME_CARD_BG      "252526"
!define THEME_ACCENT       "FFC107"
!define THEME_ACCENT_HOVER "FFD54F"
!define THEME_TEXT_WHITE   "FFFFFF"
!define THEME_TEXT_MUTED   "A0A0A0"
!define THEME_TEXT_DARK    "1E1E1E"

!define WIN_WIDTH  760
!define WIN_HEIGHT 540

!define MUI_CUSTOMFUNCTION_GUIINIT BatPlayerGuiInit

Var WelcomeDialog
Var WelcomeHeroImage
Var WelcomeTitle
Var WelcomeSubtitle
Var WelcomeInstallBtn
Var WelcomeCloseBtn
Var WelcomeLegalPrefix
Var WelcomeEulaLink
Var WelcomePrivacyLink
Var WelcomeFontTitle
Var WelcomeFontSub
Var WelcomeFontBody
Var WelcomeFontBtn
Var WelcomeFontClose
Var FinishLaunchGlyph
Var FinishLaunchState   ; 1 = launch app on finish (default), 0 = don't
Var FinishBtn

Function BatPlayerInitFonts
  CreateFont $WelcomeFontTitle "Segoe UI" 23 700
  CreateFont $WelcomeFontSub   "Segoe UI" 11 400
  CreateFont $WelcomeFontBody  "Segoe UI" 9  400
  CreateFont $WelcomeFontBtn   "Segoe UI" 12 700
  CreateFont $WelcomeFontClose "Segoe UI" 12 600
FunctionEnd

Function BatPlayerMakeBorderless
  ; 1. DWM Immersive Dark Mode
  System::Call '*(i 1) p .r0'
  System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 20, p r0, i 4) i .r1'
  ${If} $1 != 0
    System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 19, p r0, i 4)'
  ${EndIf}
  System::Free $0

  ; 2. Strip standard window caption (WS_CAPTION) and sizing frame (WS_THICKFRAME)
  System::Call 'user32::GetWindowLong(p $HWNDPARENT, i -16) i .r0'
  IntOp $0 $0 & 0xFF3BFFFF ; Clears 0x00C40000
  System::Call 'user32::SetWindowLong(p $HWNDPARENT, i -16, i r0)'

  ; 3. Resize and center with generous dimensions
  System::Call 'user32::SetWindowPos(p $HWNDPARENT, p 0, i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 0x0026)'
  Call BatPlayerCenterWindow

  ; 4. Apply 16px rounded window corners
  System::Call 'gdi32::CreateRoundRectRgn(i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 18, i 18) p .r2'
  System::Call 'user32::SetWindowRgn(p $HWNDPARENT, p r2, i 1)'
FunctionEnd

Function BatPlayerCenterWindow
  System::Call '*(i,i,i,i) p .r0'
  System::Call '*(i,i,i,i) p .r1'
  System::Call 'user32::GetWindowRect(p $HWNDPARENT, p r0)'
  System::Call 'user32::SystemParametersInfo(i 0x0030, i 0, p r1, i 0)'
  System::Call '*$0(i .r2, i .r3, i .r4, i .r5)'
  System::Call '*$1(i .r6, i .r7, i .r8, i .r9)'
  IntOp $4 $4 - $2
  IntOp $5 $5 - $3
  IntOp $8 $8 - $6
  IntOp $9 $9 - $7
  IntOp $8 $8 - $4
  IntOp $9 $9 - $5
  IntOp $8 $8 / 2
  IntOp $9 $9 / 2
  IntOp $2 $6 + $8
  IntOp $3 $7 + $9
  System::Call 'user32::SetWindowPos(p $HWNDPARENT, p 0, i r2, i r3, i 0, i 0, i 0x0015)'
  System::Free $0
  System::Free $1
FunctionEnd

Function BatPlayerHideChrome
  GetDlgItem $0 $HWNDPARENT 1
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 2
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 3
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1028
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1256
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1034
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1035
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1036
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1037
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1038
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1039
  ShowWindow $0 ${SW_HIDE}
  GetDlgItem $0 $HWNDPARENT 1046
  ShowWindow $0 ${SW_HIDE}
FunctionEnd
Function BatPlayerStretchInner
  ; NOTE: The page dialog handle is passed on the stack (from nsDialogs::Create)
  ; because FindWindow("#32770") can match a STALE dialog from the previous page
  ; on later pages, leaving the real page dialog white and unstretched.
  Pop $0
  SetCtlColors $HWNDPARENT "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  ${If} $0 != 0
    System::Call 'user32::SetWindowPos(p $0, p 0, i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 0x0004)'
    SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  ${EndIf}
  ; NSIS normalizes subsequent pages' dialogs back onto the Static(1018)
  ; "page area" anchor when navigating between pages, which would undo our
  ; stretch. Resize that anchor too so normalization lands full-bleed.
  GetDlgItem $1 $HWNDPARENT 1018
  ${If} $1 != 0
    System::Call 'user32::SetWindowPos(p $1, p 0, i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 0x0004)'
  ${EndIf}
FunctionEnd

Function BatPlayerDragWindow
  System::Call 'user32::ReleaseCapture()'
  SendMessage $HWNDPARENT 0x00A1 2 0
FunctionEnd

Function BatPlayerCloseClick
  SendMessage $HWNDPARENT 0x0010 0 0
FunctionEnd

Function BatPlayerCreateYellowPill
  Pop $6 ; Text
  Pop $5 ; Height
  Pop $4 ; Width
  Pop $3 ; Y
  Pop $2 ; X

  ${NSD_CreateLabel} $2 $3 $4 $5 $6
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_DARK}" "${THEME_ACCENT}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontBtn 1

  System::Call 'user32::GetWindowLong(p $0, i -16) i .r1'
  IntOp $1 $1 | 0x00000301
  System::Call 'user32::SetWindowLong(p $0, i -16, i r1)'

  System::Call 'gdi32::CreateRoundRectRgn(i 0, i 0, i $4, i $5, i 14, i 14) p .r7'
  System::Call 'user32::SetWindowRgn(p $0, p r7, i 1)'

  System::Call 'user32::LoadCursor(p 0, i 32649) p .r8'
  System::Call 'user32::SetClassLong(p $0, i -12, p r8)'

  Push $0
FunctionEnd

Page custom BatPlayerWelcomePage

Function BatPlayerWelcomePage
  ${If} $PassiveMode = 1
    Abort
  ${EndIf}

  Call BatPlayerInitFonts
  Call BatPlayerMakeBorderless
  Call BatPlayerHideChrome

  nsDialogs::Create 1018
  Pop $WelcomeDialog
  ${If} $WelcomeDialog == error
    Abort
  ${EndIf}

  Push $WelcomeDialog
  Call BatPlayerStretchInner

  ; 1. Top Window Drag Bar (spans across the full header)
  ${NSD_CreateLabel} 0 0 700 45 ""
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  ${NSD_OnClick} $0 BatPlayerDragWindow

  ; 2. Top-Right Close Button ('✕')
  ${NSD_CreateLabel} 712 14 34 30 "✕"
  Pop $WelcomeCloseBtn
  SetCtlColors $WelcomeCloseBtn "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomeCloseBtn ${WM_SETFONT} $WelcomeFontClose 1
  ${NSD_AddStyle} $WelcomeCloseBtn 0x00000301
  ${NSD_OnClick} $WelcomeCloseBtn BatPlayerCloseClick
  System::Call 'user32::LoadCursor(p 0, i 32649) p .r1'
  System::Call 'user32::SetClassLong(p $WelcomeCloseBtn, i -12, p r1)'

  ; 3. Center Hero Icon with Stylized Yellow Accent Ring (140x140 at X: 310, Y: 55)
  ${NSD_CreateBitmap} 310 55 140 140 ""
  Pop $WelcomeHeroImage
  File "/oname=$PLUGINSDIR\hero_ring.bmp" "${__FILEDIR__}\..\..\..\..\icons\hero_ring.bmp"
  File "/oname=$PLUGINSDIR\icon.ico" "${__FILEDIR__}\..\..\..\..\icons\icon.ico"
  System::Call 'user32::LoadImage(p 0, t "$PLUGINSDIR\hero_ring.bmp", i 0, i 140, i 140, i 0x0010) p .r1'
  ${If} $1 != 0
    SendMessage $WelcomeHeroImage ${STM_SETIMAGE} 0 $1
  ${Else}
    ; Fallback icon
    ${NSD_CreateIcon} 332 70 96 96 ""
    Pop $0
    System::Call 'user32::LoadImage(p 0, t "$PLUGINSDIR\icon.ico", i 1, i 96, i 96, i 0x0010) p .r2'
    SendMessage $0 ${STM_SETIMAGE} 1 $2
  ${EndIf}

  ; 4. Title: "Install BatPlayer" (Y: 215, H: 45)
  ${NSD_CreateLabel} 0 215 ${WIN_WIDTH} 45 "Install ${PRODUCTNAME}"
  Pop $WelcomeTitle
  SetCtlColors $WelcomeTitle "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomeTitle ${WM_SETFONT} $WelcomeFontTitle 1
  ${NSD_AddStyle} $WelcomeTitle 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ; 5. Subtitle Tagline (Y: 265, H: 24)
  ${NSD_CreateLabel} 0 265 ${WIN_WIDTH} 24 "Your media. Your pace."
  Pop $WelcomeSubtitle
  SetCtlColors $WelcomeSubtitle "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomeSubtitle ${WM_SETFONT} $WelcomeFontSub 1
  ${NSD_AddStyle} $WelcomeSubtitle 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ; 6. Large Rounded Yellow Action Button (X: 240, Y: 320, W: 280, H: 50)
  Push 240
  Push 320
  Push 280
  Push 50
  Push "Install Now"
  Call BatPlayerCreateYellowPill
  Pop $WelcomeInstallBtn
  ${NSD_OnClick} $WelcomeInstallBtn BatPlayerBeginInstall

  ; 7. Legal EULA & Privacy Policy Section (Y: 420, H: 20)
  ${NSD_CreateLabel} 0 420 ${WIN_WIDTH} 20 "By installing or using this product, you agree to its "
  Pop $WelcomeLegalPrefix
  SetCtlColors $WelcomeLegalPrefix "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomeLegalPrefix ${WM_SETFONT} $WelcomeFontBody 1
  ${NSD_AddStyle} $WelcomeLegalPrefix 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ; EULA & Privacy Policy Interactive Links with Clean Alignment (Y: 445)
  ${NSD_CreateLink} 275 445 60 20 "EULA"
  Pop $WelcomeEulaLink
  SetCtlColors $WelcomeEulaLink "${THEME_ACCENT}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomeEulaLink ${WM_SETFONT} $WelcomeFontBody 1
  ${NSD_AddStyle} $WelcomeEulaLink 0x00000002 ; SS_RIGHT
  ${NSD_OnClick} $WelcomeEulaLink BatPlayerClickEula

  ${NSD_CreateLabel} 335 445 40 20 " and "
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontBody 1
  ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ${NSD_CreateLink} 375 445 115 20 "Privacy Policy"
  Pop $WelcomePrivacyLink
  SetCtlColors $WelcomePrivacyLink "${THEME_ACCENT}" "${THEME_PRIMARY_BG}"
  SendMessage $WelcomePrivacyLink ${WM_SETFONT} $WelcomeFontBody 1
  ${NSD_AddStyle} $WelcomePrivacyLink 0x00000000 ; SS_LEFT
  ${NSD_OnClick} $WelcomePrivacyLink BatPlayerClickPrivacy

  nsDialogs::Show
FunctionEnd

Function BatPlayerClickEula
  ExecShell "open" "https://batsoft.vercel.app/apps/batplayer/terms"
FunctionEnd

Function BatPlayerClickPrivacy
  ExecShell "open" "https://batsoft.vercel.app/apps/batplayer/privacy"
FunctionEnd
Function BatPlayerGuiInit
  SetCtlColors $HWNDPARENT "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 20, *i 1, i 4) i.r9'
  ${If} $9 != 0
    System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 19, *i 1, i 4)'
  ${EndIf}
FunctionEnd

Function BatPlayerBeginInstall
  ; Rely on NSIS's own Next button (control id 1 on $HWNDPARENT): BM_CLICK makes
  ; the button itself deliver its BN_CLICKED notification to the dialog proc,
  ; which is how a genuine user click advances the page. This is much more
  ; reliable than posting a bare WM_COMMAND(id=1) with no lParam.
  GetDlgItem $0 $HWNDPARENT 1
  EnableWindow $0 1
  SendMessage $0 ${BM_CLICK} 0 0
FunctionEnd

; Remaining installation pages are intentionally reduced to install progress
; and completion; BatPlayer installs to the current user's app-data folder.

; Install mode (if it is set to `both`)
!if "${INSTALLMODE}" == "both"
  !define MUI_PAGE_CUSTOMFUNCTION_PRE SkipIfPassive
  !insertmacro MULTIUSER_PAGE_INSTALLMODE
!endif

; 4. Custom page to ask user if he wants to reinstall/uninstall
;    only if a previous installation was detected
Var ReinstallPageCheck
Var ReinstallOptionOneText
Var ReinstallOptionTwoText
Var ReinstallOptionOneControl
Var ReinstallOptionTwoControl
Page custom PageReinstall PageLeaveReinstall
Function PageReinstall
  ; Uninstall previous WiX installation if exists.
  ;
  ; A WiX installer stores the installation info in registry
  ; using a UUID and so we have to loop through all keys under
  ; `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
  ; and check if `DisplayName` and `Publisher` keys match ${PRODUCTNAME} and ${MANUFACTURER}
  ;
  ; This has a potential issue that there maybe another installation that matches
  ; our ${PRODUCTNAME} and ${MANUFACTURER} but wasn't installed by our WiX installer,
  ; however, this should be fine since the user will have to confirm the uninstallation
  ; and they can chose to abort it if doesn't make sense.
  StrCpy $0 0
  wix_loop:
    EnumRegKey $1 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" $0
    StrCmp $1 "" wix_loop_done ; Exit loop if there is no more keys to loop on
    IntOp $0 $0 + 1
    ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1" "DisplayName"
    ReadRegStr $R1 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1" "Publisher"
    StrCmp "$R0$R1" "${PRODUCTNAME}${MANUFACTURER}" 0 wix_loop
    ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1" "UninstallString"
    ${StrCase} $R1 $R0 "L"
    ${StrLoc} $R0 $R1 "msiexec" ">"
    StrCmp $R0 0 0 wix_loop_done
    StrCpy $WixMode 1
    StrCpy $R6 "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$1"
    Goto compare_version
  wix_loop_done:

  ; Check if there is an existing installation, if not, abort the reinstall page
  ReadRegStr $R0 SHCTX "${UNINSTKEY}" ""
  ReadRegStr $R1 SHCTX "${UNINSTKEY}" "UninstallString"
  ${IfThen} "$R0$R1" == "" ${|} Abort ${|}

  ; Compare this installar version with the existing installation
  ; and modify the messages presented to the user accordingly
  compare_version:
  StrCpy $R4 "$(older)"
  ${If} $WixMode = 1
    ReadRegStr $R0 HKLM "$R6" "DisplayVersion"
  ${Else}
    ReadRegStr $R0 SHCTX "${UNINSTKEY}" "DisplayVersion"
  ${EndIf}
  ${IfThen} $R0 == "" ${|} StrCpy $R4 "$(unknown)" ${|}

  nsis_tauri_utils::SemverCompare "${VERSION}" $R0
  Pop $R0
  ; Reinstalling the same version
  ${If} $R0 = 0
    StrCpy $R1 "$(alreadyInstalledLong)"
    StrCpy $R2 "$(addOrReinstall)"
    StrCpy $R3 "$(uninstallApp)"
    !insertmacro MUI_HEADER_TEXT "$(alreadyInstalled)" "$(chooseMaintenanceOption)"
  ; Upgrading
  ${ElseIf} $R0 = 1
    StrCpy $R1 "$(olderOrUnknownVersionInstalled)"
    StrCpy $R2 "$(uninstallBeforeInstalling)"
    StrCpy $R3 "$(dontUninstall)"
    !insertmacro MUI_HEADER_TEXT "$(alreadyInstalled)" "$(choowHowToInstall)"
  ; Downgrading
  ${ElseIf} $R0 = -1
    StrCpy $R1 "$(newerVersionInstalled)"
    StrCpy $R2 "$(uninstallBeforeInstalling)"
    !if "${ALLOWDOWNGRADES}" == "true"
      StrCpy $R3 "$(dontUninstall)"
    !else
      StrCpy $R3 "$(dontUninstallDowngrade)"
    !endif
    !insertmacro MUI_HEADER_TEXT "$(alreadyInstalled)" "$(choowHowToInstall)"
  ${Else}
    Abort
  ${EndIf}

  StrCpy $ReinstallOptionOneText $R2
  StrCpy $ReinstallOptionTwoText $R3

  ; Skip showing the page if passive
  ;
  ; Note that we don't call this earlier at the beginning
  ; of this function because we need to populate some variables
  ; related to current installed version if detected and whether
  ; we are downgrading or not.
  ${If} $PassiveMode = 1
    StrCpy $ReinstallPageCheck 1
    Call PageLeaveReinstall
  ${Else}
    Call BatPlayerInitFonts
    Call BatPlayerMakeBorderless
    Call BatPlayerHideChrome

    nsDialogs::Create 1018
    Pop $R4
    ${If} $R4 == error
      Abort
    ${EndIf}

    Push $R4
    Call BatPlayerStretchInner
    SetCtlColors $R4 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"

    ; 1. Drag Header
    ${NSD_CreateLabel} 0 0 700 45 ""
    Pop $0
    SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
    ${NSD_OnClick} $0 BatPlayerDragWindow

    ; 2. Close Button ('✕')
    ${NSD_CreateLabel} 712 14 34 30 "✕"
    Pop $0
    SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
    SendMessage $0 ${WM_SETFONT} $WelcomeFontClose 1
    ${NSD_AddStyle} $0 0x00000301
    ${NSD_OnClick} $0 OnClickReinstallCancel
    System::Call 'user32::LoadCursor(p 0, i 32649) p .r8'
    System::Call 'user32::SetClassLong(p $0, i -12, p r8)'

    ; 3. Center Hero Icon with Stylized Yellow Accent Ring (140x140 at X: 310, Y: 45)
    ${NSD_CreateBitmap} 310 45 140 140 ""
    Pop $0
    System::Call 'user32::LoadImage(p 0, t "$PLUGINSDIR\hero_ring.bmp", i 0, i 140, i 140, i 0x0010) p .r1'
    ${If} $1 != 0
      SendMessage $0 ${STM_SETIMAGE} 0 $1
    ${EndIf}

    ; 4. Title Header: "Already Installed"
    ${NSD_CreateLabel} 0 195 ${WIN_WIDTH} 40 "${PRODUCTNAME} is Already Installed"
    Pop $0
    SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
    SendMessage $0 ${WM_SETFONT} $WelcomeFontTitle 1
    ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX

    ; 5. Subtitle: Explanatory text
    ${NSD_CreateLabel} 60 240 640 24 "Select the maintenance operation you want to perform:"
    Pop $0
    SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
    SendMessage $0 ${WM_SETFONT} $WelcomeFontSub 1
    ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX

    ; Dark selectable maintenance rows. Static labels with SS_NOTIFY keep the
    ; entire row clickable while letting the selected state use the theme.
    ${NSD_CreateLabel} 220 280 320 32 ""
    Pop $ReinstallOptionOneControl
    ${NSD_AddStyle} $ReinstallOptionOneControl 0x00000300
    SendMessage $ReinstallOptionOneControl ${WM_SETFONT} $WelcomeFontSub 1
    ${NSD_OnClick} $ReinstallOptionOneControl PageReinstallSelectOne
    System::Call 'user32::LoadCursor(p 0, i 32649) p .r8'
    System::Call 'user32::SetClassLong(p $ReinstallOptionOneControl, i -12, p r8)'

    ${NSD_CreateLabel} 220 320 320 32 ""
    Pop $ReinstallOptionTwoControl
    ${NSD_AddStyle} $ReinstallOptionTwoControl 0x00000300
    SendMessage $ReinstallOptionTwoControl ${WM_SETFONT} $WelcomeFontSub 1
    ${NSD_OnClick} $ReinstallOptionTwoControl PageReinstallSelectTwo
    System::Call 'user32::LoadCursor(p 0, i 32649) p .r8'
    System::Call 'user32::SetClassLong(p $ReinstallOptionTwoControl, i -12, p r8)'
    !if "${ALLOWDOWNGRADES}" == "false"
      ${IfThen} $R0 = -1 ${|} EnableWindow $ReinstallOptionTwoControl 0 ${|}
    !endif

    ; Keep the existing choice on page recreation, defaulting to option one.
    ${If} $ReinstallPageCheck <> 2
      StrCpy $ReinstallPageCheck 1
    ${EndIf}
    Call PageReinstallRefreshChoices

    ; 8. Action Button: "Continue" (Large Vibrant Yellow pill button)
    Push 250
    Push 375
    Push 260
    Push 50
    Push "Continue"
    Call BatPlayerCreateYellowPill
    Pop $0
    ${NSD_OnClick} $0 OnClickReinstallContinue

    ; 9. Secondary Link: "Cancel and exit installer"
    ${NSD_CreateLink} 0 450 ${WIN_WIDTH} 20 "Cancel and exit setup"
    Pop $0
    SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
    SendMessage $0 ${WM_SETFONT} $WelcomeFontBody 1
    ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX
    ${NSD_OnClick} $0 OnClickReinstallCancel

    ${NSD_SetFocus} $ReinstallOptionOneControl
    nsDialogs::Show
  ${EndIf}
FunctionEnd

Function OnClickReinstallContinue
  GetDlgItem $0 $HWNDPARENT 1
  EnableWindow $0 1
  SendMessage $0 ${BM_CLICK} 0 0
FunctionEnd

Function OnClickReinstallCancel
  SendMessage $HWNDPARENT 0x0010 0 0
FunctionEnd
Function PageReinstallSelectOne
  StrCpy $ReinstallPageCheck 1
  Call PageReinstallRefreshChoices
FunctionEnd
Function PageReinstallSelectTwo
  StrCpy $ReinstallPageCheck 2
  Call PageReinstallRefreshChoices
FunctionEnd
Function PageReinstallRefreshChoices
  ${If} $ReinstallPageCheck = 1
    ${NSD_SetText} $ReinstallOptionOneControl "  ●   $ReinstallOptionOneText"
    SetCtlColors $ReinstallOptionOneControl "${THEME_ACCENT}" "${THEME_CARD_BG}"
    ${NSD_SetText} $ReinstallOptionTwoControl "  ○   $ReinstallOptionTwoText"
    SetCtlColors $ReinstallOptionTwoControl "${THEME_TEXT_WHITE}" "${THEME_CARD_BG}"
  ${Else}
    ${NSD_SetText} $ReinstallOptionOneControl "  ○   $ReinstallOptionOneText"
    SetCtlColors $ReinstallOptionOneControl "${THEME_TEXT_WHITE}" "${THEME_CARD_BG}"
    ${NSD_SetText} $ReinstallOptionTwoControl "  ●   $ReinstallOptionTwoText"
    SetCtlColors $ReinstallOptionTwoControl "${THEME_ACCENT}" "${THEME_CARD_BG}"
  ${EndIf}
FunctionEnd
Function PageLeaveReinstall
  StrCpy $R1 $ReinstallPageCheck

  ; If migrating from Wix, always uninstall
  ${If} $WixMode = 1
    Goto reinst_uninstall
  ${EndIf}

  ; In update mode, always proceeds without uninstalling
  ${If} $UpdateMode = 1
    Goto reinst_done
  ${EndIf}

  ; $R0 holds whether same(0)/upgrading(1)/downgrading(-1) version
  ; $R1 holds the radio buttons state:
  ;   1 => first choice was selected
  ;   0 => second choice was selected
  ${If} $R0 = 0 ; Same version, proceed
    ${If} $R1 = 1              ; User chose to add/reinstall
      Goto reinst_done
    ${Else}                    ; User chose to uninstall
      Goto reinst_uninstall
    ${EndIf}
  ${ElseIf} $R0 = 1 ; Upgrading
    ${If} $R1 = 1              ; User chose to uninstall
      Goto reinst_uninstall
    ${Else}
      Goto reinst_done         ; User chose NOT to uninstall
    ${EndIf}
  ${ElseIf} $R0 = -1 ; Downgrading
    ${If} $R1 = 1              ; User chose to uninstall
      Goto reinst_uninstall
    ${Else}
      Goto reinst_done         ; User chose NOT to uninstall
    ${EndIf}
  ${EndIf}

  reinst_uninstall:
    HideWindow
    ClearErrors

    ${If} $WixMode = 1
      ReadRegStr $R1 HKLM "$R6" "UninstallString"
      ExecWait '$R1' $0
    ${Else}
      ReadRegStr $4 SHCTX "${MANUPRODUCTKEY}" ""
      ReadRegStr $R1 SHCTX "${UNINSTKEY}" "UninstallString"
      ${IfThen} $UpdateMode = 1 ${|} StrCpy $R1 "$R1 /UPDATE" ${|} ; append /UPDATE
      ${IfThen} $PassiveMode = 1 ${|} StrCpy $R1 "$R1 /P" ${|} ; append /P
      StrCpy $R1 "$R1 _?=$4" ; append uninstall directory
      ExecWait '$R1' $0
    ${EndIf}

    BringToFront

    ${IfThen} ${Errors} ${|} StrCpy $0 2 ${|} ; ExecWait failed, set fake exit code

    ${If} $0 <> 0
    ${OrIf} ${FileExists} "$INSTDIR\${MAINBINARYNAME}.exe"
      ; User cancelled wix uninstaller? return to select un/reinstall page
      ${If} $WixMode = 1
      ${AndIf} $0 = 1602
        Abort
      ${EndIf}

      ; User cancelled NSIS uninstaller? return to select un/reinstall page
      ${If} $0 = 1
        Abort
      ${EndIf}

      ; Other errors? show generic error message and return to select un/reinstall page
      MessageBox MB_ICONEXCLAMATION "$(unableToUninstall)"
      Abort
    ${EndIf}

    ; The NSIS uninstaller was run in place (`_?=`), so it cannot delete itself
    ; and the install directory, clean them up here once the uninstall succeeded
    ; https://nsis.sourceforge.io/Docs/Chapter3.html#:~:text=path%20contains%20spaces.-,3.2.3%20Examples,-installer.exe%20/NCRC
    ${If} $WixMode = 0
    ${AndIf} $4 != ""
      Delete "$4\uninstall.exe"
      RMDir "$4"
    ${EndIf}
  reinst_done:
FunctionEnd

; Keep the default per-user location for the one-click installation.
!define MUI_PAGE_CUSTOMFUNCTION_PRE Skip
!insertmacro MUI_PAGE_DIRECTORY

; 6. Start menu shortcut page
Var AppStartMenuFolder
!if "${STARTMENUFOLDER}" != ""
  !define MUI_PAGE_CUSTOMFUNCTION_PRE SkipIfPassive
  !define MUI_STARTMENUPAGE_DEFAULTFOLDER "${STARTMENUFOLDER}"
!else
  !define MUI_PAGE_CUSTOMFUNCTION_PRE Skip
!endif
!insertmacro MUI_PAGE_STARTMENU Application $AppStartMenuFolder

; 7. Installation page
!define MUI_PAGE_CUSTOMFUNCTION_SHOW ShowInstallerChrome
!insertmacro MUI_PAGE_INSTFILES
!undef MUI_PAGE_CUSTOMFUNCTION_SHOW

Function ShowInstallerChrome
  ; IMPORTANT: The INSTFILES page has no nsDialogs page context, so
  ; nsDialogs::CreateControl-based macros (${NSD_Create*} etc.) must NOT be used
  ; here. Calling them without nsDialogs::Create is undefined behavior and
  ; crashes the process (the installer window would disappear right after
  ; "Install Now"). All child controls are created with raw CreateWindowEx
  ; instead; the controls that need click callbacks are intentionally omitted.
  Call BatPlayerMakeBorderless
  Call BatPlayerHideChrome

  ; The instfiles inner dialog is a native #32770 (no stale-overlay risk here),
  ; so FindWindow is safe: stretch it full-bleed and pre-color it dark.
  SetCtlColors $HWNDPARENT "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  FindWindow $0 "#32770" "" $HWNDPARENT
  ${If} $0 != 0
    System::Call 'user32::SetWindowPos(p $0, p 0, i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 0x0004)'
    SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  ${EndIf}
  ; Re-assert the Static(1018) page-area anchor full-bleed for the same reason
  ; as BatPlayerStretchInner (NSIS normalization between pages).
  GetDlgItem $1 $HWNDPARENT 1018
  ${If} $1 != 0
    System::Call 'user32::SetWindowPos(p $1, p 0, i 0, i 0, i ${WIN_WIDTH}, i ${WIN_HEIGHT}, i 0x0004)'
  ${EndIf}

  ${If} $0 != 0
    ; Explicitly HIDE the ugly white extraction log listbox (1016) and details box (1005)
    GetDlgItem $R3 $0 1016
    ${If} $R3 != 0
      ShowWindow $R3 ${SW_HIDE}
      EnableWindow $R3 0
    ${EndIf}
    GetDlgItem $R3 $0 1005
    ${If} $R3 != 0
      ShowWindow $R3 ${SW_HIDE}
      EnableWindow $R3 0
    ${EndIf}
    GetDlgItem $R3 $0 1027
    ${If} $R3 != 0
      ShowWindow $R3 ${SW_HIDE}
    ${EndIf}

    ; Hero graphic on installation screen for visual continuity (X: 310, Y: 55, 140x140)
    System::Call 'user32::CreateWindowEx(i 0, w "STATIC", w "", i 0x50000000, i 310, i 55, i 140, i 140, p $0, p 0, p 0, p 0) p .r9'
    System::Call 'user32::LoadImage(p 0, t "$PLUGINSDIR\hero_ring.bmp", i 0, i 140, i 140, i 0x0010) p .r1'
    ${If} $9 != 0
      SetCtlColors $9 "" "${THEME_PRIMARY_BG}"
      ${If} $1 != 0
        SendMessage $9 ${STM_SETIMAGE} 0 $1
      ${EndIf}
    ${EndIf}

    ; Title Header: "Installing BatPlayer..." (raw STATIC, SS_CENTER)
    System::Call 'user32::CreateWindowEx(i 0, w "STATIC", w "Installing ${PRODUCTNAME}...", i 0x50000081, i 0, i 215, i ${WIN_WIDTH}, i 45, p $0, p 0, p 0, p 0) p .r9'
    ${If} $9 != 0
      SetCtlColors $9 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
      SendMessage $9 ${WM_SETFONT} $WelcomeFontTitle 1
    ${EndIf}

    ; Status Subtitle text ("Extracting files...") (Control ID 1006)
    GetDlgItem $1 $0 1006
    ${If} $1 != 0
      System::Call 'user32::SetWindowPos(p $1, p 0, i 80, i 265, i 600, i 26, i 0x0004)'
      SetCtlColors $1 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
      SendMessage $1 ${WM_SETFONT} $WelcomeFontSub 1
      System::Call 'user32::GetWindowLong(p $1, i -16) i .r8'
      IntOp $8 $8 | 0x00000081 ; SS_CENTER | SS_NOPREFIX
      System::Call 'user32::SetWindowLong(p $1, i -16, i r8)'
    ${EndIf}

    ; Progress Bar (Control ID 1004, X: 130, Y: 320, W: 500, H: 18)
    GetDlgItem $3 $0 1004
    ${If} $3 != 0
      System::Call 'user32::SetWindowPos(p $3, p 0, i 130, i 320, i 500, i 18, i 0x0004)'
      System::Call 'uxtheme::SetWindowTheme(p $3, w "", w "")'
      SendMessage $3 0x2001 0 0x002B2B2B ; PBM_SETBKCOLOR (#2B2B2B Dark Charcoal track)
      SendMessage $3 0x0409 0 0x0007C1FF ; PBM_SETBARCOLOR (#FFC107 Vibrant Yellow fill)
    ${EndIf}

    ; Subtle subtext below progress bar (raw STATIC, SS_CENTER)
    System::Call 'user32::CreateWindowEx(i 0, w "STATIC", w "Please wait while files are being set up...", i 0x50000081, i 0, i 355, i ${WIN_WIDTH}, i 22, p $0, p 0, p 0, p 0) p .r9'
    ${If} $9 != 0
      SetCtlColors $9 "707070" "${THEME_PRIMARY_BG}"
      SendMessage $9 ${WM_SETFONT} $WelcomeFontBody 1
    ${EndIf}
  ${EndIf}
FunctionEnd

; 8. Custom Modern Finish Page
Page custom BatPlayerFinishPage BatPlayerFinishLeave

Function BatPlayerFinishPage
  ${If} $PassiveMode = 1
    Abort
  ${EndIf}

  Call BatPlayerInitFonts
  Call BatPlayerMakeBorderless
  Call BatPlayerHideChrome

  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  Push $0
  Call BatPlayerStretchInner

  ; 1. Drag Header
  ${NSD_CreateLabel} 0 0 700 45 ""
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  ${NSD_OnClick} $0 BatPlayerDragWindow

  ; 2. Close Button
  ${NSD_CreateLabel} 712 14 34 30 "✕"
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontClose 1
  ${NSD_AddStyle} $0 0x00000301
  ${NSD_OnClick} $0 BatPlayerFinishCloseClick
  System::Call 'user32::LoadCursor(p 0, i 32649) p .r8'
  System::Call 'user32::SetClassLong(p $0, i -12, p r8)'

  ; 3. Hero Graphic (140x140 at X: 310, Y: 55)
  ${NSD_CreateBitmap} 310 55 140 140 ""
  Pop $0
  System::Call 'user32::LoadImage(p 0, t "$PLUGINSDIR\hero_ring.bmp", i 0, i 140, i 140, i 0x0010) p .r1'
  ${If} $1 != 0
    SendMessage $0 ${STM_SETIMAGE} 0 $1
  ${EndIf}

  ; 4. Finish Title: "BatPlayer is Ready!"
  ${NSD_CreateLabel} 0 215 ${WIN_WIDTH} 45 "${PRODUCTNAME} is Ready!"
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontTitle 1
  ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ; 5. Finish Subtitle
  ${NSD_CreateLabel} 0 265 ${WIN_WIDTH} 24 "Installation completed successfully."
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontSub 1
  ${NSD_AddStyle} $0 0x00000081 ; SS_CENTER | SS_NOPREFIX

  ; 6. Launch checkbox: "Launch BatPlayer now"
  ; Real button-class checkboxes paint an opaque white face that cannot be
  ; themed here (the nsDialogs page proc never forwards WM_CTLCOLORBTN), so the
  ; toggle is drawn with two clickable statics instead: a glyph + a label,
  ; styled straight onto the dark background.
  StrCpy $FinishLaunchState 1
  ${NSD_CreateLabel} 295 311 34 30 "☑"
  Pop $FinishLaunchGlyph
  SetCtlColors $FinishLaunchGlyph "${THEME_ACCENT}" "${THEME_PRIMARY_BG}"
  SendMessage $FinishLaunchGlyph ${WM_SETFONT} $WelcomeFontSub 1
  ${NSD_OnClick} $FinishLaunchGlyph BatPlayerLaunchToggleClick

  ${NSD_CreateLabel} 331 315 190 26 "Launch ${PRODUCTNAME} now"
  Pop $0
  SetCtlColors $0 "${THEME_TEXT_WHITE}" "${THEME_PRIMARY_BG}"
  SendMessage $0 ${WM_SETFONT} $WelcomeFontSub 1
  ${NSD_OnClick} $0 BatPlayerLaunchToggleClick

  ; 7. Finish Button (Vibrant Yellow pill)
  Push 250
  Push 360
  Push 260
  Push 50
  Push "Finish"
  Call BatPlayerCreateYellowPill
  Pop $FinishBtn
  ${NSD_OnClick} $FinishBtn BatPlayerFinishClick

  ; Update desktop shortcut
  Call CreateOrUpdateDesktopShortcut

  nsDialogs::Show
FunctionEnd

Function BatPlayerLaunchToggleClick
  ; Toggle the dark checkbox pair (glyph + label share this handler).
  ${If} $FinishLaunchState = 1
    StrCpy $FinishLaunchState 0
    ${NSD_SetText} $FinishLaunchGlyph "☐"
    SetCtlColors $FinishLaunchGlyph "${THEME_TEXT_MUTED}" "${THEME_PRIMARY_BG}"
  ${Else}
    StrCpy $FinishLaunchState 1
    ${NSD_SetText} $FinishLaunchGlyph "☑"
    SetCtlColors $FinishLaunchGlyph "${THEME_ACCENT}" "${THEME_PRIMARY_BG}"
  ${EndIf}
FunctionEnd

Function BatPlayerFinishClick
  ${If} $FinishLaunchState = 1
    Call RunMainBinary
  ${EndIf}
  ; NOTE: A bare Quit does NOT escape the nsDialogs::Show pump, and WM_CLOSE is
  ; page-dependent: it closes the installer from mid-flow pages (the working X
  ; buttons on the welcome/reinstall pages) but does NOTHING on the last page.
  ; The native escape is to click the wizard's own Next button (ID 1) - on the
  ; final page NSIS treats that as "Finish" and shutdown is immediate. This is
  ; the same trick the reinstall page's Continue pill uses to advance.
  GetDlgItem $0 $HWNDPARENT 1
  EnableWindow $0 1
  SendMessage $0 ${BM_CLICK} 0 0
FunctionEnd

Function BatPlayerFinishLeave
FunctionEnd

; WM_CLOSE is page-dependent: from the FINAL page it does nothing (verified
; empirically: window stayed open 20s+), so the finish page's X button must
; use the wizard's native Next button (ID 1) like BatPlayerFinishClick does.
; Does NOT launch the app - closing is just closing.
Function BatPlayerFinishCloseClick
  GetDlgItem $0 $HWNDPARENT 1
  EnableWindow $0 1
  SendMessage $0 ${BM_CLICK} 0 0
FunctionEnd

Function RunMainBinary
  ; NOTE: nsis_tauri_utils::RunAsUser hung forever here when invoked from the
  ; finish-page click handler (installer window never closed, Quit never
  ; reached). currentUser installers run non-elevated, so a plain non-blocking
  ; Exec is both correct and immediate.
  Exec '"$INSTDIR\${MAINBINARYNAME}.exe"'
FunctionEnd

; Uninstaller Pages
; 1. Confirm uninstall page
Var DeleteAppDataCheckbox
Var DeleteAppDataCheckboxState
!define /ifndef WS_EX_LAYOUTRTL         0x00400000
!define MUI_PAGE_CUSTOMFUNCTION_SHOW un.ConfirmShow
Function un.ConfirmShow ; Add add a `Delete app data` check box
  ; $1 inner dialog HWND
  ; $2 window DPI
  ; $3 style
  ; $4 x
  ; $5 y
  ; $6 width
  ; $7 height
  FindWindow $1 "#32770" "" $HWNDPARENT ; Find inner dialog
  System::Call "user32::GetDpiForWindow(p r1) i .r2"
  ${If} $(^RTL) = 1
    StrCpy $3 "${__NSD_CheckBox_EXSTYLE} | ${WS_EX_LAYOUTRTL}"
    IntOp $4 50 * $2
  ${Else}
    StrCpy $3 "${__NSD_CheckBox_EXSTYLE}"
    IntOp $4 0 * $2
  ${EndIf}
  IntOp $5 100 * $2
  IntOp $6 400 * $2
  IntOp $7 25 * $2
  IntOp $4 $4 / 96
  IntOp $5 $5 / 96
  IntOp $6 $6 / 96
  IntOp $7 $7 / 96
  System::Call 'user32::CreateWindowEx(i r3, w "${__NSD_CheckBox_CLASS}", w "$(deleteAppData)", i ${__NSD_CheckBox_STYLE}, i r4, i r5, i r6, i r7, p r1, i0, i0, i0) i .s'
  Pop $DeleteAppDataCheckbox
  SendMessage $HWNDPARENT ${WM_GETFONT} 0 0 $1
  SendMessage $DeleteAppDataCheckbox ${WM_SETFONT} $1 1
FunctionEnd
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE un.ConfirmLeave
Function un.ConfirmLeave
  SendMessage $DeleteAppDataCheckbox ${BM_GETCHECK} 0 0 $DeleteAppDataCheckboxState
FunctionEnd
!define MUI_PAGE_CUSTOMFUNCTION_PRE un.SkipIfPassive
!insertmacro MUI_UNPAGE_CONFIRM

; 2. Uninstalling Page
!insertmacro MUI_UNPAGE_INSTFILES

;Languages
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Arabic"
!insertmacro MUI_RESERVEFILE_LANGDLL
{{#each language_files}}
  !include "{{this}}"
{{/each}}

Function .onInit
  ${GetOptions} $CMDLINE "/P" $PassiveMode
  ${IfNot} ${Errors}
    StrCpy $PassiveMode 1
  ${EndIf}

  ${GetOptions} $CMDLINE "/NS" $NoShortcutMode
  ${IfNot} ${Errors}
    StrCpy $NoShortcutMode 1
  ${EndIf}

  ${GetOptions} $CMDLINE "/UPDATE" $UpdateMode
  ${IfNot} ${Errors}
    StrCpy $UpdateMode 1
  ${EndIf}

  !insertmacro SetContext

  ${If} $INSTDIR == "${PLACEHOLDER_INSTALL_DIR}"
    ; Set default install location
    !if "${INSTALLMODE}" == "perMachine"
      ${If} ${RunningX64}
        !if "${ARCH}" == "x64"
          StrCpy $INSTDIR "$PROGRAMFILES64\${PRODUCTNAME}"
        !else if "${ARCH}" == "arm64"
          StrCpy $INSTDIR "$PROGRAMFILES64\${PRODUCTNAME}"
        !else
          StrCpy $INSTDIR "$PROGRAMFILES\${PRODUCTNAME}"
        !endif
      ${Else}
        StrCpy $INSTDIR "$PROGRAMFILES\${PRODUCTNAME}"
      ${EndIf}
    !else if "${INSTALLMODE}" == "currentUser"
      StrCpy $INSTDIR "$LOCALAPPDATA\${PRODUCTNAME}"
    !endif

    Call RestorePreviousInstallLocation
  ${EndIf}


  !if "${INSTALLMODE}" == "both"
    !insertmacro MULTIUSER_INIT
  !endif

  ; Abort downgrades if they are disabled, in the modes that skip the reinstall page choice:
  ; silent, passive and update
  !if "${ALLOWDOWNGRADES}" == "false"
  ${If} ${Silent}
  ${OrIf} $PassiveMode = 1
  ${OrIf} $UpdateMode = 1
    ReadRegStr $R0 SHCTX "${UNINSTKEY}" "DisplayVersion"
    nsis_tauri_utils::SemverCompare "${VERSION}" $R0
    Pop $R0
    ; If downgrading
    ${If} $R0 = -1
      ${If} ${Silent}
        System::Call 'kernel32::AttachConsole(i -1)i.r0'
        ${If} $0 <> 0
          System::Call 'kernel32::GetStdHandle(i -11)i.r0'
          System::call 'kernel32::SetConsoleTextAttribute(i r0, i 0x0004)' ; set red color
          FileWrite $0 "$(silentDowngrades)"
        ${EndIf}
      ${Else}
        MessageBox MB_ICONSTOP "$(silentDowngrades)"
      ${EndIf}
      Abort
    ${EndIf}
  ${EndIf}
  !endif
FunctionEnd

Section WebView2
  ; Check if Webview2 is already installed and skip this section
  ${If} ${RunningX64}
    ReadRegStr $4 HKLM "SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\${WEBVIEW2APPGUID}" "pv"
  ${Else}
    ReadRegStr $4 HKLM "SOFTWARE\Microsoft\EdgeUpdate\Clients\${WEBVIEW2APPGUID}" "pv"
  ${EndIf}
  ${If} $4 == ""
    ReadRegStr $4 HKCU "SOFTWARE\Microsoft\EdgeUpdate\Clients\${WEBVIEW2APPGUID}" "pv"
  ${EndIf}

  ${If} $4 == ""
    ; Webview2 installation
    ;
    ; Skip if updating
    ${If} $UpdateMode <> 1
      !if "${INSTALLWEBVIEW2MODE}" == "downloadBootstrapper"
        Delete "$TEMP\MicrosoftEdgeWebview2Setup.exe"
        DetailPrint "$(webview2Downloading)"
        NSISdl::download "https://go.microsoft.com/fwlink/p/?LinkId=2124703" "$TEMP\MicrosoftEdgeWebview2Setup.exe"
        Pop $0
        ${If} $0 == "success"
          DetailPrint "$(webview2DownloadSuccess)"
        ${Else}
          DetailPrint "$(webview2DownloadError)"
          Abort "$(webview2AbortError)"
        ${EndIf}
        StrCpy $6 "$TEMP\MicrosoftEdgeWebview2Setup.exe"
        Goto install_webview2
      !endif

      !if "${INSTALLWEBVIEW2MODE}" == "embedBootstrapper"
        Delete "$TEMP\MicrosoftEdgeWebview2Setup.exe"
        File "/oname=$TEMP\MicrosoftEdgeWebview2Setup.exe" "${WEBVIEW2BOOTSTRAPPERPATH}"
        DetailPrint "$(installingWebview2)"
        StrCpy $6 "$TEMP\MicrosoftEdgeWebview2Setup.exe"
        Goto install_webview2
      !endif

      !if "${INSTALLWEBVIEW2MODE}" == "offlineInstaller"
        Delete "$TEMP\MicrosoftEdgeWebView2RuntimeInstaller.exe"
        File "/oname=$TEMP\MicrosoftEdgeWebView2RuntimeInstaller.exe" "${WEBVIEW2INSTALLERPATH}"
        DetailPrint "$(installingWebview2)"
        StrCpy $6 "$TEMP\MicrosoftEdgeWebView2RuntimeInstaller.exe"
        Goto install_webview2
      !endif

      Goto webview2_done

      install_webview2:
        DetailPrint "$(installingWebview2)"
        ; $6 holds the path to the webview2 installer
        ExecWait "$6 ${WEBVIEW2INSTALLERARGS} /install" $1
        ${If} $1 = 0
          DetailPrint "$(webview2InstallSuccess)"
        ${Else}
          DetailPrint "$(webview2InstallError)"
          Abort "$(webview2AbortError)"
        ${EndIf}
      webview2_done:
    ${EndIf}
  ${Else}
    !if "${MINIMUMWEBVIEW2VERSION}" != ""
      ${VersionCompare} "${MINIMUMWEBVIEW2VERSION}" "$4" $R0
      ${If} $R0 = 1
        update_webview:
          DetailPrint "$(installingWebview2)"
          ${If} ${RunningX64}
            ReadRegStr $R1 HKLM "SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate" "path"
          ${Else}
            ReadRegStr $R1 HKLM "SOFTWARE\Microsoft\EdgeUpdate" "path"
          ${EndIf}
          ${If} $R1 == ""
            ReadRegStr $R1 HKCU "SOFTWARE\Microsoft\EdgeUpdate" "path"
          ${EndIf}
          ${If} $R1 != ""
            ; Chromium updater docs: https://source.chromium.org/chromium/chromium/src/+/main:docs/updater/user_manual.md
            ; Modified from "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView\ModifyPath"
            ExecWait `"$R1" /install appguid=${WEBVIEW2APPGUID}&needsadmin=true` $1
            ${If} $1 = 0
              DetailPrint "$(webview2InstallSuccess)"
            ${Else}
              MessageBox MB_ICONEXCLAMATION|MB_ABORTRETRYIGNORE "$(webview2InstallError)" IDIGNORE ignore IDRETRY update_webview
              Quit
              ignore:
            ${EndIf}
          ${EndIf}
      ${EndIf}
    !endif
  ${EndIf}
SectionEnd

Section Install
  SetOutPath $INSTDIR

  !ifmacrodef NSIS_HOOK_PREINSTALL
    !insertmacro NSIS_HOOK_PREINSTALL
  !endif

  !insertmacro CheckIfAppIsRunning "$INSTDIR\${MAINBINARYNAME}.exe" "${PRODUCTNAME}"

  ; Copy main executable
  File "${MAINBINARYSRCPATH}"

  ; Copy resources
    CreateDirectory "$INSTDIR\"
    File /a "/oname=libmpv-2.dll" "${__FILEDIR__}\..\..\..\..\mpv\libmpv-2.dll"

  ; Copy external binaries

  ; Create file associations

  ; Register deep links

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Save $INSTDIR in registry for future installations
  WriteRegStr SHCTX "${MANUPRODUCTKEY}" "" $INSTDIR

  !if "${INSTALLMODE}" == "both"
    ; Save install mode to be selected by default for the next installation such as updating
    ; or when uninstalling
    WriteRegStr SHCTX "${UNINSTKEY}" $MultiUser.InstallMode 1
  !endif

  ; Remove old main binary if it doesn't match new main binary name
  ReadRegStr $OldMainBinaryName SHCTX "${UNINSTKEY}" "MainBinaryName"
  ${If} $OldMainBinaryName != ""
  ${AndIf} $OldMainBinaryName != "${MAINBINARYNAME}.exe"
    Delete "$INSTDIR\$OldMainBinaryName"
  ${EndIf}

  ; Save current MAINBINARYNAME for future updates
  WriteRegStr SHCTX "${UNINSTKEY}" "MainBinaryName" "${MAINBINARYNAME}.exe"

  ; Registry information for add/remove programs
  WriteRegStr SHCTX "${UNINSTKEY}" "DisplayName" "${PRODUCTNAME}"
  WriteRegStr SHCTX "${UNINSTKEY}" "DisplayIcon" "$\"$INSTDIR\${MAINBINARYNAME}.exe$\""
  WriteRegStr SHCTX "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr SHCTX "${UNINSTKEY}" "Publisher" "${MANUFACTURER}"
  WriteRegStr SHCTX "${UNINSTKEY}" "InstallLocation" "$\"$INSTDIR$\""
  WriteRegStr SHCTX "${UNINSTKEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD SHCTX "${UNINSTKEY}" "NoModify" "1"
  WriteRegDWORD SHCTX "${UNINSTKEY}" "NoRepair" "1"

  ${GetSize} "$INSTDIR" "/M=uninstall.exe /S=0K /G=0" $0 $1 $2
  IntOp $0 $0 + ${ESTIMATEDSIZE}
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD SHCTX "${UNINSTKEY}" "EstimatedSize" "$0"

  !if "${HOMEPAGE}" != ""
    WriteRegStr SHCTX "${UNINSTKEY}" "URLInfoAbout" "${HOMEPAGE}"
    WriteRegStr SHCTX "${UNINSTKEY}" "URLUpdateInfo" "${HOMEPAGE}"
    WriteRegStr SHCTX "${UNINSTKEY}" "HelpLink" "${HOMEPAGE}"
  !endif

  ; Create start menu shortcut
  !insertmacro MUI_STARTMENU_WRITE_BEGIN Application
    Call CreateOrUpdateStartMenuShortcut
  !insertmacro MUI_STARTMENU_WRITE_END

  ; Create desktop shortcut for silent and passive installers
  ; because finish page will be skipped
  ${If} $PassiveMode = 1
  ${OrIf} ${Silent}
    Call CreateOrUpdateDesktopShortcut
  ${EndIf}

  !ifmacrodef NSIS_HOOK_POSTINSTALL
    !insertmacro NSIS_HOOK_POSTINSTALL
  !endif

  ; Auto-close the instfiles page on completion so the custom finish page is
  ; reached without user interaction (the wizard Next button stays hidden).
  SetAutoClose true
  ; Auto close this page for passive mode
  ${If} $PassiveMode = 1
    SetAutoClose true
  ${EndIf}
SectionEnd

Function .onInstSuccess
  ; Check for `/R` flag only in silent and passive installers because
  ; GUI installer has a toggle for the user to (re)start the app
  ${If} $PassiveMode = 1
  ${OrIf} ${Silent}
    ${GetOptions} $CMDLINE "/R" $R0
    ${IfNot} ${Errors}
      ${GetOptions} $CMDLINE "/ARGS" $R0
      nsis_tauri_utils::RunAsUser "$INSTDIR\${MAINBINARYNAME}.exe" "$R0"
    ${EndIf}
  ${EndIf}
FunctionEnd

Function un.onInit
  !insertmacro SetContext

  !if "${INSTALLMODE}" == "both"
    !insertmacro MULTIUSER_UNINIT
  !endif

  !insertmacro MUI_UNGETLANGUAGE

  ${GetOptions} $CMDLINE "/P" $PassiveMode
  ${IfNot} ${Errors}
    StrCpy $PassiveMode 1
  ${EndIf}

  ${GetOptions} $CMDLINE "/UPDATE" $UpdateMode
  ${IfNot} ${Errors}
    StrCpy $UpdateMode 1
  ${EndIf}
FunctionEnd

Section Uninstall

  !ifmacrodef NSIS_HOOK_PREUNINSTALL
    !insertmacro NSIS_HOOK_PREUNINSTALL
  !endif

  !insertmacro CheckIfAppIsRunning "$INSTDIR\${MAINBINARYNAME}.exe" "${PRODUCTNAME}"

  ; Delete the app directory and its content from disk
  ; Copy main executable
  Delete "$INSTDIR\${MAINBINARYNAME}.exe"

  ; Delete resources
    Delete "$INSTDIR\libmpv-2.dll"

  ; Delete external binaries

  ; Delete app associations

  ; Delete deep links


  ; Delete uninstaller
  Delete "$INSTDIR\uninstall.exe"

  RMDir "$INSTDIR"

  ; Remove shortcuts if not updating
  ${If} $UpdateMode <> 1
    !insertmacro DeleteAppUserModelId

    ; Remove start menu shortcut
    !insertmacro MUI_STARTMENU_GETFOLDER Application $AppStartMenuFolder
    !insertmacro IsShortcutTarget "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    Pop $0
    ${If} $0 = 1
      !insertmacro UnpinShortcut "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk"
      Delete "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk"
      RMDir "$SMPROGRAMS\$AppStartMenuFolder"
    ${EndIf}
    !insertmacro IsShortcutTarget "$SMPROGRAMS\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    Pop $0
    ${If} $0 = 1
      !insertmacro UnpinShortcut "$SMPROGRAMS\${PRODUCTNAME}.lnk"
      Delete "$SMPROGRAMS\${PRODUCTNAME}.lnk"
    ${EndIf}

    ; Remove desktop shortcuts
    !insertmacro IsShortcutTarget "$DESKTOP\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    Pop $0
    ${If} $0 = 1
      !insertmacro UnpinShortcut "$DESKTOP\${PRODUCTNAME}.lnk"
      Delete "$DESKTOP\${PRODUCTNAME}.lnk"
    ${EndIf}
  ${EndIf}

  ; Remove registry information for add/remove programs
  !if "${INSTALLMODE}" == "both"
    DeleteRegKey SHCTX "${UNINSTKEY}"
  !else if "${INSTALLMODE}" == "perMachine"
    DeleteRegKey HKLM "${UNINSTKEY}"
  !else
    DeleteRegKey HKCU "${UNINSTKEY}"
  !endif

  ; Removes the Autostart entry for ${PRODUCTNAME} from the HKCU Run key if it exists.
  ; This ensures the program does not launch automatically after uninstallation if it exists.
  ; If it doesn't exist, it does nothing.
  ; We do this when not updating (to preserve the registry value on updates)
  ${If} $UpdateMode <> 1
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCTNAME}"
  ${EndIf}

  ; Delete app data if the checkbox is selected
  ; and if not updating
  ${If} $DeleteAppDataCheckboxState = 1
  ${AndIf} $UpdateMode <> 1
    ; Clear the install location $INSTDIR from registry
    DeleteRegKey SHCTX "${MANUPRODUCTKEY}"
    DeleteRegKey /ifempty SHCTX "${MANUKEY}"

    ; Clear the install language from registry
    DeleteRegValue HKCU "${MANUPRODUCTKEY}" "Installer Language"
    DeleteRegKey /ifempty HKCU "${MANUPRODUCTKEY}"
    DeleteRegKey /ifempty HKCU "${MANUKEY}"

    SetShellVarContext current
    RmDir /r "$APPDATA\${BUNDLEID}"
    RmDir /r "$LOCALAPPDATA\${BUNDLEID}"
  ${EndIf}

  !ifmacrodef NSIS_HOOK_POSTUNINSTALL
    !insertmacro NSIS_HOOK_POSTUNINSTALL
  !endif

  ; Auto close if passive mode or updating
  ${If} $PassiveMode = 1
  ${OrIf} $UpdateMode = 1
    SetAutoClose true
  ${EndIf}
SectionEnd

Function RestorePreviousInstallLocation
  ReadRegStr $4 SHCTX "${MANUPRODUCTKEY}" ""
  StrCmp $4 "" +2 0
    StrCpy $INSTDIR $4
FunctionEnd

Function Skip
  Abort
FunctionEnd

Function SkipIfPassive
  ${IfThen} $PassiveMode = 1  ${|} Abort ${|}
FunctionEnd
Function un.SkipIfPassive
  ${IfThen} $PassiveMode = 1  ${|} Abort ${|}
FunctionEnd

Function CreateOrUpdateStartMenuShortcut
  ; We used to use product name as MAINBINARYNAME
  ; migrate old shortcuts to target the new MAINBINARYNAME
  StrCpy $R0 0

  !insertmacro IsShortcutTarget "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk" "$INSTDIR\$OldMainBinaryName"
  Pop $0
  ${If} $0 = 1
    !insertmacro SetShortcutTarget "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    StrCpy $R0 1
  ${EndIf}

  !insertmacro IsShortcutTarget "$SMPROGRAMS\${PRODUCTNAME}.lnk" "$INSTDIR\$OldMainBinaryName"
  Pop $0
  ${If} $0 = 1
    !insertmacro SetShortcutTarget "$SMPROGRAMS\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    StrCpy $R0 1
  ${EndIf}

  ${If} $R0 = 1
    Return
  ${EndIf}

  ; Skip creating shortcut if in update mode or no shortcut mode
  ; but always create if migrating from wix
  ${If} $WixMode = 0
    ${If} $UpdateMode = 1
    ${OrIf} $NoShortcutMode = 1
      Return
    ${EndIf}
  ${EndIf}

  !if "${STARTMENUFOLDER}" != ""
    CreateDirectory "$SMPROGRAMS\$AppStartMenuFolder"
    CreateShortcut "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    !insertmacro SetLnkAppUserModelId "$SMPROGRAMS\$AppStartMenuFolder\${PRODUCTNAME}.lnk"
  !else
    CreateShortcut "$SMPROGRAMS\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    !insertmacro SetLnkAppUserModelId "$SMPROGRAMS\${PRODUCTNAME}.lnk"
  !endif
FunctionEnd

Function CreateOrUpdateDesktopShortcut
  ; We used to use product name as MAINBINARYNAME
  ; migrate old shortcuts to target the new MAINBINARYNAME
  !insertmacro IsShortcutTarget "$DESKTOP\${PRODUCTNAME}.lnk" "$INSTDIR\$OldMainBinaryName"
  Pop $0
  ${If} $0 = 1
    !insertmacro SetShortcutTarget "$DESKTOP\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
    Return
  ${EndIf}

  ; Skip creating shortcut if in update mode or no shortcut mode
  ; but always create if migrating from wix
  ${If} $WixMode = 0
    ${If} $UpdateMode = 1
    ${OrIf} $NoShortcutMode = 1
      Return
    ${EndIf}
  ${EndIf}

  CreateShortcut "$DESKTOP\${PRODUCTNAME}.lnk" "$INSTDIR\${MAINBINARYNAME}.exe"
  !insertmacro SetLnkAppUserModelId "$DESKTOP\${PRODUCTNAME}.lnk"
FunctionEnd
