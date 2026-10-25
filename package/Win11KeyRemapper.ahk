; Windows 11 Key Remapper - launcher
;
; In the release zip, Win11KeyRemapper.exe next to this file is the official
; AutoHotkey v2 runtime (AutoHotkey64.exe), unmodified, only renamed. Run
; without a script, AutoHotkey runs the .ahk with its own name: this file.
; It starts the app with the same runtime, so nothing needs to be installed.
; (Windows' Smart App Control trusts that runtime; it blocks unsigned exes
; that it doesn't know, like a compiled script would be.)
#Requires AutoHotkey v2.0
#NoTrayIcon

args := ""
for arg in A_Args
    args .= ' "' arg '"'
Run('"' A_AhkPath '" "' A_ScriptDir '\src\Win11KeyRemapper.ahk"' args, A_ScriptDir "\src")
