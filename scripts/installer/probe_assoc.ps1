# Verifies the file-association registry keys the installer writes (run it
# after a real install; exactly the surface Windows "Open with" and
# Settings > Default apps enumerate). Read-only probe.
#
#   powershell -ExecutionPolicy Bypass -File scripts\installer\probe_assoc.ps1
#
# Expects BatPlayer.Media as the ProgID and reports, per extension, whether
# the app is on the "Open with" list and whether the extension's DEFAULT was
# left untouched (registration is additive by design).
$ErrorActionPreference = 'SilentlyContinue'

# Mirrors src/utils/media.ts MEDIA_EXTENSIONS and the installer template.
$exts = 'mkv', 'mp4', 'm4v', 'avi', 'mov', 'webm', 'wmv', 'flv', 'ts', 'm2ts',
    'mts', 'mpg', 'mpeg', 'vob', 'ogv', 'mp3', 'm4a', 'aac', 'flac', 'wav',
    'ogg', 'opus', 'wma'
$progid = 'BatPlayer.Media'

$fail = 0

function Check($name, $ok, $detail) {
    $mark = if ($ok) { 'OK  ' } else { 'FAIL' }
    if (-not $ok) { $script:fail++ }
    "{0} {1,-46} {2}" -f $mark, $name, ($(if ($detail) { $detail }))
}

$cmd = (Get-ItemProperty "HKCU:\Software\Classes\$progid\shell\open\command").'(default)'
$icon = (Get-ItemProperty "HKCU:\Software\Classes\$progid\DefaultIcon").'(default)'
$descr = (Get-ItemProperty "HKCU:\Software\Classes\$progid").'(default)'
Check "ProgID default description" ($descr -like '*BatPlayer*') $descr
Check "ProgID DefaultIcon points at the exe" ($icon -is [string] -and $icon -like '*batplayer.exe*,0') $icon
Check "ProgID open command has a %1 placeholder" ($cmd -is [string] -and $cmd -like '*batplayer.exe*" "%1"*') $cmd

$cap = "HKCU:\Software\BatSoft\BatPlayer\Capabilities"
$appName = (Get-ItemProperty $cap).ApplicationName
$appDescr = (Get-ItemProperty $cap).ApplicationDescription
Check "Capabilities.ApplicationName" ($appName -eq 'BatPlayer') $appName
Check "Capabilities.ApplicationDescription set" ([bool]$appDescr) $appDescr

$missing = @()
$defaults = @{}
foreach ($ext in $exts) {
    $listed = (Get-ItemProperty "HKCU:\Software\Classes\.$ext\OpenWithProgids").PSObject.Properties |
        Where-Object Name -eq $progid
    if (-not $listed) { $missing += $ext }
    $assocOk = (Get-Item "$cap\FileAssociations").GetValueNames() -contains ".$ext"
    if ($assocOk -and $listed) {
        $defaults[$ext] = (Get-ItemProperty "HKCU:\Software\Classes\.$ext").'(default)'
    } elseif (-not $assocOk) {
        $fail++
        "FAIL Capabilities/.${ext} association missing"
    }
}
Check "OpenWithProgids lists the app for ALL $($exts.Count) extensions" ($missing.Count -eq 0) ($missing -join ' ')

$regApp = (Get-Item 'HKCU:\Software\RegisteredApplications').GetValue('BatPlayer')
Check "RegisteredApplications name value" ($regApp -is [string] -and $regApp -like '*\Capabilities') $regApp

$taken = $defaults.GetEnumerator() | Where-Object Value -eq $progid
$defaultCheck = ($defaults.Count -gt 0 -and $taken.Count -eq 0) -or
    ($defaults.Count -eq 0)
Check "no extension default taken over (additive registration)" $defaultCheck `
    ($(if ($taken.Count -gt 0) { ($taken | ForEach-Object { ".$($_.Name)" }) -join ' ' } else { "defaults: $($defaults.Count) present, none = $progid" }))

""
"result: $fail failure(s)"
if ($fail -gt 0) { exit 1 }
