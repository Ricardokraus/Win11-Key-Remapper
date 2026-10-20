#Requires AutoHotkey v2.0
#SingleInstance Off                     ; handled in Main(): a 2nd launch opens the settings
Persistent

;@Ahk2Exe-SetName Windows 11 Key Remapper
;@Ahk2Exe-SetDescription Windows 11 Key Remapper
;@Ahk2Exe-SetVersion 0.5.3
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Ricardo - MIT License
;@Ahk2Exe-SetOrigFilename Win11KeyRemapper.exe
;@Ahk2Exe-SetMainIcon ..\assets\icon.ico

; ============================================================================
; Windows 11 Key Remapper (NitroSense Key Remapper)
; https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense - MIT License
;
; Remaps the Acer NitroSense key (or any other key) with a single low-level
; keyboard hook (WH_KEYBOARD_LL), plus an optional shortcut that opens the
; NitroSense app. Settings live in settings.ini and are edited from a small
; window opened from the tray icon.
;
; Why it is built like this (details in docs/DEVELOPMENT.md):
; - The NitroSense key reports VK 0xFF, which AutoHotkey can't hotkey
;   reliably, and other Acer keys share that VK (Win Lock on/off). So keys
;   are matched by VK + scan code inside our own hook.
; - The hook swallows the source key so Windows and the vendor software
;   never see it (that used to cause double toggles).
; - Modifiers are tracked by the hook itself: GetKeyState is unreliable for
;   them in some situations.
; - The hook never does real work: actions go through a queue that runs on
;   a timer. Windows silently removes hooks that respond too slowly.
; ============================================================================

#Include %A_ScriptDir%\lib\GlassToast.ahk

APP := {name: "Windows 11 Key Remapper", short: "Key Remapper", version: "0.5.3"
      , repo: "https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense"
      , api: "https://api.github.com/repos/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest"
      , lnk: A_Startup "\Windows 11 Key Remapper.lnk"
      , dataDir: A_AppData "\Win11KeyRemapper"}

; Finding the running copy: its hidden main window gets this title, and a
; second launch posts it INSTANCE_MSG ("open your settings") before exiting.
; The title is also what Windows shows if it lists the app while shutting
; down, so it's the app's name (up to 0.5.2 it was an internal name, still
; recognized so an older copy that's running is found too).
INSTANCE_TITLE := "Windows 11 Key Remapper"
INSTANCE_TITLES := [INSTANCE_TITLE, "Win11KeyRemapper.Instance"]
INSTANCE_MSG := DllCall("RegisterWindowMessage", "str", "Win11KeyRemapper.ShowSettings", "uint")

; A key-down that arrives this soon after the previous one, without a key-up
; in between, is keyboard auto-repeat. Must exceed the longest Windows repeat
; delay (1 s), otherwise holding the key would toggle twice.
REPEAT_MS := 1500

MODES       := ["Key", "Disable", "None"]
MODE_LABELS := ["Press another key or shortcut", "Do nothing (disable the key)", "Keep its normal behavior"]
ACTION_INFO := Map("Key", "Presses the key below instead. Num, Caps and Scroll Lock toggle once while held."
                 , "Disable", "The key does nothing at all."
                 , "None", "The key works as it normally would. The shortcut below still works.")
; Before v0.5.0 the lock keys were modes of their own; they're now "press that key"
LEGACY_MODES := Map("numlock", [0x90, 0x145], "capslock", [0x14, 0x3A], "scrolllock", [0x91, 0x46])
LOCK_VKS     := Map(0x90, true, 0x14, true, 0x91, true)     ; a held lock key must not repeat
THEME_PREFS := ["System", "Light", "Dark"]
TOAST_POSITIONS := ["TopCenter", "TopRight", "TopLeft", "BottomCenter", "BottomRight", "BottomLeft"]
TOAST_POSITION_LABELS := ["Top center", "Top right", "Top left", "Bottom center", "Bottom right", "Bottom left"]
TOAST_ANIMS := ["Slide", "Fade", "None"]
TOAST_ANIM_LABELS := ["Slide in", "Fade in", "None (just appear)"]
TOAST_WHENS := ["Always", "Startup", "Never"]
TOAST_WHEN_LABELS := ["Always", "Only when the app starts", "Never"]

; Settings window sections: id, title, Segoe Fluent Icons / MDL2 glyph
PAGES := [["general", "General", 0xE713], ["keys", "Keys", 0xE765], ["notifications", "Notifications", 0xEA8F]
        , ["updates", "Updates", 0xE895], ["advanced", "Advanced", 0xE90F], ["about", "About", 0xE946]]
; About: groups of links (title, path on the GitHub page, glyph)
LINKS := [["Feedback", [["Tell us it works on your laptop", "/issues/new?template=works_on_my_laptop.yml", 0xE7F8]
                      , ["Report a bug", "/issues/new?template=bug_report.yml", 0xEBE8]
                      , ["Suggest a feature", "/issues/new?template=feature_request.yml", 0xEA80]]]
        , ["Help", [["Frequently asked questions", "/blob/main/docs/FAQ.md", 0xE897]
                  , ["Ask a question", "/issues/new?template=question.yml", 0xE8BD]]]]
; Titles of the "saved" notices for each switch
SWITCH_LABELS := Map("remapping", "Remapping", "autostart", "Start with Windows", "trayIcon", "Tray icon"
                   , "launchEnabled", "App shortcut", "distinguish", "Distinguish left and right"
                   , "toastGlass", "Transparency effects", "checkUpdates", "Automatic update checks"
                   , "matchSC", "Exact key match", "log", "Developer log")

; Settings window colors (RGB). "dim" is used for disabled rows; nav* are
; sidebar entries, row* the clickable rows on a card, btn* the buttons (the
; lip is the darker edge under a button, gone while it's pressed).
THEMES := Map("light", {dark: false, win: 0xF3F3F3, card: 0xFFFFFF, border: 0xE3E3E3
                      , navSel: 0xE6E6E6, navHover: 0xEBEBEB, navPress: 0xE0E0E0
                      , rowHover: 0xF5F5F5, rowPress: 0xEEEEEE
                      , text: 0x1A1A1A, sub: 0x616161, dim: 0xA8A8A8
                      , on: 0x1E9E48, knobOn: 0xFFFFFF, off: 0x8A8A8A, knobOff: 0x616161
                      , keyFace: 0xFAFAFA, keyEdge: 0xCFCFCF, keyShade: 0xC9C9C9, keyText: 0x1A1A1A
                      , btnFace: 0xFDFDFD, btnHover: 0xF4F4F4, btnEdge: 0xD5D5D5, btnLip: 0xC2C2C2
                      , danger: 0xC42B1C, dangerFill: 0xC42B1C, dangerLip: 0x8A1E14, onDanger: 0xFFFFFF
                      , accent: 0x1E9E48, accentLip: 0x146B31, onAccent: 0xFFFFFF, ok: 0x13803A, warn: 0xC42B1C}
            , "dark", {dark: true, win: 0x202020, card: 0x2B2B2B, border: 0x3A3A3A
                      , navSel: 0x2D2D2D, navHover: 0x292929, navPress: 0x262626
                      , rowHover: 0x323232, rowPress: 0x2F2F2F
                      , text: 0xF3F3F3, sub: 0xABABAB, dim: 0x6B6B6B
                      , on: 0x30D158, knobOn: 0x0F2A17, off: 0x9E9E9E, knobOff: 0xCFCFCF
                      , keyFace: 0x3D3D3D, keyEdge: 0x505050, keyShade: 0x171717, keyText: 0xF3F3F3
                      , btnFace: 0x383838, btnHover: 0x414141, btnEdge: 0x474747, btnLip: 0x1A1A1A
                      , danger: 0xFF7B72, dangerFill: 0xDA3633, dangerLip: 0x8E1F1B, onDanger: 0xFFFFFF
                      , accent: 0x30D158, accentLip: 0x1E8A3A, onAccent: 0x0F2A17, ok: 0x6CCB5F, warn: 0xFF99A4})

; Side-specific modifiers, in display order
MOD_ORDER  := ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
MOD_VK     := Map("LCtrl", 0xA2, "RCtrl", 0xA3, "LAlt", 0xA4, "RAlt", 0xA5
                , "LShift", 0xA0, "RShift", 0xA1, "LWin", 0x5B, "RWin", 0x5C)
VK_MOD     := Map(0xA2, "LCtrl", 0xA3, "RCtrl", 0xA4, "LAlt", 0xA5, "RAlt"
                , 0xA0, "LShift", 0xA1, "RShift", 0x5B, "LWin", 0x5C, "RWin"
                , 0x11, "LCtrl", 0x12, "LAlt", 0x10, "LShift")      ; generic VKs -> left side
MOD_FAMILY := Map("LCtrl", "Ctrl", "RCtrl", "Ctrl", "LAlt", "Alt", "RAlt", "Alt"
                , "LShift", "Shift", "RShift", "Shift", "LWin", "Win", "RWin", "Win")
MOD_LABEL  := Map("LCtrl", "Left Ctrl", "RCtrl", "Right Ctrl", "LAlt", "Left Alt", "RAlt", "Right Alt"
                , "LShift", "Left Shift", "RShift", "Right Shift", "LWin", "Left Win", "RWin", "Right Win")
MOD_ALIAS  := Map("ctrl", "LCtrl", "control", "LCtrl", "alt", "LAlt", "shift", "LShift", "win", "LWin")

; Acer keys that share VK 0xFF ("VK:SC", hex, SC with the extended bit)
KNOWN_KEYS := Map("FF:175", "NitroSense key", "FF:159", "Win Lock on", "FF:162", "Win Lock off")
KEY_NAMES  := Map("Numlock", "Num Lock", "AppsKey", "Menu key")

; settings.ini explains itself: it's written whole from this template, with a
; comment above every key. settings.example.ini is this text with the defaults
; (a test checks it). {Name} = the value of that key.
SETTINGS_TEMPLATE := "
(
; Windows 11 Key Remapper - settings
;
; The easy way: change everything in the settings window (tray icon > Settings...).
; You can also edit this file: save it, then restart the app (tray icon > Restart).
; The app writes this file again whenever you change something in the settings
; window, so comments of your own are lost. A missing or wrong value falls back
; to its default.
;
; VK = virtual-key code, SC = scan code, both in hex (0x...). The settings window
; shows them next to each key (Keys > Change...).

[Remap]

; The key to remap. Default: the Acer NitroSense key (VK 0xFF, SC 0x175).
SourceVK={SourceVK}
SourceSC={SourceSC}

; Exact key match. 1 = the scan code must match too (default). Keep it on for
; the NitroSense key: Win Lock on/off (Fn+Win) send the same VK 0xFF with
; SC 0x159 / 0x162. 0 = match the VK only.
MatchSC={MatchSC}

; What the key does:
;   Key     = press another key or shortcut, set below (default)
;   Disable = nothing at all
;   None    = keep its normal behavior (the app leaves it alone)
Mode={Mode}

; Mode=Key: the key to press instead. Default: Num Lock (VK 0x90, SC 0x145).
; TargetMods = modifiers held with it, comma-separated (empty = none):
;   LCtrl RCtrl LAlt RAlt LShift RShift LWin RWin
; Example, Ctrl+Shift+Esc: TargetMods=LCtrl,LShift  TargetVK=0x1B  TargetSC=0x1
TargetMods={TargetMods}
TargetVK={TargetVK}
TargetSC={TargetSC}

[Launcher]

; A shortcut that opens an app. 1 = on (default), 0 = off.
; Default: Right Ctrl + NitroSense key opens NitroSense.
LaunchEnabled={LaunchEnabled}

; Modifiers to hold, exactly these (same names as TargetMods; empty = none).
LaunchMods={LaunchMods}

; The shortcut's key.
LaunchVK={LaunchVK}
LaunchSC={LaunchSC}

; 1 = Ctrl, Alt, Shift and Win count on either side of the keyboard.
; 0 = only the side written in LaunchMods (default).
LaunchAnySide={LaunchAnySide}

; The app to open:
;   auto = find NitroSense by itself (default)
;   a path to an .exe or .lnk, e.g. C:\Program Files\Some App\app.exe
;   shell:AppsFolder\<AppID> for a Microsoft Store app
LaunchPath={LaunchPath}

[General]

; When to show the "app is running" notification:
;   Always  = at startup, after unlocking and when the screen turns on (default)
;   Startup = only when the app starts
;   Never   = no notifications on the desktop at all, except warnings
ToastWhen={ToastWhen}

; Where it appears: TopCenter (default), TopRight, TopLeft, BottomCenter,
; BottomRight or BottomLeft.
ToastPosition={ToastPosition}

; How it appears: Slide (default), Fade or None.
ToastAnimation={ToastAnimation}

; 1 = frosted glass that blurs what's behind it (default).
; 0 = a solid card in the settings window's colors, lighter for older PCs.
ToastTransparency={ToastTransparency}

; 1 = show the tray icon (default). 0 = hide it: open the app again to reach
; the settings.
TrayIcon={TrayIcon}

; 1 = look for a new version on GitHub once a day (default). 0 = only when you
; click Check now (Settings > Updates).
CheckUpdates={CheckUpdates}

; Colors of the settings window and the tray menu: System (follows Windows,
; default), Light or Dark.
Theme={Theme}

; Developer log. 1 = write what the app does, with times, to
; Win11KeyRemapper.log next to this file, to find out what went wrong.
; 0 = off (default). It never records the keys you type.
Log={Log}

)"

; ---- Runtime state ---------------------------------------------------------
SETTINGS_PATH := ""
CFG := {}                 ; active settings
DRAFT := {}               ; copy edited by the settings window
RT := {mode: "None", up: "", launchOn: false}   ; CFG precomputed for the hook
PAUSED := false
LOCKED := false           ; session locked (no toast on display-on then)
POWER_NOTIFY := 0
HELD := Map()             ; modifiers held down, tracked by the hook: name -> true
PRESS := Map()            ; keys whose down we handled: id -> {owner, t}
SWALLOW := Map()          ; keys whose key-up (and repeats) must be eaten: id -> tick
QUEUE := []               ; actions for RunQueue, in order
CAP := {active: false, target: "", mods: Map(), downs: Map(), result: 0}
HOOK := {proc: 0, h: 0}
NS := {checked: false, target: "", label: ""}   ; NitroSense auto-detection cache
UI := {gui: 0}
NT := {gui: 0, hwnd: 0, phase: "", last: ""}   ; the notice inside the settings window
; Settings window layout, in logical pixels
SL := {W: 820, H: 630, side: 220, cx: 236, cw: 560, rx: 780, kvX: 426, btnX: 684}
; Update check: state "" | checking | latest | available | error
UPD := {state: "", latest: "", page: "", zip: "", sums: "", req: 0, manual: false, t0: 0, notified: ""}
; Developer log (Settings > Advanced > Developer): file paths, lines since the size check
DEVLOG := {on: false, path: "", old: "", n: 0}
ENDING := false           ; Windows is shutting down or signing out: start nothing new

Main()

; ============================================================================
; Startup / exit
; ============================================================================

Main() {
    global SETTINGS_PATH, CFG, POWER_NOTIFY
    t0 := A_TickCount
    args := ParseArgs()
    if args.restartPid {
        try ProcessWaitClose(args.restartPid, 5)    ; restart/update: let the old copy exit first
    } else if (other := OtherInstance()) {
        ; Already running (maybe with the tray icon hidden): open its settings instead
        DllCall("AllowSetForegroundWindow", "uint", 0xFFFFFFFF)
        DllCall("PostMessage", "ptr", other, "uint", INSTANCE_MSG, "ptr", 0, "ptr", 0)
        ExitApp
    }
    MarkInstance()
    OnMessage(INSTANCE_MSG, OnInstanceMsg)
    if FileExist(A_ScriptFullPath ".old")   ; the previous exe, left by an update
        try FileDelete(A_ScriptFullPath ".old")
    ProcessSetPriority("High")              ; costs nothing, keeps the hook snappy under load
    if (!A_IsCompiled && FileExist(IconPath()))
        TraySetIcon(IconPath())

    SETTINGS_PATH := SettingsPath()
    firstRun := !FileExist(SETTINGS_PATH)
    CFG := firstRun ? DefaultSettings() : LoadSettings(SETTINGS_PATH)
    if (firstRun || !SettingsExplained(SETTINGS_PATH)) {   ; new, or from a version without the comments
        try WriteSettings(SETTINGS_PATH, CFG)
    }
    ApplySettings()                         ; also turns the log on, if it's on
    OnError(LogError)
    Log("Settings: " SETTINGS_PATH (firstRun ? " (first run)" : "") " | " Summary())
    ApplyAppTheme(CFG.theme)                ; dark/light tray menu
    OnMessage(0x1A, OnSettingChange)        ; WM_SETTINGCHANGE: Windows switched light/dark
    OnMessage(0x11, OnQueryEndSession)      ; shutting down, restarting or signing out
    OnMessage(0x16, OnEndSession)

    HOOK.proc := CallbackCreate(KeyboardProc)
    if !HookInstall() {
        MsgBox("Couldn't install the keyboard hook, so keys can't be remapped.", APP.name, "Iconx")
        ExitApp(1)
    }
    OnExit(AppExit)

    BuildTray()
    if FileExist(APP.lnk)
        SetAutostart(true)                  ; recreate it: the app may have been moved

    ; Toast again on session unlock and when the display turns back on
    DllCall("LoadLibrary", "str", "wtsapi32", "ptr")     ; keep it loaded (see DEVELOPMENT.md)
    OnMessage(0x2B1, OnSessionChange)                    ; WM_WTSSESSION_CHANGE
    DllCall("wtsapi32\WTSRegisterSessionNotification", "ptr", A_ScriptHwnd, "uint", 0)
    displayGuid := Buffer(16)                            ; GUID_CONSOLE_DISPLAY_STATE
    DllCall("ole32\CLSIDFromString", "wstr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}", "ptr", displayGuid)
    OnMessage(0x218, OnPower)                            ; WM_POWERBROADCAST
    POWER_NOTIFY := DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd, "ptr", displayGuid, "uint", 0, "ptr")

    if firstRun {
        SetAutostart(true)                  ; on by default; the switch is right there to undo it
        ShowSettings("keys")
        SetTimer(() => Notice("Welcome to " APP.short, "Choose what the key should do: changes apply at once", "ok", 6000), -700)
    } else if (args.settings != "") {      ; restarted from the settings window: back where it was
        ShowSettings(args.settings, args.x, args.y)
        SetTimer(() => Notice("The app restarted", Summary()), -400)
    } else if args.updated
        SetTimer(() => SystemToast("Updated to version " APP.version, "See what's new on the GitHub release page"), -2000)
    else if (CFG.toastWhen != "Never")
        SetTimer(StatusToast, -2000)        ; give the desktop time to paint
    ScheduleUpdateCheck()
    Log("Ready in " A_TickCount - t0 " ms")
}

; --restart <pid>: started by Restart or by an update; --updated: show "Updated";
; --settings <section> <x> <y>: reopen the settings window there
ParseArgs() {
    out := {restartPid: 0, updated: false, settings: "", x: "", y: ""}
    for i, arg in A_Args {
        if (arg = "--restart" && i < A_Args.Length) {
            try out.restartPid := Integer(A_Args[i + 1])
        } else if (arg = "--updated")
            out.updated := true
        else if (arg = "--settings" && i + 3 <= A_Args.Length) {
            for p in PAGES
                if (p[1] = A_Args[i + 1])
                    out.settings := p[1]
            try out.x := Integer(A_Args[i + 2]), out.y := Integer(A_Args[i + 3])
            catch
                out.x := "", out.y := ""
        }
    }
    return out
}

OtherInstance() {
    prev := A_DetectHiddenWindows, prevMode := A_TitleMatchMode
    DetectHiddenWindows(true)
    SetTitleMatchMode(3)                    ; the exact title: other scripts' titles are their paths
    found := 0
    for title in INSTANCE_TITLES {
        for hwnd in WinGetList(title " ahk_class AutoHotkey")
            if (hwnd != A_ScriptHwnd) {
                found := hwnd
                break 2
            }
    }
    SetTitleMatchMode(prevMode)
    DetectHiddenWindows(prev)
    return found
}

MarkInstance() {
    prev := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    WinSetTitle(INSTANCE_TITLE, A_ScriptHwnd)
    DetectHiddenWindows(prev)
}

OnInstanceMsg(*) {
    SetTimer(() => ShowSettings(), -1)
    return 1
}

RestartApp() {
    target := A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"'
    args := " --restart " ProcessExist()
    if UI.gui {                             ; reopen the settings window at the same place
        old := PMv2()
        WinGetPos(&wx, &wy, , , UI.gui.Hwnd)
        PMv2(old)
        args .= " --settings " UI.page " " wx " " wy
    }
    try Run(target args, A_ScriptDir)
    catch {
        Notice("Couldn't restart", "Start the app again from its folder", "warn")
        return
    }
    Log("Restarting")
    ExitApp
}

AppExit(reason, code) {
    t := A_TickCount
    ReleasePresses()
    RunQueue()                              ; send the key-up of a held remapped key
    if HOOK.h
        DllCall("UnhookWindowsHookEx", "ptr", HOOK.h), HOOK.h := 0
    StopUpdateCheck()
    DllCall("wtsapi32\WTSUnRegisterSessionNotification", "ptr", A_ScriptHwnd)
    if POWER_NOTIFY
        DllCall("UnregisterPowerSettingNotification", "ptr", POWER_NOTIFY)
    Log("Exit (" reason ", code " code "), cleaned up in " A_TickCount - t " ms")
}

; ---- Shutdown ----------------------------------------------------------------
; Windows asks every app before shutting down, restarting or signing out
; (WM_QUERYENDSESSION), then tells it the session is ending (WM_ENDSESSION),
; where AutoHotkey runs ExitApp. An app that's still busy a few seconds later
; is listed as "preventing shutdown", under its window's title (here the
; hidden INSTANCE_TITLE). So: answer at once, and start nothing new that
; could keep this thread busy (notifications, update checks). Measured: the
; answer takes ~20 ms and the exit ~30 ms, even while a notification is
; being built. While another app blocks the shutdown, Windows lists every app
; still open, this one included: that alone doesn't mean it's the culprit.
OnQueryEndSession(wParam, lParam, *) {
    global ENDING := true
    Log("Windows asks to end the session (" EndReason(lParam) ")")
    for fn in [StatusToast, AutoCheckUpdates, HookInstall]
        SetTimer(fn, 0)
    StopUpdateCheck()
    try GT_Free()
    return true
}

OnEndSession(wParam, lParam, *) {
    global ENDING
    if wParam {
        Log("The session is ending (" EndReason(lParam) "): exiting")
        return                              ; nothing returned: AutoHotkey exits now
    }
    ENDING := false                         ; another app cancelled it: carry on
    Log("Shutdown cancelled: carrying on")
    ScheduleUpdateCheck()
    return 0
}

EndReason(lParam) {
    reason := lParam & 0x80000000 ? "sign out" : "shutdown or restart"     ; ENDSESSION_LOGOFF
    if (lParam & 0x40000000)                ; ENDSESSION_CRITICAL
        reason .= ", forced"
    if (lParam & 0x1)                       ; ENDSESSION_CLOSEAPP: an installer needs the files
        reason := "an installer asks apps to close"
    return reason
}

; ---- Developer log -------------------------------------------------------------
; One line per event, with the time, appended at once so a crash or a forced
; shutdown keeps everything up to it. Costs a fraction of a millisecond per
; line, and only events are logged: never the keys you type (the hook doesn't
; log at all; only the remapped key's actions are). Over 1 MB the file becomes
; Win11KeyRemapper.old.log and a new one starts.

LogPath() {
    SplitPath(SETTINGS_PATH, , &dir)
    return dir "\Win11KeyRemapper.log"
}

SetLog(on) {
    on := on ? true : false
    if (on = DEVLOG.on)
        return
    if !on {
        Log("Log turned off")
        DEVLOG.on := false
        return
    }
    DEVLOG.path := LogPath(), DEVLOG.old := RegExReplace(DEVLOG.path, "\.log$", ".old.log")
    DEVLOG.on := true, DEVLOG.n := 0
    Log("---- Log on: " APP.name " " APP.version ", AutoHotkey " A_AhkVersion (A_PtrSize = 8 ? " 64-bit" : " 32-bit")
      . ", Windows " A_OSVersion ", " (A_IsCompiled ? "exe" : "script") " " A_ScriptFullPath
      . (A_Args.Length ? ", args: " JoinArgs(A_Args) : "") ", " MonitorGetCount() " monitor(s), main " A_ScreenDPI " dpi")
}

Log(msg) {
    if !DEVLOG.on
        return ""
    if (++DEVLOG.n >= 100) {                   ; check the size now and then, not on every line
        DEVLOG.n := 0
        try {
            if (FileGetSize(DEVLOG.path) > 1048576)
                FileMove(DEVLOG.path, DEVLOG.old, 1)
        }
    }
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss.") Format("{:03}", A_MSec) "  " msg "`r`n", DEVLOG.path, "UTF-8")
    return ""
}

LogError(e, mode) {                         ; unexpected errors; the usual dialog still shows
    Log("ERROR: " e.Message (e.Extra != "" ? " (" e.Extra ")" : "") " | " e.What " line " e.Line)
}

JoinArgs(arr) {
    out := ""
    for a in arr
        out .= (out = "" ? "" : " ") a
    return out
}

OpenLog(*) {
    if FileExist(LogPath())
        Run('notepad.exe "' LogPath() '"')
    else
        Notice("No log yet", "Turn on Write a log, then use the app", "info", 3500)
}

IconPath() => FullPath(A_ScriptDir "\..\assets\icon.ico")

FullPath(path) {
    buf := Buffer(2048)
    n := DllCall("GetFullPathNameW", "str", path, "uint", 1024, "ptr", buf, "ptr", 0)
    return n ? StrGet(buf) : path
}

; ============================================================================
; Settings (settings.ini)
; ============================================================================

DefaultSettings() {
    return {sourceVK: 0xFF, sourceSC: 0x175, matchSC: true, mode: "Key"
          , targetMods: [], targetVK: 0x90, targetSC: 0x145                 ; Num Lock
          , launchEnabled: true, launchMods: ["RCtrl"], launchVK: 0xFF, launchSC: 0x175
          , launchAnySide: false, launchPath: "auto"
          , toastWhen: "Always", toastPosition: "TopCenter", toastAnim: "Slide", toastGlass: true
          , trayIcon: true, checkUpdates: true, theme: "System", log: false}
}

CloneSettings(c) {
    copy := c.Clone()
    copy.targetMods := c.targetMods.Clone()
    copy.launchMods := c.launchMods.Clone()
    return copy
}

; Next to the exe if that folder is writable, otherwise %APPDATA%
SettingsPath() {
    beside := A_ScriptDir "\settings.ini", roaming := APP.dataDir "\settings.ini"
    if FileExist(beside)
        return beside
    if FileExist(roaming)
        return roaming
    if DirWritable(A_ScriptDir)
        return beside
    try DirCreate(APP.dataDir)
    return roaming
}

DirWritable(dir) {
    probe := dir "\~write-test-" A_TickCount ".tmp"
    try {
        FileAppend("", probe)
        FileDelete(probe)
        return true
    }
    return false
}

LoadSettings(path) {
    d := DefaultSettings()
    launchPath := IniStr(path, "Launcher", "LaunchPath", d.launchPath)
    if (launchPath = "")
        launchPath := "auto"
    c := {sourceVK: IniHex(path, "Remap", "SourceVK", d.sourceVK)
          , sourceSC: IniHex(path, "Remap", "SourceSC", d.sourceSC)
          , matchSC: IniBool(path, "Remap", "MatchSC", d.matchSC)
          , mode: IniChoice(path, "Remap", "Mode", MODES, d.mode)
          , targetMods: ParseMods(IniStr(path, "Remap", "TargetMods", JoinMods(d.targetMods)))
          , targetVK: IniHex(path, "Remap", "TargetVK", d.targetVK)
          , targetSC: IniHex(path, "Remap", "TargetSC", d.targetSC)
          , launchEnabled: IniBool(path, "Launcher", "LaunchEnabled", d.launchEnabled)
          , launchMods: ParseMods(IniStr(path, "Launcher", "LaunchMods", JoinMods(d.launchMods)))
          , launchVK: IniHex(path, "Launcher", "LaunchVK", d.launchVK)
          , launchSC: IniHex(path, "Launcher", "LaunchSC", d.launchSC)
          , launchAnySide: IniBool(path, "Launcher", "LaunchAnySide", d.launchAnySide)
          , launchPath: launchPath
          , toastWhen: IniChoice(path, "General", "ToastWhen", TOAST_WHENS, d.toastWhen)
          , toastPosition: IniChoice(path, "General", "ToastPosition", TOAST_POSITIONS, d.toastPosition)
          , toastAnim: IniChoice(path, "General", "ToastAnimation", TOAST_ANIMS, d.toastAnim)
          , toastGlass: IniBool(path, "General", "ToastTransparency", d.toastGlass)
          , trayIcon: IniBool(path, "General", "TrayIcon", d.trayIcon)
          , checkUpdates: IniBool(path, "General", "CheckUpdates", d.checkUpdates)
          , theme: IniChoice(path, "General", "Theme", THEME_PREFS, d.theme)
          , log: IniBool(path, "General", "Log", d.log)}
    legacy := StrLower(IniStr(path, "Remap", "Mode", ""))
    if LEGACY_MODES.Has(legacy) {
        lock := LEGACY_MODES[legacy]
        c.mode := "Key", c.targetVK := lock[1], c.targetSC := lock[2], c.targetMods := []
    }
    return c
}

; The whole file, written to a temporary file first so a failure never leaves
; it half-written. UTF-16 (with BOM): IniRead reads non-ASCII paths right.
WriteSettings(path, c) {
    tmp := path ".tmp"
    if FileExist(tmp)
        FileDelete(tmp)
    FileAppend(SettingsText(c), tmp, "UTF-16")
    FileMove(tmp, path, 1)
}

SettingsExplained(path) {
    try return InStr(FileRead(path), "`n; What the key does:") > 0
    return false
}

SettingsText(c) {
    values := Map("SourceVK", Hex(c.sourceVK), "SourceSC", Hex(c.sourceSC), "MatchSC", c.matchSC ? 1 : 0
        , "Mode", c.mode, "TargetMods", JoinMods(c.targetMods), "TargetVK", Hex(c.targetVK), "TargetSC", Hex(c.targetSC)
        , "LaunchEnabled", c.launchEnabled ? 1 : 0, "LaunchMods", JoinMods(c.launchMods)
        , "LaunchVK", Hex(c.launchVK), "LaunchSC", Hex(c.launchSC), "LaunchAnySide", c.launchAnySide ? 1 : 0
        , "LaunchPath", c.launchPath, "ToastWhen", c.toastWhen, "ToastPosition", c.toastPosition
        , "ToastAnimation", c.toastAnim, "ToastTransparency", c.toastGlass ? 1 : 0
        , "TrayIcon", c.trayIcon ? 1 : 0, "CheckUpdates", c.checkUpdates ? 1 : 0, "Theme", c.theme
        , "Log", c.log ? 1 : 0)
    text := SETTINGS_TEMPLATE
    for key, value in values
        text := StrReplace(text, "{" key "}", value)
    return StrReplace(text, "`n", "`r`n")
}

; Missing key -> default. An empty value stays empty (e.g. "no modifiers").
IniStr(path, section, key, def) {
    v := IniRead(path, section, key, "<<unset>>")
    if (v == "<<unset>>")
        return def
    return Trim(RegExReplace(v, "\s+;.*$"))          ; allow "Key=value  ; comment"
}

IniHex(path, section, key, def) {
    v := IniStr(path, section, key, Hex(def))
    if (v = "")
        return 0
    try {
        n := Integer(v)
        if (n >= 0 && n <= 0xFFFF)
            return n
    }
    return def
}

IniBool(path, section, key, def) {
    v := IniStr(path, section, key, def ? "1" : "0")
    return !(v = "" || v = "0" || v = "false" || v = "no" || v = "off")
}

; One of a fixed list of words (case-insensitive), returned with the list's spelling
IniChoice(path, section, key, choices, def) {
    v := IniStr(path, section, key, def)
    for choice in choices
        if (v = choice)
            return choice
    return def
}

ParseMods(str) {
    found := Map()
    for part in StrSplit(str, [",", "+", " "]) {
        part := Trim(part)
        if (part = "")
            continue
        for name in MOD_ORDER
            if (part = name)
                found[name] := true
        if MOD_ALIAS.Has(StrLower(part))
            found[MOD_ALIAS[StrLower(part)]] := true
    }
    mods := []
    for name in MOD_ORDER
        if found.Has(name)
            mods.Push(name)
    return mods
}

JoinMods(mods) {
    out := ""
    for name in mods
        out .= (out = "" ? "" : ",") name
    return out
}

Hex(n) => Format("0x{:X}", n)

; Turns CFG into what the hook needs, so the hook does no string work
ApplySettings() {
    global RT
    ReleasePresses()
    c := CFG
    r := {mode: c.mode, srcVK: c.sourceVK, srcSC: c.matchSC ? c.sourceSC : 0
        , down: "", up: "", combo: ""
        , launchOn: c.launchEnabled && c.launchVK != 0
        , launchVK: c.launchVK, launchSC: c.launchSC
        , launchAny: c.launchAnySide, launchMods: Map()
        , noRepeat: !c.targetMods.Length && LOCK_VKS.Has(c.targetVK)}
    if (!r.srcVK || (r.mode = "Key" && !c.targetVK))
        r.mode := "None"
    if (r.mode = "Key") {
        key := KeySpec(c.targetVK, c.targetSC)
        if !c.targetMods.Length {
            ; A real remap: down/up follow the source key, so holding repeats
            ; and Shift+source gives Shift+target
            r.down := "{Blind}{" key " down}", r.up := "{Blind}{" key " up}"
        } else {
            pre := "", post := ""
            for name in c.targetMods
                pre .= "{" name " down}", post := "{" name " up}" post
            r.combo := pre "{" key "}" post
        }
    }
    for name in c.launchMods
        r.launchMods[c.launchAnySide ? MOD_FAMILY[name] : name] := true
    RT := r
    GTCFG.position := c.toastPosition, GTCFG.animation := c.toastAnim
    GTCFG.glass := c.toastGlass, GTCFG.solidTheme := c.theme = "System" ? "" : StrLower(c.theme)
    A_IconHidden := !c.trayIcon
    UpdateTray()
    SetLog(c.log)
}

; ============================================================================
; Keyboard hook
; ============================================================================

HookInstall() {
    ; Create the new hook before removing the old one. Also called after
    ; anything slow, because Windows silently drops a hook that times out.
    hNew := DllCall("SetWindowsHookEx", "int", 13, "ptr", HOOK.proc            ; WH_KEYBOARD_LL
                  , "ptr", DllCall("GetModuleHandle", "ptr", 0, "ptr"), "uint", 0, "ptr")
    if !hNew {
        Log("Couldn't install the keyboard hook (error " A_LastError ")")
        return false
    }
    old := HOOK.h, HOOK.h := hNew
    if old
        DllCall("UnhookWindowsHookEx", "ptr", old)
    Log("Keyboard hook " (old ? "reinstalled" : "installed"))
    return true
}

CallNext(nCode, wParam, lParam) => DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")

KeyboardProc(nCode, wParam, lParam) {
    Critical
    if (nCode != 0)
        return CallNext(nCode, wParam, lParam)
    vk := NumGet(lParam, 0, "uint"), flags := NumGet(lParam, 8, "uint")
    sc := NumGet(lParam, 4, "uint") | ((flags & 1) << 8)          ; scan code + extended bit
    if (flags & 0x10)                                             ; injected: our own SendInput
        return CallNext(nCode, wParam, lParam)
    up := (flags & 0x80) != 0
    id := (vk << 16) | sc
    now := A_TickCount
    fake := (sc & 0x200) != 0                                     ; fake LCtrl sent with AltGr

    ; Key-up (and auto-repeat) of a key whose key-down we ate earlier
    if SWALLOW.Has(id) {
        if up {
            SWALLOW.Delete(id)
            return 1
        }
        if (now - SWALLOW[id] < REPEAT_MS) {
            SWALLOW[id] := now
            return 1
        }
        SWALLOW.Delete(id)                                        ; stale: the key-up was missed
    }

    ; Key detection for the settings window: before the rules, even if paused
    if CAP.active
        return CaptureKey(vk, sc, id, up, fake) ? 1 : CallNext(nCode, wParam, lParam)

    if (VK_MOD.Has(vk) && !fake) {
        name := VK_MOD[vk]
        if !up
            HELD[name] := true
        else if HELD.Has(name)
            HELD.Delete(name)
    }

    if PAUSED
        return CallNext(nCode, wParam, lParam)

    ; A key we are already handling: auto-repeat or release
    if PRESS.Has(id) {
        p := PRESS[id]
        if up {
            PRESS.Delete(id)
            return OnPressUp(p)
        }
        if (now - p.t < REPEAT_MS) {
            p.t := now
            return OnPressRepeat(p)
        }
        PRESS.Delete(id)                                          ; stale: treat as a new press
    }
    if up
        return CallNext(nCode, wParam, lParam)

    if (RT.launchOn && vk = RT.launchVK && (!RT.launchSC || sc = RT.launchSC) && LaunchModsHeld()) {
        PRESS[id] := {owner: "launch", t: now}
        Enqueue({do: "launch"})
        return 1
    }

    if (RT.mode != "None" && vk = RT.srcVK && (!RT.srcSC || sc = RT.srcSC)) {
        PRESS[id] := {owner: "remap", t: now}
        if (RT.mode = "Key")
            Enqueue({do: "send", keys: RT.combo != "" ? RT.combo : RT.down})
        return 1                            ; Windows / vendor software never see the key
    }
    return CallNext(nCode, wParam, lParam)
}

OnPressRepeat(p) {
    ; A key remap repeats like the real key, except a lock key (holding it
    ; toggles once); a shortcut is sent again on every repeat.
    if (p.owner = "remap" && RT.mode = "Key" && !RT.noRepeat)
        Enqueue({do: "send", keys: RT.combo != "" ? RT.combo : RT.down})
    return 1
}

OnPressUp(p) {
    if (p.owner = "remap" && RT.mode = "Key" && RT.up != "")
        Enqueue({do: "send", keys: RT.up})
    return 1
}

LaunchModsHeld() {
    ; Drop modifiers whose key-up we missed (e.g. released while an
    ; elevated window had the focus)
    stale := []
    for name in HELD
        if !GetKeyState(name, "P")
            stale.Push(name)
    for name in stale
        HELD.Delete(name)
    return ModsMatch(HELD)
}

; The held modifiers must be exactly the required set (per family if "any side")
ModsMatch(down) {
    have := Map()
    for name in down
        have[RT.launchAny ? MOD_FAMILY[name] : name] := true
    if (have.Count != RT.launchMods.Count)
        return false
    for name in RT.launchMods
        if !have.Has(name)
            return false
    return true
}

; Forgets the keys being handled (settings changed, paused, exiting): sends
; the key-up of a held remapped key and eats the physical key-ups to come
ReleasePresses() {
    Critical
    now := A_TickCount
    for id, p in PRESS {
        if (p.owner = "remap" && RT.up != "")
            Enqueue({do: "send", keys: RT.up})
        SWALLOW[id] := now
    }
    PRESS.Clear()
}

; ---- Action queue (keeps order; nothing heavy runs inside the hook) --------

Enqueue(action) {
    QUEUE.Push(action)
    SetTimer(RunQueue, -1)
}

RunQueue() {
    while QUEUE.Length {
        act := QUEUE.RemoveAt(1)
        try {
            switch act.do {
                case "send":
                    SendInput(act.keys)
                    Log("Remapped key: sent " act.keys)    ; the configured target only, never typed keys
                case "launch":
                    Log("App shortcut pressed")
                    LaunchApp()
            }
        } catch as e
            Log("Couldn't " (act.do = "send" ? "send " act.keys : "open the app") ": " e.Message)
    }
}

; ============================================================================
; Key / shortcut detection (runs inside the hook while the panel listens)
; ============================================================================

; Returns true to swallow the event
CaptureKey(vk, sc, id, up, fake) {
    isMod := VK_MOD.Has(vk) && !fake
    if up {
        if !CAP.downs.Has(id) {             ; pressed before listening started: let it go
            if (isMod && HELD.Has(VK_MOD[vk]))
                HELD.Delete(VK_MOD[vk])
            return false
        }
        CAP.downs.Delete(id)
        if isMod {                          ; a modifier alone: capture the modifier itself
            CAP.mods.Delete(VK_MOD[vk])
            CaptureFinish(vk, sc)
        }
        return true
    }
    if CAP.downs.Has(id)                    ; auto-repeat
        return true
    CAP.downs[id] := true
    if fake
        return true
    if isMod {
        CAP.mods[VK_MOD[vk]] := true
        return true
    }
    CaptureFinish(vk, sc)
    return true
}

CaptureFinish(vk, sc) {
    ; Windows reports Ctrl + Num Lock as Pause and Ctrl + Scroll Lock as
    ; Break, with the lock key's scan code: keep the key that was pressed
    if (vk = 0x13 && sc = 0x145)
        vk := 0x90
    else if (vk = 0x03 && sc = 0x46)
        vk := 0x91
    now := A_TickCount
    for id in CAP.downs                     ; keys still held: eat their key-ups later
        SWALLOW[id] := now
    keyMod := VK_MOD.Has(vk) ? VK_MOD[vk] : ""
    if (keyMod != "")
        vk := MOD_VK[keyMod]                ; generic Ctrl/Alt/Shift -> side-specific
    mods := []
    for name in MOD_ORDER
        if (CAP.mods.Has(name) && name != keyMod)
            mods.Push(name)
    CAP.result := {vk: vk, sc: sc, mods: mods}
    CAP.active := false
    SetTimer(CaptureDone, -1)               ; never touch the GUI from the hook
}

CaptureToggle(target) {
    Critical
    again := CAP.active && CAP.target = target
    CaptureCancel()
    if !again {
        CAP.target := target, CAP.mods := Map(), CAP.downs := Map(), CAP.result := 0
        CAP.active := true
        SetTimer(CaptureTimeout, -10000)
    }
    Critical "Off"
    RefreshSettings()
}

CaptureCancel() {
    Critical
    SetTimer(CaptureTimeout, 0)
    if !CAP.active
        return
    CAP.active := false
    now := A_TickCount
    for id in CAP.downs
        SWALLOW[id] := now
    CAP.downs := Map()
}

CaptureTimeout() {
    CaptureCancel()
    RefreshSettings()
}

CaptureDone() {
    SetTimer(CaptureTimeout, 0)
    r := CAP.result
    CAP.result := 0
    if (!r || !UI.gui)
        return
    switch CAP.target {
        case "source": DRAFT.sourceVK := r.vk, DRAFT.sourceSC := r.sc, what := "Key: "
        case "target": DRAFT.targetVK := r.vk, DRAFT.targetSC := r.sc, DRAFT.targetMods := r.mods, what := "Sends: "
        case "launch": DRAFT.launchVK := r.vk, DRAFT.launchSC := r.sc, DRAFT.launchMods := r.mods, what := "Shortcut: "
    }
    CommitDraft(what (CAP.target = "source" ? KeyLabel(r.vk, r.sc) : ComboLabel(r.mods, r.vk, r.sc)))
}

; ============================================================================
; Key names
; ============================================================================

KeySpec(vk, sc) => sc ? Format("vk{:02X}sc{:03X}", vk, sc) : Format("vk{:02X}", vk)

KeyLabel(vk, sc) {
    known := Format("{:X}:{:X}", vk, sc)
    if KNOWN_KEYS.Has(known)
        return KNOWN_KEYS[known]
    if VK_MOD.Has(vk)
        return MOD_LABEL[VK_MOD[vk]]
    name := GetKeyName(KeySpec(vk, sc))
    if (name != "") {
        if KEY_NAMES.Has(name)
            return KEY_NAMES[name]
        if (StrLen(name) = 1)
            return StrUpper(name)
        return RegExReplace(StrReplace(name, "_", " "), "(?<=[a-z])(?=[A-Z0-9])", " ")
    }
    return sc ? Format("Special key (SC {:X})", sc) : Format("Special key (VK {:X})", vk)
}

; ["Right Ctrl", "NitroSense key"]: the keys of a shortcut, in display order
ComboParts(mods, vk, sc, anySide := false) {
    parts := [], seen := Map()
    for name in mods {
        label := anySide ? MOD_FAMILY[name] : MOD_LABEL[name]
        if !seen.Has(label)
            parts.Push(label), seen[label] := true
    }
    parts.Push(KeyLabel(vk, sc))
    return parts
}

ComboLabel(mods, vk, sc, anySide := false) {
    out := ""
    for part in ComboParts(mods, vk, sc, anySide)
        out .= (out = "" ? "" : " + ") part
    return out
}

FieldText(vk, sc, mods := 0, anySide := false) {
    if !vk
        return "Not set"
    return ComboLabel(mods ? mods : [], vk, sc, anySide) " · " Format("VK {:X} SC {:X}", vk, sc)
}

Summary(c := 0) {
    if !c
        c := CFG
    src := c.sourceVK ? KeyLabel(c.sourceVK, c.sourceSC) : "No key"
    switch c.mode {
        case "Key":        return src " → " (c.targetVK ? ComboLabel(c.targetMods, c.targetVK, c.targetSC) : "nothing")
        case "Disable":    return src " is disabled"
    }
    return c.launchEnabled ? "Remapping off, app shortcut on" : "Remapping is off"
}

; ============================================================================
; Opening NitroSense (or any app)
; ============================================================================

DetectNitroSense(force := false) {
    if (NS.checked && !force)
        return NS.target
    NS.checked := true, NS.target := "", NS.label := ""
    for dir in [A_ProgramFiles, EnvGet("ProgramW6432"), EnvGet("ProgramFiles(x86)")] {
        if (dir = "")
            continue
        for rel in ["\NitroSense\Prerequisites\NitroSenseLauncher.exe", "\NitroSense\NitroSense.exe"]
            if FileExist(dir rel) {
                NS.target := dir rel
                Log("NitroSense found: " NS.target)
                return NS.target
            }
    }
    ; Microsoft Store version: look it up in the Apps folder (can be slow)
    t := A_TickCount
    try {
        for item in ComObject("Shell.Application").NameSpace("shell:AppsFolder").Items()
            if InStr(item.Name, "NitroSense") {
                NS.target := "shell:AppsFolder\" item.Path, NS.label := item.Name " (Microsoft Store app)"
                break
            }
    }
    Log("NitroSense " (NS.target != "" ? "found: " NS.target : "not found") " (searched the apps in " A_TickCount - t " ms)")
    HookInstall()                           ; in case that took long enough to drop the hook
    return NS.target
}

TargetExists(t) => t != "" && (FileExist(t) || SubStr(t, 1, 6) = "shell:")

LaunchApp() {
    target := CFG.launchPath
    if (target = "auto") {
        target := DetectNitroSense()
        if !TargetExists(target)
            target := DetectNitroSense(true)    ; installed or moved since the last look
    }
    if !TargetExists(target) {
        Log("App to open not found: " CFG.launchPath)
        SystemToast("App not found", "Choose it in Settings", "warn")
        return
    }
    try {
        if FileExist(target) {
            SplitPath(target, , &dir)
            Run('"' target '"', dir)
        } else
            Run(target)
        Log("Opened " target)
    } catch as e {
        Log("Couldn't open " target ": " e.Message)
        SystemToast("Couldn't open the app", "Check the app in Settings", "warn")
    }
    HookInstall()
}

; ============================================================================
; Toasts, session and display events
; ============================================================================

; System notifications (GlassToast), which ToastWhen=Never turns off except
; warnings that need you. The startup/unlock one is StatusToast. What happens
; in the settings window is told inside it instead: Notice, a separate,
; smaller component (see "Notices inside the settings window").
SystemToast(title, sub, kind := "ok", holdMs := 5000) {
    if (CFG.toastWhen != "Never" || kind = "warn")
        ShowToast(title, sub, kind, holdMs)
}

StatusToast() {
    if PAUSED
        ShowToast(APP.short " is paused", "Resume it from the tray icon", "info")
    else
        ShowToast(APP.short " is active", Summary())
}

; Building one (screen capture + blur) is the heaviest thing the app does, so
; the log says how long it took. None while Windows is shutting down.
ShowToast(title, sub, kind := "ok", holdMs := 5000) {
    if ENDING
        return
    t := A_TickCount
    GlassToast(title, sub, kind, holdMs)
    Log("Notification: " title " | " sub " (" kind ", " (GTCFG.glass ? "glass" : "solid") ", built in " A_TickCount - t " ms)")
}

OnSessionChange(wParam, lParam, msg, hwnd) {
    global LOCKED
    if (wParam = 0x8) {                     ; WTS_SESSION_UNLOCK
        Log("Session unlocked")
        LOCKED := false
        SetTimer(HookInstall, -500)
        if (CFG.toastWhen = "Always")
            SetTimer(StatusToast, -1200)    ; wait until the desktop is visible
    } else if (wParam = 0x7) {              ; WTS_SESSION_LOCK
        Log("Session locked")
        LOCKED := true
        SetTimer(GT_Free, -1)
    }
}

; Display turned off and on again without locking: no session event, so the
; console display state is watched instead (off = 0, on = 1, dimmed = 2)
OnPower(wParam, lParam, msg, hwnd) {
    static prev := -1                       ; the first notification is the current state
    if (wParam = 0x4)                       ; PBT_APMSUSPEND
        Log("Going to sleep")
    if (wParam = 0x7 || wParam = 0x12) {    ; resumed from sleep
        Log("Resumed from sleep")
        SetTimer(HookInstall, -1000)
        return true
    }
    if (wParam != 0x8013)                   ; PBT_POWERSETTINGCHANGE
        return
    state := NumGet(lParam, 20, "uint")     ; POWERBROADCAST_SETTING: GUID(16) + length(4) + data
    if (prev != -1 && state != prev)
        Log("Display " (state = 0 ? "off" : state = 1 ? "on" : "dimmed"))
    if (state = 0)
        SetTimer(GT_Free, -1)
    else if (state = 1 && prev = 0 && !LOCKED) {
        SetTimer(HookInstall, -500)
        if (CFG.toastWhen = "Always")
            SetTimer(StatusToast, -1500)
    }
    prev := state
    return true
}

; ============================================================================
; Tray menu
; ============================================================================

BuildTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Settings…", (*) => ShowSettings())
    tray.Add("Pause remapping", (*) => TogglePause())
    tray.Add()
    tray.Add("Restart", (*) => RestartApp())
    tray.Add("Exit", (*) => ExitApp())
    tray.Default := "Settings…"
    tray.ClickCount := 2
    OnMessage(0x404, OnTrayNotify)          ; AHK_NOTIFYICON
    UpdateTray()
}

; Shows the tray menu Per-Monitor DPI aware: with the app's system-DPI
; awareness, Windows put it in the wrong place and at the wrong size on a
; monitor whose scale differs from the main one.
OnTrayNotify(wParam, lParam, msg, hwnd) {
    event := lParam & 0xFFFF
    if (event != 0x205 && event != 0x7B)    ; WM_RBUTTONUP, WM_CONTEXTMENU
        return
    ShowMenuAtCursor(A_TrayMenu)
    return 1
}

ShowMenuAtCursor(m) {
    old := PMv2()
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    CoordMode("Menu", "Screen")
    m.Show(NumGet(pt, 0, "int"), NumGet(pt, 4, "int"))
    PMv2(old)
}

; Switches this thread to Per-Monitor v2 DPI awareness and returns the old
; context; PMv2(old) restores it.
PMv2(old := 0) => DllCall("SetThreadDpiAwarenessContext", "ptr", old ? old : -4, "ptr")

UpdateTray() {
    try PAUSED ? A_TrayMenu.Check("Pause remapping") : A_TrayMenu.Uncheck("Pause remapping")
    A_IconTip := SubStr(APP.name (PAUSED ? " (paused)" : "") "`n" Summary(), 1, 127)
}

TogglePause() => SetPaused(!PAUSED)

SetPaused(state, toast := true) {
    global PAUSED
    ReleasePresses()
    PAUSED := state ? 1 : 0
    Log("Remapping " (PAUSED ? "paused" : "resumed"))
    UpdateTray()
    RefreshSettings()                       ; if the window is open
    if !toast
        return
    if PAUSED
        SystemToast("Remapping paused", "Keys work as usual until you resume", "info", 2500)
    else
        SystemToast("Remapping resumed", Summary(), "ok", 2500)
}

; Shortcut in the Startup folder. From source it must run AutoHotkey64.exe
; with the script as argument: a shortcut to the .ahk doesn't start at logon.
SetAutostart(on) {
    try {
        if !on {
            if FileExist(APP.lnk)
                FileDelete(APP.lnk)
        } else if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, APP.lnk, A_ScriptDir, , APP.name)
        else
            FileCreateShortcut(A_AhkPath, APP.lnk, A_ScriptDir, '"' A_ScriptFullPath '"', APP.name
                             , FileExist(IconPath()) ? IconPath() : A_AhkPath)
        return true
    } catch as e {
        Notice("Couldn't change Start with Windows", e.Message, "warn", 5000)
        return false
    }
}

OpenSettingsFolder() {
    if FileExist(SETTINGS_PATH)
        Run('explorer.exe /select,"' SETTINGS_PATH '"')
    else {
        SplitPath(SETTINGS_PATH, , &dir)
        Run(dir)
    }
}

; ============================================================================
; Updates (GitHub releases)
; ============================================================================
; The check is asynchronous (WinHttp + a polling timer): a blocking request
; would stall the keyboard hook. Installing replaces the exe in place: it's
; downloaded, verified against the release's SHA256SUMS.txt, the running exe
; is renamed to .old (Windows allows that) and the new one is started.

ScheduleUpdateCheck() {
    SetTimer(AutoCheckUpdates, CFG.checkUpdates ? -60000 : 0)     ; not during logon
}

AutoCheckUpdates() {
    if !CFG.checkUpdates
        return
    CheckUpdates(false)
    SetTimer(AutoCheckUpdates, -24 * 3600 * 1000)                 ; then once a day
}

UpdateAction() {
    if (UPD.state = "available")
        InstallUpdate()
    else
        CheckUpdates(true)
}

CheckUpdates(manual := false) {
    if (UPD.state = "checking" || ENDING)
        return
    Log("Checking for updates (" (manual ? "Check now" : "daily check") ")")
    UPD.t0 := A_TickCount
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", APP.api, true)
        req.SetRequestHeader("User-Agent", "Win11KeyRemapper/" APP.version)
        req.SetRequestHeader("Accept", "application/vnd.github+json")
        req.Send()
    } catch {
        UpdateDone("error", manual)
        return
    }
    UPD.req := req, UPD.manual := manual, UPD.t0 := A_TickCount, UPD.state := "checking"
    RefreshSettings()
    SetTimer(PollUpdates, 250)
}

PollUpdates() {
    req := UPD.req, done := false, failed := false
    try done := req.WaitForResponse(0)      ; COM true is -1
    catch
        failed := true
    if (!done && !failed && A_TickCount - UPD.t0 < 20000)
        return
    SetTimer(PollUpdates, 0)
    UPD.req := 0
    status := 0, text := ""
    if (done && !failed)
        try status := req.Status, text := req.ResponseText
    if (status = 404)                       ; no release published yet
        return UpdateDone("latest", UPD.manual)
    rel := status = 200 ? ParseRelease(text) : {tag: ""}
    if (rel.tag = "")
        return UpdateDone("error", UPD.manual)
    if !VersionNewer(rel.tag, APP.version)
        return UpdateDone("latest", UPD.manual)
    UPD.latest := rel.tag, UPD.page := rel.page, UPD.zip := rel.zip, UPD.sums := rel.sums
    UpdateDone("available", UPD.manual)
}

; Stops a check in progress (exiting, or Windows is shutting down): a pending
; request must not keep the app busy
StopUpdateCheck() {
    SetTimer(PollUpdates, 0)
    if UPD.req {
        try UPD.req.Abort()
        UPD.req := 0
        Log("Update check stopped")
    }
    if (UPD.state = "checking")
        UPD.state := ""
}

UpdateDone(state, manual) {
    Log("Update check: " (state = "available" ? "version " UPD.latest " available" : state = "latest" ? "up to date" : "failed")
      . (UPD.t0 ? " (" A_TickCount - UPD.t0 " ms)" : ""))
    UPD.state := state
    RefreshSettings()
    if (state = "available") {
        if manual
            Notice("Update available: " UPD.latest, (A_IsCompiled ? "Click Install" : "Click Download") " to get it", "update", 4000)
        else if (UPD.notified != UPD.latest)
            SystemToast("Update available: " UPD.latest, "Install it from Settings > Updates", "update", 7000)
        UPD.notified := UPD.latest
    } else if (manual && state = "latest")
        Notice("You're up to date", APP.short " " APP.version)
    else if (manual && state = "error")
        Notice("Couldn't check for updates", "Check your connection", "warn", 4000)
}

; Minimal reading of GitHub's "latest release" JSON
ParseRelease(json) {
    rel := {tag: "", page: "", zip: "", sums: ""}
    if RegExMatch(json, '"tag_name"\s*:\s*"([^"]+)"', &m)
        rel.tag := m[1]
    if RegExMatch(json, '"html_url"\s*:\s*"([^"]+/releases/tag/[^"]+)"', &m)
        rel.page := m[1]
    if RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+/Win11KeyRemapper-v[^"/]+\.zip)"', &m)
        rel.zip := m[1]
    if RegExMatch(json, '"browser_download_url"\s*:\s*"([^"]+/SHA256SUMS\.txt)"', &m)
        rel.sums := m[1]
    return rel
}

VersionNewer(tag, current) {
    if !RegExMatch(tag, "(\d+)\.(\d+)\.(\d+)", &mNew) || !RegExMatch(current, "(\d+)\.(\d+)\.(\d+)", &mCur)
        return false
    loop 3 {
        a := Integer(mNew[A_Index]), b := Integer(mCur[A_Index])
        if (a != b)
            return a > b
    }
    return false
}

InstallUpdate() {
    if (UPD.state != "available")
        return
    page := UPD.page != "" ? UPD.page : APP.repo "/releases/latest"
    if (!A_IsCompiled || UPD.zip = "" || UPD.sums = "" || !DirWritable(A_ScriptDir)) {
        Run(page)                           ; from source or in a protected folder: manual download
        return
    }
    if (Dialog("Install " APP.short " " UPD.latest "?`n`nIt will be downloaded from GitHub, checked, installed in place of this version, and the app will restart.", "OKCancel Iconi") != "OK")
        return
    dir := A_Temp "\Win11KeyRemapper-update"
    SplitPath(UPD.zip, &zipName)
    try {
        if DirExist(dir)
            DirDelete(dir, true)
        DirCreate(dir "\files")
        Download(UPD.zip, dir "\" zipName)
        Download(UPD.sums, dir "\SHA256SUMS.txt")
    } catch as e {
        HookInstall()
        return UpdateFailed("The download failed: " e.Message, page)
    }
    HookInstall()                           ; the download kept this thread busy for a moment
    sums := ReadSums(dir "\SHA256SUMS.txt")
    exeName := "Win11KeyRemapper.exe"
    if (!sums.Has(zipName) || !sums.Has(exeName) || Sha256File(dir "\" zipName) != sums[zipName])
        return UpdateFailed("The downloaded file doesn't match its checksum.", page)
    shell := ComObject("Shell.Application")
    shell.NameSpace(dir "\files").CopyHere(shell.NameSpace(dir "\" zipName).Items(), 4 | 16 | 1024)
    newExe := dir "\files\" exeName
    loop 50 {                               ; unzipping may finish in the background
        if (Sha256File(newExe) = sums[exeName])
            break
        Sleep(100)
    }
    if (Sha256File(newExe) != sums[exeName])
        return UpdateFailed("The update couldn't be unpacked.", page)
    old := A_ScriptFullPath ".old"
    try {
        if FileExist(old)
            FileDelete(old)
        FileMove(A_ScriptFullPath, old)     ; renaming a running exe is allowed
        try FileCopy(newExe, A_ScriptFullPath)
        catch as e {
            FileMove(old, A_ScriptFullPath)
            throw e
        }
    } catch as e
        return UpdateFailed("The app couldn't be replaced: " e.Message, page)
    Run('"' A_ScriptFullPath '" --restart ' ProcessExist() " --updated", A_ScriptDir)
    ExitApp
}

UpdateFailed(msg, page) {
    Dialog(msg "`n`nThe release page will open so you can download it manually.", "Icon!")
    try Run(page)
}

ReadSums(path) {                        ; "hash  file" lines -> Map(file, hash)
    sums := Map()
    try {
        for line in StrSplit(FileRead(path), "`n", "`r ")
            if RegExMatch(line, "i)^([0-9a-f]{64})\s+\*?(\S.*)$", &m)
                sums[Trim(m[2])] := StrLower(m[1])
    }
    return sums
}

Sha256File(path) {                      ; lowercase hex, "" if unreadable
    static lib := DllCall("LoadLibrary", "str", "bcrypt", "ptr")    ; the handle spans calls
    try data := FileRead(path, "RAW")
    catch
        return ""
    alg := 0, hash := Buffer(32)
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &alg, "wstr", "SHA256", "ptr", 0, "uint", 0)
    DllCall("bcrypt\BCryptHash", "ptr", alg, "ptr", 0, "uint", 0, "ptr", data, "uint", data.Size, "ptr", hash, "uint", 32)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", alg, "uint", 0)
    out := ""
    loop 32
        out .= Format("{:02x}", NumGet(hash, A_Index - 1, "uchar"))
    return out
}

; ============================================================================
; Settings window
; ============================================================================
; Windows 11 style: a sidebar with sections, each section a column of
; setting cards (title, description, control on the right). Every change is
; applied and saved at once; if something is missing (e.g. the key to send),
; the row says so and the previous setting stays active.
;
; Standard Win32 controls can't draw rounded cards, buttons with states,
; keycaps, switches or the sidebar, so those are drawn with GDI+: the cards
; on WM_ERASEBKGND, everything else as widgets (UiWidget), Picture controls
; redrawn for each state: hover, pressed, disabled, animating. Mouse input
; for widgets is handled here, like a normal button: pressed on button-down,
; action on button-up over it.
;
; The window is Per-Monitor DPI aware (v2) while the rest of the app is
; system-aware: it's created in a PMv2 thread context with -DPIScale,
; positions and font sizes are scaled by hand (Px, FontPts) and every
; control is remembered in UI.items. On WM_DPICHANGED only the visible
; section is laid out again (the others when they're opened), in one batch
; and with painting frozen, so moving the window to another monitor stays
; fluid. Every bigger change (a section, a DPI change, a row appearing) is
; done frozen and then shown in one copy (Flip): never a half-painted frame.

ShowSettings(page := "", posX := "", posY := "") {
    global DRAFT
    if UI.gui {
        if (page != "")
            ShowPage(page)
        UI.gui.Show()
        return
    }
    DRAFT := CloneSettings(CFG)
    t := A_TickCount
    BuildSettings(page != "" ? page : "keys", posX, posY)
    Log("Settings window opened (" UI.page ", " UI.dpi " dpi, built in " A_TickCount - t " ms)")
    if !NS.checked
        SetTimer(DetectForApp, -150)        ; after the window is on screen
}

BuildSettings(page, posX := "", posY := "") {
    static hooked := false
    if !hooked {
        OnMessage(0x14, OnSettingsErase)            ; WM_ERASEBKGND: paint the cards
        OnMessage(0x134, OnSettingsCtlColorList)    ; WM_CTLCOLORLISTBOX: dark drop-down lists
        OnMessage(0x2E0, OnSettingsDpiChanged)      ; WM_DPICHANGED: moved to another monitor
        OnMessage(0x20, OnSettingsSetCursor)        ; WM_SETCURSOR: hand over what can be clicked
        OnMessage(0x200, OnSettingsMouseMove)       ; WM_MOUSEMOVE: hover, ⓘ tooltips
        OnMessage(0x201, OnSettingsMouseDown)       ; WM_LBUTTONDOWN
        OnMessage(0x203, OnSettingsMouseDown)       ; WM_LBUTTONDBLCLK: a fast second click
        OnMessage(0x202, OnSettingsMouseUp)         ; WM_LBUTTONUP
        OnMessage(0x3, OnSettingsMove)              ; WM_MOVE: the notice follows the window
        OnMessage(0x231, OnSettingsSizeMove)        ; WM_ENTERSIZEMOVE: dragging the window
        OnMessage(0x232, OnSettingsSizeMove)        ; WM_EXITSIZEMOVE: dropped
        hooked := true
    }
    old := PMv2()
    if (posX = "") {                        ; center on the monitor under the mouse
        mon := GT_MouseMonitor()
        MonitorGetWorkArea(mon, &wl, &wt, &wr, &wb)
        UI.dpi := GT_MonitorDpi(mon)
    } else
        UI.dpi := DpiAt(posX, posY)
    UI.k := UI.dpi / 96
    UI.themeName := ThemeName(DRAFT.theme)
    th := UI.th := THEMES[UI.themeName]
    UI.tok := GdipStart()
    UI.fam := Map(), UI.cardIcon := 0, UI.cardIconSize := 0
    UI.iconFont := FontFamily("Segoe Fluent Icons") ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"
    UI.page := page, UI.problem := "", UI.problemWhere := "", UI.tipFor := 0, UI.bgBmp := 0
    UI.items := [], UI.itemOf := Map(), UI.icons := [], UI.groups := Map(), UI.nav := Map(), UI.laidOut := Map()
    UI.keyText := Map(), UI.tg := Map(), UI.tgState := Map(), UI.infoTips := Map(), UI.hand := Map()
    UI.widgets := Map(), UI.anims := Map(), UI.hot := 0, UI.frozen := 0, UI.paintOff := false
    UI.pendingDpi := 0, UI.dpiShot := 0, UI.sizing := false, UI.stretchHidden := []
    UI.kvW := SL.btnX - 10 - SL.kvX
    UI.brushCard := DllCall("CreateSolidBrush", "uint", Bgr(th.card), "ptr")
    for p in PAGES
        UI.groups[p[1]] := [], UI.laidOut[p[1]] := UI.dpi
    UI.laidOut[""] := UI.dpi

    g := Gui("-MinimizeBox -MaximizeBox -DPIScale", APP.name)
    UI.gui := g
    g.BackColor := Hex6(th.win)
    g.MarginX := 0, g.MarginY := 0
    g.OnEvent("Close", CloseSettings)
    g.OnEvent("Escape", CloseSettings)

    ; Sidebar: app name, status, sections
    AddIcon(20, 16, 28)
    Place("Text", "", 56, 14, 150, 22, "0x80 Background" Hex6(th.win), APP.short, 12, "w600", th.text)
    UI.status := Place("Text", "", 56, 36, 150, 16, "0x80 Background" Hex6(th.win), "", 8.5, "w400", th.ok)
    for i, p in PAGES
        UI.nav[p[1]] := NewWidget("nav", "", 8, 72 + (i - 1) * 40, SL.side - 16, 36
                                , {page: p[1], label: p[2], glyph: p[3], pos: 1}).OnEvent("Click", ShowPage.Bind(p[1]))

    ; Content: section title, then the section's cards
    UI.title := Place("Text", "", SL.cx, 14, SL.cw, 38, "0x80 Background" Hex6(th.win), "", 20, "w600", th.text)
    BuildGeneralPage()
    BuildKeysPage()
    BuildNotificationsPage()
    BuildUpdatesPage()
    BuildAdvancedPage()
    BuildAboutPage()

    ThemeTitleBar(g.Hwnd)
    RefreshSettings()
    ShowPage(page)
    w := Px(SL.W), h := Px(SL.H)
    if (posX = "")
        posX := wl + (wr - wl - w) // 2, posY := wt + Max(0, (wb - wt - h) // 2 - Px(20))
    showOpts := "x" posX " y" posY " w" w " h" h
    g.Show(showOpts)
    PMv2(old)
}

; ---- Pages -----------------------------------------------------------------

BuildGeneralPage() {
    grp := Group("general", 70)
    y := Row(grp, 64)
    RowText("general", y, 64, "Remapping", "Off: all keys work as usual until you turn it back on.", 470)
    NewSwitch("remapping", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Start with Windows", "Start the app when you sign in.", 470)
    NewSwitch("autostart", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Show the icon in the tray", "If it's hidden, open the app again to see this window.", 470)
    NewSwitch("trayIcon", "general", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("general", y, 64, "Theme", "Colors of this window and of the tray menu.", 330)
    UI.theme := NewList("general", SL.rx - 160, y + 17, 160, THEME_PREFS, OnThemeChange)

    grp := Group("general", grp.y + grp.h + 16, "App")
    y := Row(grp, 64)
    RowText("general", y, 64, "Restart the app", "Closes it and opens it again, e.g. after editing settings.ini.", 420)
    NewButton("general", SL.rx - 110, y + 16, 110, "Restart", "danger").OnEvent("Click", (*) => RestartApp())
    y := Row(grp, 64)
    RowText("general", y, 64, "Exit the app", "Keys work as usual until you open it again.", 420)
    NewButton("general", SL.rx - 110, y + 16, 110, "Exit", "danger").OnEvent("Click", (*) => ExitApp())
}

BuildKeysPage() {
    th := UI.th, x := SL.cx + 16
    grp := Group("keys", 70, "Remap a key")
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Key", "", SL.kvX - 10 - x)
    UI.srcDesc := r.desc
    UI.srcKeys := NewKeyView("source", "keys", SL.kvX, y + 15)
    UI.srcBtn := NewButton("keys", SL.btnX, y + 16, 96, "Change…")
    UI.srcBtn.OnEvent("Click", (*) => CaptureToggle("source"))
    y := Row(grp, 92)
    RowText("keys", y, 92, "Action", "", SL.kvX - 10 - x, "", 17)
    UI.mode := NewList("keys", SL.kvX, y + 13, SL.rx - SL.kvX, MODE_LABELS, OnModeChange)
    UI.actionInfo := Place("Text", "keys", x, y + 54, SL.rx - x, 20, "0x80 Background" Hex6(th.card), "", 9, "w400", th.sub)
    first := UI.items.Length + 1
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Sends", "What to press instead.", SL.kvX - 10 - x)
    UI.targetTitle := r.title, UI.targetDesc := r.desc
    UI.targetKeys := NewKeyView("target", "keys", SL.kvX, y + 15)
    UI.targetBtn := NewButton("keys", SL.btnX, y + 16, 96, "Change…")
    UI.targetBtn.OnEvent("Click", (*) => CaptureToggle("target"))
    ; The Sends row only exists for "Press another key": SetSendsRow
    UI.sends := {shown: true, h: 64, grp: grp, div: grp.dividers[grp.dividers.Length], items: ItemsFrom(first)}

    first := UI.items.Length + 1
    grp := Group("keys", grp.y + grp.h + 16, "NitroSense shortcut")
    UI.sends.below := grp
    y := Row(grp, 64)
    RowText("keys", y, 64, "Open an app with a shortcut", "By default, Right Ctrl + NitroSense key opens NitroSense.", SL.rx - 50 - x)
    NewSwitch("launchEnabled", "keys", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "Shortcut", "", SL.kvX - 10 - x)
    UI.launchTitle := r.title, UI.launchDesc := r.desc
    UI.launchKeys := NewKeyView("launch", "keys", SL.kvX, y + 15)
    UI.launchBtn := NewButton("keys", SL.btnX, y + 16, 96, "Change…")
    UI.launchBtn.OnEvent("Click", (*) => CaptureToggle("launch"))
    y := Row(grp, 52)
    r := RowText("keys", y, 52, "Distinguish left and right modifiers", "", SL.rx - 80 - x
               , "On: only the exact keys of the shortcut work (for example Right Ctrl).`n"
               . "Off: the same key on either side works too (Left or Right Ctrl).")
    UI.sidesTitle := r.title
    NewSwitch("distinguish", "keys", SL.rx - 40, y + 16)
    y := Row(grp, 64)
    r := RowText("keys", y, 64, "App to open", "", SL.btnX - 82 - x)
    UI.appTitle := r.title, UI.appStatus := r.desc
    UI.auto := NewButton("keys", SL.btnX - 72, y + 16, 64, "Auto")
    UI.browse := NewButton("keys", SL.btnX, y + 16, 96, "Browse…")
    UI.auto.OnEvent("Click", AutoApp)
    UI.browse.OnEvent("Click", BrowseApp)
    UI.sends.belowItems := ItemsFrom(first)
}

ItemsFrom(first) {                      ; the controls added since UI.items[first]
    out := []
    loop UI.items.Length - first + 1
        out.Push(UI.items[first + A_Index - 1])
    return out
}

; Shows or hides the Sends row; the rows below move up or down
SetSendsRow(show) {
    sd := UI.sends
    if (sd.shown = show)
        return
    sd.shown := show
    dy := show ? sd.h : -sd.h
    for item in sd.items {
        item.hidden := !show
        item.ctl.Visible := show && UI.page = "keys"
    }
    sd.grp.h += dy
    if show
        sd.grp.dividers.Push(sd.div)
    else
        sd.grp.dividers.Pop()
    sd.below.y += dy
    for item in sd.belowItems
        item.y += dy
    if (UI.page != "keys") {
        UI.laidOut["keys"] := 0             ; laid out when the section is shown
        return
    }
    old := PMv2()
    Freeze(true)
    LayoutPage("keys")
    RenderPageBackground()
    Freeze(false)
    PMv2(old)
}

BuildNotificationsPage() {
    grp := Group("notifications", 70)
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Show notifications", "Always = at startup, after unlocking and on screen wake.", 300)
    UI.toastWhen := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_WHEN_LABELS
                          , (ctl, *) => (DRAFT.toastWhen := TOAST_WHENS[ctl.Value]
                                       , CommitDraft("Notifications: " TOAST_WHEN_LABELS[ctl.Value])))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Position", "Where they appear on the screen.", 270)
    UI.toastPos := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_POSITION_LABELS
                         , (ctl, *) => (DRAFT.toastPosition := TOAST_POSITIONS[ctl.Value]
                                      , CommitDraft("Position: " TOAST_POSITION_LABELS[ctl.Value])))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Animation", "How they appear and leave.", 270)
    UI.toastAnim := NewList("notifications", SL.rx - 220, y + 17, 220, TOAST_ANIM_LABELS
                          , (ctl, *) => (DRAFT.toastAnim := TOAST_ANIMS[ctl.Value]
                                       , CommitDraft("Animation: " TOAST_ANIM_LABELS[ctl.Value])))
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Transparency effects", "Frosted glass. It can be heavy for older or low-power PCs.", 470
          , "On: the notification blurs what's behind it (a screen capture each time).`n"
          . "Off: a solid card in the colors of this window.")
    NewSwitch("toastGlass", "notifications", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    RowText("notifications", y, 64, "Preview", "Show a notification with these settings.", 330)
    NewButton("notifications", SL.rx - 160, y + 16, 160, "Show a test").OnEvent("Click", PreviewToast)
}

BuildUpdatesPage() {
    grp := Group("updates", 70)
    y := Row(grp, 64)
    RowText("updates", y, 64, "Check for updates automatically", "Once a day, from GitHub. Nothing about you is sent.", 470)
    NewSwitch("checkUpdates", "updates", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("updates", y, 64, "Version " APP.version, "", 340)
    UI.updText := r.desc
    UI.updBtn := NewButton("updates", SL.rx - 170, y + 16, 170, "Check now")
    UI.updBtn.OnEvent("Click", (*) => UpdateAction())
    y := Row(grp, 64)
    RowText("updates", y, 64, "Release notes", "What changed in each version.", 400)
    NewButton("updates", SL.rx - 96, y + 16, 96, "Open").OnEvent("Click", (*) => Run(APP.repo "/releases"))
}

BuildAdvancedPage() {
    grp := Group("advanced", 70)
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Exact key match", "Recommended for vendor keys like NitroSense.", 400
          , "Also compares the scan code, not only the key code. Needed when several`n"
          . "keys share a code, like the NitroSense key and Win Lock (Fn+Win) on Acer`n"
          . "laptops. Turn it off only if your key changes its scan code.")
    NewSwitch("matchSC", "advanced", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("advanced", y, 64, "Settings file", "", SL.rx - 140 - SL.cx - 16)
    UI.settingsPath := r.desc
    NewButton("advanced", SL.rx - 130, y + 16, 130, "Open folder").OnEvent("Click", (*) => OpenSettingsFolder())
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Reset all settings", "Puts every option back to its default value.", 400)
    NewButton("advanced", SL.rx - 110, y + 16, 110, "Reset…", "danger").OnEvent("Click", ResetSettings)

    grp := Group("advanced", grp.y + grp.h + 16, "Developer")
    y := Row(grp, 64)
    RowText("advanced", y, 64, "Write a log", "What the app does, with times. For finding problems.", 400
          , "Writes one line per event (start, settings changes, the remapped key's`n"
          . "actions, notifications, updates, sleep, shutdown) to Win11KeyRemapper.log,`n"
          . "next to the settings file. It never records the keys you type.`n`n"
          . "Each line takes a fraction of a millisecond and the file stays under about`n"
          . "2 MB, so it doesn't slow anything down. Check it before sharing it: it`n"
          . "contains folder paths.")
    NewSwitch("log", "advanced", SL.rx - 40, y + 22)
    y := Row(grp, 64)
    r := RowText("advanced", y, 64, "Log file", "", SL.rx - 110 - SL.cx - 16)
    UI.logPath := r.desc
    NewButton("advanced", SL.rx - 100, y + 16, 100, "Open").OnEvent("Click", OpenLog)
}

BuildAboutPage() {
    ; The app card is the link to the project page
    NewWidget("card", "about", SL.cx, 70, SL.cw, 100).OnEvent("Click", (*) => Run(APP.repo))
    y := 70 + 100 + 16
    for section in LINKS {
        grp := Group("about", y, section[1])
        for link in section[2] {
            ry := Row(grp, 44)
            NewWidget("link", "about", SL.cx + 4, ry + 4, SL.cw - 8, 36, {label: link[1], glyph: link[3]})
                .OnEvent("Click", OpenUrl.Bind(APP.repo link[2]))
        }
        y := grp.y + grp.h + 16
    }
}

OpenUrl(url, *) => Run(url)

; ---- Building blocks ---------------------------------------------------------

Px(n) => Round(n * UI.k)
FontPts(pts) => Round(pts * UI.dpi / A_ScreenDPI, 2)   ; AutoHotkey sizes fonts for the main monitor

DpiAt(x, y) {
    hMon := DllCall("MonitorFromPoint", "int64", (x & 0xFFFFFFFF) | (y << 32), "uint", 2, "ptr")
    dx := 0, dy := 0
    try {
        if DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dx, "uint*", &dy) = 0 && dx
            return dx
    }
    return A_ScreenDPI
}

; Adds a control at logical coordinates and remembers it for DPI changes.
; page "" = always visible (sidebar, header); other sections start hidden.
Place(type, page, x, y, w, h, opts := "", text := "", pts := 10, style := "w400", color := -1, fontName := "Segoe UI") {
    item := {x: x, y: y, w: w, h: h, pts: pts, style: style, color: color, fontName: fontName, page: page, hidden: false}
    ItemFont(UI.gui, item)
    pos := "x" Px(x) " y" Px(y) " w" Px(w) (h != "" ? " h" Px(h) : "")
    if (page != "" && page != UI.page)
        opts .= " Hidden"
    ctl := UI.gui.Add(type, pos " " opts, text)
    item.ctl := ctl
    UI.items.Push(item)
    UI.itemOf[ctl.Hwnd] := item
    return ctl
}

ItemFont(target, item) {                ; target: the Gui (before adding) or the control
    target.SetFont("s" FontPts(item.pts) " " item.style (item.color >= 0 ? " c" Hex6(item.color) : ""), item.fontName)
}

; Text color that survives a DPI change (ItemFont applies it again)
SetColor(ctl, color) {
    item := UI.itemOf[ctl.Hwnd]
    if (item.color = color)
        return
    item.color := color
    ctl.SetFont("c" Hex6(color))
}

AddIcon(x, y, size) {                   ; the app icon, in the sidebar
    if !(A_IsCompiled || FileExist(IconPath()))     ; from source, assets\ may be missing
        return
    ctl := Place("Picture", "", x, y, size, size, A_IsCompiled ? "Icon1" : "", A_IsCompiled ? A_ScriptFullPath : IconPath())
    UI.icons.Push({ctl: ctl, size: size})
}

IconSpec(size) => (A_IsCompiled ? "*icon1 " : "") "*w" Px(size) " *h" Px(size) " " (A_IsCompiled ? A_ScriptFullPath : IconPath())

; A card group; the rows are added with Row(). Optional section title above.
Group(page, y, title := "") {
    if (title != "")
        Place("Text", page, SL.cx + 2, y, 400, 22, "0x80 Background" Hex6(UI.th.win), title, 10.5, "w600", UI.th.text), y += 28
    grp := {x: SL.cx, y: y, w: SL.cw, h: 0, dividers: []}
    UI.groups[page].Push(grp)
    return grp
}

Row(grp, h) {
    if grp.h
        grp.dividers.Push(grp.h)
    y := grp.y + grp.h
    grp.h += h
    return y
}

; Title and description on the left of a row; optional ⓘ with a tooltip
RowText(page, y, h, title, desc, textW, info := "", titleY := "") {
    th := UI.th, x := SL.cx + 16, bg := " Background" Hex6(th.card)
    if (titleY = "")
        titleY := desc = "" && h <= 52 ? (h - 20) // 2 : 12
    out := {desc: 0}
    out.title := Place("Text", page, x, y + titleY, textW, 20, "0x80" bg, title, 10.5, "w400", th.text)
    if (desc != "" || titleY = 12)
        out.desc := Place("Text", page, x, y + 34, textW, 18, "0x4080" bg, desc, 9, "w400", th.sub)
    if (info != "") {                       ; the ⓘ goes right after the title
        tw := TextWidth(out.title, title) + 2
        UI.itemOf[out.title.Hwnd].w := tw
        out.title.Move(, , Px(tw))
        icon := Place("Text", page, x + tw + 6, y + titleY + 2, 18, 18, bg, Chr(0xE946), 10, "w400", th.sub, UI.iconFont)
        icon.OnEvent("Click", (ctl, *) => ShowInfoTip(ctl.Hwnd))
        UI.infoTips[icon.Hwnd] := info
        UI.hand[icon.Hwnd] := true
    }
    return out
}

TextWidth(ctl, text) {                  ; in logical pixels, with the control's font
    hdc := DllCall("GetDC", "ptr", ctl.Hwnd, "ptr")
    font := SendMessage(0x31, 0, 0, ctl)                    ; WM_GETFONT
    old := DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr")
    sz := Buffer(8, 0)
    DllCall("GetTextExtentPoint32", "ptr", hdc, "str", text, "int", StrLen(text), "ptr", sz)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", ctl.Hwnd, "ptr", hdc)
    return Ceil(NumGet(sz, 0, "int") / UI.k)
}

NewWidget(kind, page, x, y, w, h, props := "") {
    return UiWidget(Place("Picture", page, x, y, w, h, "0x10E"), kind, w, h, props)    ; SS_BITMAP | SS_NOTIFY (mouse input)
}

; variant: "" (normal), "danger" (red, like GitHub's danger zone), "accent" (green)
NewButton(page, x, y, w, text, variant := "") => NewWidget("button", page, x, y, w, 32, {_text: text, variant: variant})

NewList(page, x, y, w, items, onChange) {
    ddl := Place("DropDownList", page, x, y, w, "", "AltSubmit", items, 10, "w400", UI.th.text)
    ThemeCtl(ddl)
    ddl.OnEvent("Change", onChange)
    UI.hand[ddl.Hwnd] := true
    return ddl
}

; The keys of a shortcut drawn as keycaps; click = same as "Change…"
NewKeyView(name, page, x, y) {
    return NewWidget("keys", page, x, y, UI.kvW, 34, {parts: [], listen: false})
        .OnEvent("Click", (*) => CaptureToggle(name))
}

; On/off switch: clicking it flips the setting
NewSwitch(name, page, x, y) {
    UI.tg[name] := NewWidget("switch", page, x, y, 40, 20)
    return UI.tg[name].OnEvent("Click", (*) => FlipSwitch(name))
}

; A custom-drawn control: a Picture redrawn for each state. Hidden ones are
; only marked and get drawn when their section is shown.
class UiWidget {
    __New(ctl, kind, lw, lh, props := "") {
        this.ctl := ctl, this.kind := kind, this.lw := lw, this.lh := lh
        this._text := "", this._enabled := true, this.variant := "", this.on := "", this.pos := 0
        this.hover := false, this.press := false, this.dirty := true, this.onClick := 0
        if IsObject(props)
            for name, value in props.OwnProps()
                this.%name% := value
        UI.widgets[ctl.Hwnd] := this
    }
    Text {
        get => this._text
        set {
            if (value == this._text)
                return
            this._text := value
            this.Draw()
        }
    }
    Enabled {
        get => this._enabled
        set {
            value := value ? true : false
            if (value = this._enabled)
                return
            this._enabled := value
            if !value
                this.hover := false, this.press := false
            this.Draw()
        }
    }
    Visible {
        get => this.ctl.Visible
        set => this.ctl.Visible := value
    }
    Hwnd => this.ctl.Hwnd
    GetPos(&x := 0, &y := 0, &w := 0, &h := 0) => this.ctl.GetPos(&x, &y, &w, &h)
    OnEvent(name, fn) {                 ; "Click": button-up over the widget
        this.onClick := fn
        return this
    }
    Update(props) {                     ; several fields at once, one redraw
        for name, value in props.OwnProps()
            this.%name% := value
        this.Draw()
    }
    Draw() {
        if !UI.gui
            return
        if !this.ctl.Visible {
            this.dirty := true
            return
        }
        this.dirty := false
        ; Straight to the control: 3x faster than setting .Value. The control
        ; keeps its own copy of a bitmap with alpha; free whatever isn't in use.
        hbm := RenderWidget(this), hwnd := this.ctl.Hwnd
        prev := DllCall("SendMessage", "ptr", hwnd, "uint", 0x172, "ptr", 0, "ptr", hbm, "ptr")   ; STM_SETIMAGE
        cur := DllCall("SendMessage", "ptr", hwnd, "uint", 0x173, "ptr", 0, "ptr", 0, "ptr")      ; STM_GETIMAGE
        if (cur != hbm)
            DllCall("DeleteObject", "ptr", hbm)
        if (prev && prev != cur)
            DllCall("DeleteObject", "ptr", prev)
    }
    Free() {                            ; before the window is destroyed
        if (hbm := DllCall("SendMessage", "ptr", this.ctl.Hwnd, "uint", 0x172, "ptr", 0, "ptr", 0, "ptr"))
            DllCall("DeleteObject", "ptr", hbm)
    }
}

; Stops painting while many controls change, then shows the result in one
; copy (Flip). Nests; does nothing while the window is hidden (WM_SETREDRAW
; would show it). rect: resize the window too (a DPI change), see Flip.
Freeze(on, rect := 0) {
    hwnd := UI.gui.Hwnd
    if on {
        if (UI.frozen++ = 0 && (UI.paintOff := DllCall("IsWindowVisible", "ptr", hwnd)))
            DllCall("SendMessage", "ptr", hwnd, "uint", 0xB, "ptr", 0, "ptr", 0)      ; WM_SETREDRAW
    } else if (--UI.frozen = 0) {
        if UI.paintOff
            Flip(rect)
        else if IsObject(rect)
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", rect.x, "int", rect.y, "int", rect.w, "int", rect.h, "uint", 0x14)
        UI.paintOff := false
    }
}

; Shows the window's new look in one copy, never half-drawn: it's composed
; off-screen first (ComposeWindow), still frozen; then painting is turned
; back on, the window is resized if needed and the image copied at once.
; Repainting control by control on screen showed half-drawn frames at high
; refresh rates, and resizing first (a monitor with a bigger scale) showed
; the new area black until it was painted: those were the "cuts".
Flip(rect := 0) {
    hwnd := UI.gui.Hwnd, w := Px(SL.W), h := Px(SL.H)
    hdcWin := DllCall("GetDCEx", "ptr", hwnd, "ptr", 0, "uint", 0x2, "ptr")      ; DCX_CACHE, children not clipped
    hdc := DllCall("CreateCompatibleDC", "ptr", hdcWin, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcWin, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    ComposeWindow(hdc)
    DllCall("ReleaseDC", "ptr", hwnd, "ptr", hdcWin)
    DllCall("SendMessage", "ptr", hwnd, "uint", 0xB, "ptr", 1, "ptr", 0)          ; painting back on
    if IsObject(rect)                                                               ; no z-order, no activate, no redraw
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", rect.x, "int", rect.y, "int", rect.w, "int", rect.h, "uint", 0x11C)
    hdcWin := DllCall("GetDCEx", "ptr", hwnd, "ptr", 0, "uint", 0x2, "ptr")
    DllCall("BitBlt", "ptr", hdcWin, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdc, "int", 0, "int", 0, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", hwnd, "ptr", hdcWin)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
    DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x88)     ; validate all: nothing left to repaint piecemeal
    for item in UI.items                    ; drop-down lists don't print their text: they paint it themselves
        if (item.ctl.Type = "DDL" && DllCall("IsWindowVisible", "ptr", item.ctl.Hwnd))
            DllCall("RedrawWindow", "ptr", item.ctl.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x101)   ; invalidate, update now
}

PrintListText(ddl, hdc, cw, ch) {
    font := DllCall("SendMessage", "ptr", ddl.Hwnd, "uint", 0x31, "ptr", 0, "ptr", 0, "ptr")   ; WM_GETFONT
    old := DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr")
    DllCall("SetBkMode", "ptr", hdc, "int", 1)                                    ; transparent
    DllCall("SetTextColor", "ptr", hdc, "uint", Bgr(UI.th.text))
    rc := Buffer(16), NumPut("int", Px(4), "int", 0, "int", cw - Px(28), "int", ch, rc)
    DllCall("DrawText", "ptr", hdc, "str", ddl.Text, "int", -1, "ptr", rc, "uint", 0x8824)  ; one line, centered vertically, "…"
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
}

; Paints the window's client area into hdc as it is laid out now: the
; background, then each visible control. Done by hand because PrintWindow
; clips to the window's current size. Each control prints into a bitmap of
; its own, at its own origin, then is copied to its place: drop-down lists
; clip their text in device coordinates, so with a shifted origin it vanished.
ComposeWindow(hdc) {
    src := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    old := DllCall("SelectObject", "ptr", src, "ptr", UI.bgBmp, "ptr")
    DllCall("BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", UI.bgW, "int", UI.bgH, "ptr", src, "int", 0, "int", 0, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", src, "ptr", old)
    rc := Buffer(16)
    for item in UI.items {
        hwnd := item.ctl.Hwnd
        if !(DllCall("GetWindowLong", "ptr", hwnd, "int", -16) & 0x10000000)        ; WS_VISIBLE (its own)
            continue
        DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
        cw := NumGet(rc, 8, "int") - NumGet(rc, 0, "int"), ch := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        bmp := DllCall("CreateCompatibleBitmap", "ptr", hdc, "int", cw, "int", ch, "ptr")
        old := DllCall("SelectObject", "ptr", src, "ptr", bmp, "ptr")
        DllCall("SendMessage", "ptr", hwnd, "uint", 0x317, "ptr", src, "ptr", 0xE)    ; WM_PRINT: client, frame, background
        if (item.ctl.Type = "DDL")          ; a drop-down list doesn't print its text: draw it
            PrintListText(item.ctl, src, cw, ch)
        DllCall("BitBlt", "ptr", hdc, "int", Px(item.x), "int", Px(item.y), "int", cw, "int", ch, "ptr", src, "int", 0, "int", 0, "uint", 0x00CC0020)
        DllCall("SelectObject", "ptr", src, "ptr", old)
        DllCall("DeleteObject", "ptr", bmp)
    }
    DllCall("DeleteDC", "ptr", src)
}

ShowPage(name, *) {
    if !UI.gui
        return
    old := PMv2()
    prev := UI.page
    UI.page := name
    Freeze(true)
    if (UI.laidOut[name] != UI.dpi)         ; the DPI changed while it was hidden
        LayoutPage(name)
    for item in UI.items
        if (item.page != "" && (item.page = name || item.page = prev))
            item.ctl.Visible := item.page = name && !item.hidden
    for p in PAGES
        if (p[1] = name)
            UI.title.Value := p[2]
    ToolTip()
    UI.tipFor := 0
    SetHot(0)
    RenderPageBackground()
    for hwnd, wd in UI.widgets
        if (wd.dirty && wd.ctl.Visible)
            wd.Draw()
    if (prev != name) {
        UI.nav[prev].Draw()
        nav := UI.nav[name]
        nav.pos := 0                        ; the accent bar grows in
        nav.Draw()
        Animate(nav, 1, 320)
    }
    Freeze(false)
    PMv2(old)
}

; Positions and fonts of one section's controls for the current DPI
; ("" = sidebar and header), moved in one batch
LayoutPage(page) {
    list := []
    for item in UI.items
        if (item.page = page)
            list.Push(item)
    hdwp := DllCall("BeginDeferWindowPos", "int", list.Length, "ptr")
    for item in list                        ; drop-down lists: the height is the open list's
        hdwp := DllCall("DeferWindowPos", "ptr", hdwp, "ptr", item.ctl.Hwnd, "ptr", 0, "int", Px(item.x), "int", Px(item.y)
                      , "int", Px(item.w), "int", Px(item.h = "" ? 300 : item.h), "uint", 0x14, "ptr")
    DllCall("EndDeferWindowPos", "ptr", hdwp)
    for item in list
        if (item.ctl.Type != "Pic")         ; pictures have no font
            ItemFont(item.ctl, item)
    if (page = "")
        for icon in UI.icons
            icon.ctl.Value := IconSpec(icon.size)
    UI.laidOut[page] := UI.dpi
}

; Background (cards of the current section), painted on WM_ERASEBKGND
RenderPageBackground() {
    if UI.bgBmp
        DllCall("DeleteObject", "ptr", UI.bgBmp)
    UI.bgW := Px(SL.W), UI.bgH := Px(SL.H)
    UI.bgBmp := RenderBackground(SL.W, SL.H, UI.groups[UI.page])
}

ShowInfoTip(hwnd) {
    if !UI.infoTips.Has(hwnd)
        return
    UI.tipFor := hwnd
    old := PMv2()
    WinGetPos(&x, &y, &w, &h, hwnd)
    CoordMode("ToolTip", "Screen")
    ToolTip(UI.infoTips[hwnd], x + w + Px(4), y + h + Px(4))
    PMv2(old)
    SetTimer(CheckInfoTip, 250)
}

CheckInfoTip() {
    MouseGetPos(, , , &over, 2)
    if (over = UI.tipFor)
        return
    ToolTip()
    UI.tipFor := 0
    SetTimer(CheckInfoTip, 0)
}

; Moved to a monitor with another scale. Laying everything out again takes
; ~50 ms, which stalled the window in the middle of a drag (the "cut"). So,
; like Chromium does: at once, the window takes the new size with the
; current picture scaled into it (~2 ms) and painting stays frozen; the real
; layout is done when the drag ends (WM_EXITSIZEMOVE), or right away if the
; window wasn't being dragged, and shown in one copy (Flip).
OnSettingsDpiChanged(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd)
        return
    dpi := wParam & 0xFFFF
    if (dpi = UI.dpi && !UI.pendingDpi)     ; e.g. first shown on this monitor: already laid out for it
        return 0
    rect := {x: NumGet(lParam, 0, "int"), y: NumGet(lParam, 4, "int")}
    rect.w := NumGet(lParam, 8, "int") - rect.x, rect.h := NumGet(lParam, 12, "int") - rect.y
    old := PMv2()
    if !DllCall("IsWindowVisible", "ptr", hwnd) && !UI.pendingDpi {     ; hidden: no picture to keep
        UI.dpi := dpi, UI.k := dpi / 96
        ApplyLayout()
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", rect.x, "int", rect.y, "int", rect.w, "int", rect.h, "uint", 0x14)
    } else {
        StretchToNewSize(hwnd, rect)
        UI.pendingDpi := dpi
        if !UI.sizing
            SetTimer(ApplyPendingDpi, -1)
    }
    PMv2(old)
    return 0
}

; The window at its new size, showing the old picture scaled (a moment
; blurry, never black or half-drawn). The first time, the picture is composed
; off-screen (reading it from the window while it moves between monitors
; gave a broken mix) and the controls are hidden: Windows makes them repaint
; after a DPI change, and they did it at their old places, on top of the
; picture. Meanwhile the window itself paints the scaled picture as its
; background (OnSettingsErase), whatever size it gets during the drag.
StretchToNewSize(hwnd, rect) {
    if !UI.dpiShot {
        UI.shotW := Px(SL.W), UI.shotH := Px(SL.H)      ; still the old scale
        hdcWin := DllCall("GetDCEx", "ptr", hwnd, "ptr", 0, "uint", 0x2, "ptr")
        UI.shotDC := DllCall("CreateCompatibleDC", "ptr", hdcWin, "ptr")
        UI.dpiShot := DllCall("CreateCompatibleBitmap", "ptr", hdcWin, "int", UI.shotW, "int", UI.shotH, "ptr")
        DllCall("ReleaseDC", "ptr", hwnd, "ptr", hdcWin)
        UI.shotOld := DllCall("SelectObject", "ptr", UI.shotDC, "ptr", UI.dpiShot, "ptr")
        ComposeWindow(UI.shotDC)
        DllCall("SendMessage", "ptr", hwnd, "uint", 0xB, "ptr", 0, "ptr", 0)      ; hide them without painting
        UI.stretchHidden := []
        for item in UI.items
            if (DllCall("GetWindowLong", "ptr", item.ctl.Hwnd, "int", -16) & 0x10000000) {
                DllCall("ShowWindow", "ptr", item.ctl.Hwnd, "int", 0)
                UI.stretchHidden.Push(item.ctl.Hwnd)
            }
        DllCall("SendMessage", "ptr", hwnd, "uint", 0xB, "ptr", 1, "ptr", 0)
    }
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", rect.x, "int", rect.y, "int", rect.w, "int", rect.h, "uint", 0x114)  ; no z-order, no activate, no copy
    DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x105)      ; the scaled picture, now (one blit)
}

; The real layout for the new scale, shown in one copy
ApplyPendingDpi() {
    if (!UI.gui || !UI.pendingDpi)
        return
    old := PMv2()
    dpi := UI.pendingDpi, t := A_TickCount
    UI.pendingDpi := 0
    Freeze(true)
    for hwnd in UI.stretchHidden            ; back, still frozen: nothing shows yet
        DllCall("ShowWindow", "ptr", hwnd, "int", 8)                              ; SW_SHOWNA
    UI.stretchHidden := []
    FreeDpiShot()
    if (dpi != UI.dpi) {
        UI.dpi := dpi, UI.k := dpi / 96
        ApplyLayout()
    }
    Freeze(false)                           ; composed off-screen, shown at once
    PMv2(old)
    Log("Settings window laid out for " dpi " dpi in " A_TickCount - t " ms")
}

FreeDpiShot() {
    if !UI.dpiShot
        return
    DllCall("SelectObject", "ptr", UI.shotDC, "ptr", UI.shotOld)
    DllCall("DeleteObject", "ptr", UI.dpiShot)
    DllCall("DeleteDC", "ptr", UI.shotDC)
    UI.dpiShot := 0
}

OnSettingsSizeMove(wParam, lParam, msg, hwnd) {   ; WM_ENTERSIZEMOVE / WM_EXITSIZEMOVE
    if (!UI.gui || hwnd != UI.gui.Hwnd)
        return
    UI.sizing := msg = 0x231
    if (!UI.sizing && UI.pendingDpi)
        SetTimer(ApplyPendingDpi, -1)
}

OnSettingsMove(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd)
        return
    NoticeFollow()
    ; While crossing monitors, the parts of the window outside every screen
    ; get no paint (the screens don't line up) and would show stale pixels
    ; when they come back: paint the scaled picture again (coalesced by Windows)
    if UI.dpiShot
        DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x5)     ; invalidate + erase
}

; ---- Notices inside the settings window --------------------------------------
; What the user just did ("Theme: Dark · Saved", the answer of Check now,
; errors). Separate from the system notifications on purpose: its own small
; window, state (NT) and timer, so neither replaces the other and the
; notifications setting has nothing to do with it. A solid pill drawn once,
; at the bottom center of the window; it rises a little while fading in,
; stays, and goes. The window is owned by the settings window (always above
; it, closed with it) and click-through, so it can't be clicked away.

Notice(title, sub := "Saved", kind := "ok", holdMs := 2500) {
    if (kind = "warn")                      ; the rest just confirm what's already logged
        Log("Warning shown: " title " | " sub)
    if !UI.gui                              ; window closed: a system notification
        return SystemToast(title, sub, kind, Max(holdMs, 4000))
    NT.last := title " · " sub
    if !DllCall("IsWindowVisible", "ptr", UI.gui.Hwnd)
        return
    NoticeFree()
    old := PMv2()
    try NoticeBuild(title, sub, kind)
    PMv2(old)
    if !NT.hwnd
        return
    NT.phase := "in", NT.t0 := A_TickCount, NT.holdMs := holdMs
    NT.inMs := AnimationsOn() ? 240 : 0
    SetTimer(NoticeStep, 10)
}

NoticeBuild(title, sub, kind) {
    th := UI.th, k := UI.k, host := UI.gui.Hwnd
    h := Round(46 * k), pad := Round(12 * k), icon := Round(24 * k)   ; pad: room for the shadow
    famSB := FontFamily("Segoe UI Semibold"), famR := FontFamily("Segoe UI")
    fTitle := GT_Font(famSB ? famSB : famR, 13.5 * k, famSB ? 0 : 1), fSub := GT_Font(famR, 13 * k, 0)
    fmt := NewFormat(0)
    DllCall("gdiplus\GdipSetStringFormatTrimming", "ptr", fmt, "int", 3)       ; "…" if it doesn't fit
    mb := GT_Bitmap(1, 1), mg := GT_BmpGraphics(mb)
    tw := GT_MeasureW(mg, title, fTitle, fmt), sw := sub != "" ? GT_MeasureW(mg, sub, fSub, fmt) : 0
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", mg), DllCall("gdiplus\GdipDisposeImage", "ptr", mb)
    w := Round(Min(11 * k + icon + 10 * k + tw + (sw ? 8 * k + sw : 0) + 18 * k, 520 * k))
    winW := w + 2 * pad, winH := h + 2 * pad

    ; 32-bit canvas for UpdateLayeredWindow
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", winW, bi, 4), NumPut("int", -winH, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr"), bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    g := 0
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", &g)
    GT_Quality(g)                           ; antialiased text: the background is transparent
    loop 4                                  ; soft shadow: a few faint, growing pills
        FillPathFree(g, GT_RoundPath(pad - A_Index * k, pad - A_Index * k + 2 * k, w + 2 * A_Index * k, h + 2 * A_Index * k
                   , h / 2 + A_Index * k), Argb(0x000000, th.dark ? 0x18 : 0x0C))
    FillPathFree(g, GT_RoundPath(pad, pad, w, h, h / 2), Argb(th.btnFace))
    StrokePathFree(g, GT_RoundPath(pad + 0.5, pad + 0.5, w - 1, h - 1, h / 2 - 0.5), Argb(th.btnEdge), 1)
    ix := pad + 11 * k, iy := pad + (h - icon) / 2
    color := kind = "warn" ? 0xFFFF9F0A : kind = "ok" ? Argb(th.on) : 0xFF0A84FF
    FillCircle(g, ix, iy, icon, color)
    switch kind {
        case "warn":   GT_Exclaim(g, ix, iy, icon, 0xFFFFFFFF)
        case "info":   GT_PauseBars(g, ix, iy, icon, 0xFFFFFFFF)
        case "update": GT_DownArrow(g, ix, iy, icon, 0xFFFFFFFF)
        default:       GT_Check(g, ix, iy, icon, 0xFFFFFFFF)
    }
    tx := ix + icon + 10 * k
    GT_Text(g, title, fTitle, Argb(th.text), tx, pad, tw + 2, h, fmt)
    if sw
        GT_Text(g, sub, fSub, Argb(th.sub), tx + tw + 8 * k, pad, w - (tx - pad) - tw - 8 * k - 12 * k, h, fmt)
    FreeAll([fTitle, fSub], [fmt])
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", g)

    ; Bottom center of the window's client area
    rc := Buffer(16), pt := Buffer(8, 0)
    DllCall("GetClientRect", "ptr", host, "ptr", rc)
    DllCall("ClientToScreen", "ptr", host, "ptr", pt)
    NT.hostX := NumGet(pt, 0, "int"), NT.hostY := NumGet(pt, 4, "int")
    NT.x := NT.hostX + (NumGet(rc, 8, "int") - winW) // 2
    NT.yVis := NT.hostY + NumGet(rc, 12, "int") - Round(16 * k) - h - pad
    NT.yHid := NT.yVis + Round(12 * k)

    gw := Gui("-Caption +ToolWindow +E0x80000 +E0x08000000 +E0x20 +Owner" host)   ; layered, no-activate, click-through
    gw.Show("NA x-32000 y-32000 w1 h1")
    NT.gui := gw, NT.hwnd := gw.Hwnd
    pos := Buffer(8), NumPut("int", NT.x, "int", NT.yHid, pos)
    sz := Buffer(8), NumPut("int", winW, "int", winH, sz)
    src := Buffer(8, 0)
    DllCall("UpdateLayeredWindow", "ptr", NT.hwnd, "ptr", 0, "ptr", pos, "ptr", sz
          , "ptr", hdc, "ptr", src, "uint", 0, "uint*", 1 << 24, "uint", 2)          ; drawn once, alpha 0
    DllCall("SelectObject", "ptr", hdc, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", hdc)
}

NoticeStep() {
    Critical
    now := A_TickCount
    switch NT.phase {
        case "in":
            p := NT.inMs ? Min((now - NT.t0) / NT.inMs, 1) : 1
            y := NT.yHid + (NT.yVis - NT.yHid) * GT_EaseOutBack(p, 1.4), a := 255 * GT_EaseOutCubic(p)
            if (p >= 1)
                NT.phase := "hold", NT.until := now + NT.holdMs
        case "hold":
            if (now >= NT.until)
                NT.phase := "out", NT.t0 := now
            return
        case "out":
            p := NT.inMs ? Min((now - NT.t0) / 180, 1) : 1
            if (p >= 1)
                return NoticeFree()
            e := GT_EaseInCubic(p)
            y := NT.yVis + (NT.yHid - NT.yVis) * e, a := 255 * (1 - e)
        default:
            SetTimer(NoticeStep, 0)
            return
    }
    NoticeMove(y, a)
}

NoticeMove(y, alpha) {                  ; no bitmap: only the position and the fade change
    old := PMv2()
    pt := Buffer(8), NumPut("int", NT.x, "int", Round(y), pt)
    blend := (Max(0, Min(255, Round(alpha))) << 16) | (1 << 24)
    DllCall("UpdateLayeredWindow", "ptr", NT.hwnd, "ptr", 0, "ptr", pt, "ptr", 0
          , "ptr", 0, "ptr", 0, "uint", 0, "uint*", blend, "uint", 2)
    PMv2(old)
}

NoticeFollow() {                        ; the settings window moved
    if !NT.hwnd
        return
    old := PMv2()
    pt := Buffer(8, 0)
    DllCall("ClientToScreen", "ptr", UI.gui.Hwnd, "ptr", pt)
    PMv2(old)
    dx := NumGet(pt, 0, "int") - NT.hostX, dy := NumGet(pt, 4, "int") - NT.hostY
    NT.hostX += dx, NT.hostY += dy, NT.x += dx, NT.yVis += dy, NT.yHid += dy
    if (NT.phase = "hold" && (dx || dy))
        NoticeMove(NT.yVis, 255)
}

NoticeFree() {
    SetTimer(NoticeStep, 0)
    if NT.gui {
        try NT.gui.Destroy()
    }
    NT.gui := 0, NT.hwnd := 0, NT.phase := ""
}

ApplyLayout() {
    old := PMv2()
    Freeze(true)
    LayoutPage("")
    LayoutPage(UI.page)                     ; the other sections when they're shown
    RenderPageBackground()
    if UI.cardIcon
        DllCall("DestroyIcon", "ptr", UI.cardIcon), UI.cardIcon := 0
    for hwnd, wd in UI.widgets
        wd.Draw()
    Freeze(false)
    PMv2(old)
}

; ---- Mouse: hover, press, click, cursor ---------------------------------------

OnSettingsSetCursor(wParam, lParam, msg, hwnd) {
    static hand := DllCall("LoadCursor", "ptr", 0, "ptr", 32649, "ptr")    ; IDC_HAND
    if (!UI.gui || hwnd != UI.gui.Hwnd || (lParam & 0xFFFF) != 1)          ; HTCLIENT
        return
    if (UI.widgets.Has(wParam) ? UI.widgets[wParam]._enabled : UI.hand.Has(wParam)) {
        DllCall("SetCursor", "ptr", hand)
        return 1
    }
}

OnSettingsMouseMove(wParam, lParam, msg, hwnd) {
    if !UI.gui
        return
    if (UI.infoTips.Has(hwnd) && UI.tipFor != hwnd)
        ShowInfoTip(hwnd)
    if !UI.widgets.Has(hwnd) {
        if UI.hot
            SetHot(0)
        return
    }
    wd := UI.widgets[hwnd]
    if wd.press {                           ; captured: looks pressed only while over it
        inside := InClient(hwnd, lParam)
        if (inside != wd.hover)
            wd.hover := inside, wd.Draw()
    } else if wd._enabled
        SetHot(hwnd)
}

OnSettingsMouseDown(wParam, lParam, msg, hwnd) {
    if (!UI.gui || !UI.widgets.Has(hwnd))
        return
    wd := UI.widgets[hwnd]
    if wd._enabled {
        wd.press := true, wd.hover := true
        DllCall("SetCapture", "ptr", hwnd)
        wd.Draw()
    }
    return 0
}

OnSettingsMouseUp(wParam, lParam, msg, hwnd) {
    if (!UI.gui || !UI.widgets.Has(hwnd))
        return
    wd := UI.widgets[hwnd]
    if !wd.press
        return 0
    inside := InClient(hwnd, lParam)
    wd.press := false, wd.hover := inside
    DllCall("ReleaseCapture")
    wd.Draw()
    if (inside && wd._enabled && wd.onClick)
        SetTimer(wd.onClick.Bind(wd), -1)   ; not inside the message handler
    return 0
}

InClient(hwnd, lParam) {
    x := lParam << 48 >> 48, y := lParam << 32 >> 48       ; signed client coordinates
    rc := Buffer(16)
    DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
    return x >= 0 && y >= 0 && x < NumGet(rc, 8, "int") && y < NumGet(rc, 12, "int")
}

; The widget under the mouse (hwnd, 0 = none) gets the hover look
SetHot(hwnd) {
    if (UI.hot = hwnd || UI.pendingDpi)
        return
    if (UI.hot && UI.widgets.Has(UI.hot)) {
        wd := UI.widgets[UI.hot]
        wd.hover := false
        wd.Draw()
    }
    UI.hot := hwnd
    if hwnd {
        wd := UI.widgets[hwnd]
        wd.hover := true
        wd.Draw()
    }
    SetTimer(CheckHot, hwnd ? 50 : 0)
}

CheckHot() {                            ; the mouse left the window, or a press got lost
    if (!UI.gui || !UI.hot || !UI.widgets.Has(UI.hot)) {
        SetTimer(CheckHot, 0)
        return
    }
    wd := UI.widgets[UI.hot]
    if wd.press {
        if (DllCall("GetKeyState", "int", 1, "short") < 0)
            return
        wd.press := false
        DllCall("ReleaseCapture")
    }
    MouseGetPos(, , , &over, 2)
    if (over != UI.hot)
        SetHot(0)
    else
        wd.Draw()
}

; ---- Animation ---------------------------------------------------------------
; Widgets animate their "pos" (a switch's knob, a sidebar entry's accent bar)
; with a small overshoot. Skipped when Windows' animation effects are off.

Animate(wd, to, ms := 260) {
    if (!wd.ctl.Visible || !AnimationsOn()) {
        if UI.anims.Has(wd)
            UI.anims.Delete(wd)
        wd.pos := to
        wd.Draw()
        return
    }
    UI.anims[wd] := {from: wd.pos, to: to, t0: A_TickCount, ms: ms}
    SetTimer(AnimTick, 10)
}

AnimTick() {
    if (!UI.gui || !UI.anims.Count) {
        SetTimer(AnimTick, 0)
        return
    }
    if UI.pendingDpi                        ; waiting for the new layout
        return
    now := A_TickCount
    for wd, a in UI.anims.Clone() {
        p := Min((now - a.t0) / a.ms, 1)
        wd.pos := p >= 1 ? a.to : a.from + (a.to - a.from) * GT_EaseOutBack(p, 1.7)
        if (p >= 1)
            UI.anims.Delete(wd)
        wd.Draw()
    }
}

AnimationsOn() {                        ; Settings > Accessibility > Visual effects > Animation effects
    on := 1
    DllCall("SystemParametersInfo", "uint", 0x1042, "uint", 0, "int*", &on, "uint", 0)   ; SPI_GETCLIENTAREAANIMATION
    return on
}

; ---- State -> window -----------------------------------------------------------

FlipSwitch(name) {
    if (!UI.gui || !UI.tg[name].Enabled)
        return
    switch name {
        case "remapping":
            SetPaused(!PAUSED, false)
            Notice(OnOff(name, !PAUSED), PAUSED ? "Keys work as usual until you turn it back on" : Summary())
        case "autostart":
            if SetAutostart(!FileExist(APP.lnk))
                Notice(OnOff(name, FileExist(APP.lnk) != ""))
            RefreshSettings()
        case "distinguish":
            DRAFT.launchAnySide := !DRAFT.launchAnySide
            CommitDraft(OnOff(name, !DRAFT.launchAnySide))
        default:
            DRAFT.%name% := !DRAFT.%name%
            if (name = "launchEnabled" && !DRAFT.launchEnabled && CAP.active && CAP.target = "launch")
                CaptureCancel()
            CommitDraft(OnOff(name, DRAFT.%name%))
    }
}

OnOff(name, on) => SWITCH_LABELS[name] ": " (on ? "on" : "off")

; Applies and saves the draft if it's complete; otherwise the row that needs
; something says so and the active settings stay as they were. what = the
; title of the "saved" notice.
CommitDraft(what := "") {
    global CFG
    UI.problem := ValidateSettings(DRAFT, &where), UI.problemWhere := where
    if (UI.problem != "") {
        RefreshSettings()
        return false
    }
    themeChanged := UI.gui && ThemeName(DRAFT.theme) != UI.themeName
    hidingIcon := CFG.trayIcon && !DRAFT.trayIcon
    CFG := CloneSettings(DRAFT)
    try WriteSettings(SETTINGS_PATH, CFG)
    catch as e {
        Log("Couldn't save the settings: " e.Message)
        what := ""
        Notice("Couldn't save the settings", e.Message, "warn", 5000)
    }
    if (what != "")
        Log("Setting changed: " what)
    ApplySettings()
    ApplyAppTheme(CFG.theme)
    ScheduleUpdateCheck()
    if (hidingIcon && what != "") {
        what := ""
        Notice("The tray icon is hidden", "To see this window again, open the app again", "info", 6000)
    }
    if themeChanged                         ; rebuilt, but not from inside the control's own event
        SetTimer(() => (RebuildSettings(), what != "" ? Notice(what) : 0), -1)
    else {
        RefreshSettings()
        if (what != "")
            Notice(what)
    }
    return true
}

RefreshSettings() {
    if !UI.gui
        return
    old := PMv2()
    d := DRAFT, th := UI.th
    listening := CAP.active ? CAP.target : ""
    isKey := d.mode = "Key", on := d.launchEnabled ? 1 : 0

    UI.status.Value := PAUSED ? "Paused" : "Active"
    SetColor(UI.status, PAUSED ? th.warn : th.ok)

    ; General
    SetSwitch("remapping", !PAUSED)
    SetSwitch("autostart", FileExist(APP.lnk) != "")
    SetSwitch("trayIcon", d.trayIcon)
    UI.theme.Value := ChoiceIndex(THEME_PREFS, d.theme)

    ; Keys
    SetKeyView("source", UI.srcKeys, [], d.sourceVK, d.sourceSC, false, listening = "source")
    UI.srcBtn.Text := listening = "source" ? "Cancel" : "Change…"
    UI.mode.Value := ChoiceIndex(MODES, d.mode)
    UI.actionInfo.Value := ACTION_INFO[d.mode]
    SetSendsRow(isKey)
    SetKeyView("target", UI.targetKeys, d.targetMods, d.targetVK, d.targetSC, false, listening = "target")
    UI.targetBtn.Text := listening = "target" ? "Cancel" : "Change…"
    RowNote(UI.srcDesc, "source", KeyCode(d.sourceVK, d.sourceSC))
    RowNote(UI.targetDesc, "target", KeyCode(d.targetVK, d.targetSC))

    SetSwitch("launchEnabled", on)
    SetKeyView("launch", UI.launchKeys, d.launchMods, d.launchVK, d.launchSC, d.launchAnySide, listening = "launch", !on)
    UI.launchBtn.Update({_text: listening = "launch" ? "Cancel" : "Change…", _enabled: on})
    SetSwitch("distinguish", !d.launchAnySide, !on)
    UI.auto.Enabled := on, UI.browse.Enabled := on
    for ctl in [UI.launchTitle, UI.sidesTitle, UI.appTitle]
        SetColor(ctl, on ? th.text : th.dim)
    RowNote(UI.launchDesc, "launch", KeyCode(d.launchVK, d.launchSC), !on)
    UpdateApp()

    ; Notifications
    UI.toastWhen.Value := ChoiceIndex(TOAST_WHENS, d.toastWhen)
    UI.toastPos.Value := ChoiceIndex(TOAST_POSITIONS, d.toastPosition)
    UI.toastAnim.Value := ChoiceIndex(TOAST_ANIMS, d.toastAnim)
    SetSwitch("toastGlass", d.toastGlass)

    ; Updates
    SetSwitch("checkUpdates", d.checkUpdates)
    UpdateUpdatesRow()

    ; Advanced
    SetSwitch("matchSC", d.matchSC)
    UI.settingsPath.Value := SETTINGS_PATH
    SetSwitch("log", d.log)
    UI.logPath.Value := LogPath()
    PMv2(old)
}

; A row's description, or what's missing (in red) if the problem is there
RowNote(ctl, where, normal, dim := false) {
    th := UI.th
    if (UI.problemWhere = where) {
        ctl.Value := where = "target" ? "Click Change… to choose it." : "Add a modifier, e.g. Right Ctrl."
        SetColor(ctl, th.warn)
    } else {
        ctl.Value := normal
        SetColor(ctl, dim ? th.dim : th.sub)
    }
}

KeyCode(vk, sc) => vk ? Format("Code: VK {:X} · SC {:X}", vk, sc) : "Not set yet"

SetKeyView(name, wd, mods, vk, sc, anySide, listen, dim := false) {
    UI.keyText[name] := listen ? "listening" : vk ? ComboLabel(mods, vk, sc, anySide) : "Not set"
    wd.Update({parts: vk ? ComboParts(mods, vk, sc, anySide) : [], listen: listen, _enabled: !dim})
}

; Sets a switch; a change of state slides the knob (not on the first draw)
SetSwitch(name, on, dim := false) {
    wd := UI.tg[name], on := on ? 1 : 0
    UI.tgState[name] := on
    slide := wd.on != "" && on != wd.on
    wd.on := on, wd._enabled := !dim
    if dim
        wd.hover := false, wd.press := false
    if slide
        Animate(wd, on)
    else {
        if !UI.anims.Has(wd)
            wd.pos := on
        wd.Draw()
    }
}

ChoiceIndex(list, value) {
    for i, item in list
        if (item = value)
            return i
    return 1
}

UpdateApp() {
    if !UI.gui
        return
    p := DRAFT.launchPath, th := UI.th, color := th.sub
    if (p = "auto") {
        name := NS.label != "" ? NS.label : "NitroSense"
        if !NS.checked
            status := "Looking for it…"
        else if (NS.target != "") {
            SplitPath(NS.target, &file)
            status := SubStr(NS.target, 1, 6) = "shell:" ? "found automatically" : "found automatically (" file ")"
            color := th.ok
        } else
            status := "not found: click Browse…", color := th.warn
        status := name ", " status
    } else if (SubStr(p, 1, 6) = "shell:") {
        status := "An app from the Apps folder (chosen by you)"
    } else {
        SplitPath(p, &file)
        if FileExist(p)
            status := file " (chosen by you)"
        else
            status := file ": file not found, click Browse…", color := th.warn
    }
    UI.appStatus.Value := status
    SetColor(UI.appStatus, DRAFT.launchEnabled ? color : th.dim)
}

UpdateUpdatesRow() {
    if !UI.gui
        return
    th := UI.th, color := th.sub, variant := ""
    switch UPD.state {
        case "checking":
            btn := "Checking…", text := "Looking for a new version…"
        case "available":
            btn := (A_IsCompiled ? "Install " : "Download ") UPD.latest
            text := "A new version is available", color := th.ok, variant := "accent"
        case "latest":
            btn := "Check now", text := "You're up to date"
        case "error":
            btn := "Check now", text := "Couldn't check. Try again later.", color := th.warn
        default:
            btn := "Check now", text := "Not checked yet"
    }
    UI.updBtn.Update({_text: btn, variant: variant, _enabled: UPD.state != "checking"})
    UI.updText.Value := text
    SetColor(UI.updText, color)
}

DetectForApp() {
    DetectNitroSense()
    UpdateApp()
}

; ---- Window -> settings ----------------------------------------------------------

OnModeChange(ctl, *) {
    DRAFT.mode := MODES[ctl.Value]
    if (CAP.active && CAP.target = "target" && DRAFT.mode != "Key")
        CaptureCancel()
    CommitDraft("Action: " MODE_LABELS[ctl.Value])
}

OnThemeChange(ctl, *) {
    DRAFT.theme := THEME_PREFS[ctl.Value]
    CommitDraft("Theme: " THEME_PREFS[ctl.Value])
}

AutoApp(*) {
    DRAFT.launchPath := "auto"
    if !NS.checked
        SetTimer(DetectForApp, -1)
    CommitDraft("App to open: found automatically")
}

BrowseApp(*) {
    old := PMv2()                           ; a sharp dialog on any monitor (see Dialog)
    UI.gui.Opt("+OwnDialogs")
    file := FileSelect(35, , "Choose the app to open", "Programs (*.exe; *.lnk)")   ; 1+2+32: must exist, keep .lnk
    PMv2(old)
    if (file != "") {
        DRAFT.launchPath := file
        SplitPath(file, &name)
        CommitDraft("App to open: " name)
    }
}

ResetSettings(*) {
    global DRAFT
    if (Dialog("Put every option back to its default value?", "YesNo Icon?") != "Yes")
        return
    CaptureCancel()
    DRAFT := DefaultSettings()
    CommitDraft("All settings are back to their defaults")
}

; A message box that's sharp on any monitor: created Per-Monitor DPI aware
; (a system-aware one is stretched by Windows, so blurry) and, with the
; settings window open, owned by it
Dialog(text, opts) {
    old := PMv2()
    if UI.gui
        UI.gui.Opt("+OwnDialogs")
    answer := MsgBox(text, APP.short, opts)
    PMv2(old)
    return answer
}

; Shows a notification with the style chosen in the window
PreviewToast(*) {
    saved := [GTCFG.position, GTCFG.animation, GTCFG.glass]
    GTCFG.position := DRAFT.toastPosition, GTCFG.animation := DRAFT.toastAnim, GTCFG.glass := DRAFT.toastGlass
    try ShowToast("This is how notifications look"
                , TOAST_POSITION_LABELS[ChoiceIndex(TOAST_POSITIONS, DRAFT.toastPosition)] " · "
                . TOAST_ANIM_LABELS[ChoiceIndex(TOAST_ANIMS, DRAFT.toastAnim)] " · "
                . (DRAFT.toastGlass ? "Glass" : "Solid"), "ok", 3000)
    GTCFG.position := saved[1], GTCFG.animation := saved[2], GTCFG.glass := saved[3]
}

; Blocking problems only; where = the row that must show it
ValidateSettings(d, &where := "") {
    where := ""
    if (d.mode != "None" && !d.sourceVK)
        return (where := "source", "Choose the key to remap first: click Change… next to Key.")
    if (d.mode = "Key" && !d.targetVK)
        return (where := "target", "Choose the key or shortcut to send: click Change… next to Sends.")
    if d.launchEnabled {
        if !d.launchVK
            return (where := "launch", "Choose the shortcut that opens NitroSense, or turn it off.")
        if (!d.launchMods.Length && d.mode != "None" && SameKey(d.launchVK, d.launchSC, d.sourceVK, d.sourceSC))
            return (where := "launch", "The shortcut to open NitroSense is the key you are remapping, so the remap would never run. Add a modifier, for example Right Ctrl.")
    }
    return ""
}

SameKey(vk1, sc1, vk2, sc2) => vk1 = vk2 && (!sc1 || !sc2 || sc1 = sc2)

CloseSettings(*) {
    CaptureCancel()
    DestroySettings()
}

DestroySettings() {
    if !UI.gui
        return
    Log("Settings window closed")
    ToolTip()
    for fn in [CheckInfoTip, CheckHot, AnimTick, ApplyPendingDpi]
        SetTimer(fn, 0)
    FreeDpiShot()
    UI.pendingDpi := 0
    DllCall("ReleaseCapture")
    NoticeFree()
    g := UI.gui
    UI.gui := 0, UI.hot := 0
    for hwnd, wd in UI.widgets
        wd.Free()
    UI.widgets := Map(), UI.anims := Map()
    g.Destroy()
    for handle in [UI.brushCard, UI.bgBmp]
        if handle
            DllCall("DeleteObject", "ptr", handle)
    UI.bgBmp := 0
    if UI.cardIcon
        DllCall("DestroyIcon", "ptr", UI.cardIcon), UI.cardIcon := 0
    for name, fam in UI.fam
        if fam
            DllCall("gdiplus\GdipDeleteFontFamily", "ptr", fam)
    UI.fam := Map()
    if UI.tok
        DllCall("gdiplus\GdiplusShutdown", "ptr", UI.tok), UI.tok := 0
}

; Rebuilds the window (theme change) at the same place and section
RebuildSettings() {
    if !UI.gui
        return
    old := PMv2()
    WinGetPos(&wx, &wy, , , UI.gui.Hwnd)
    PMv2(old)
    page := UI.page
    CaptureCancel()
    DestroySettings()
    BuildSettings(page, wx, wy)
}

; ---- Theme -----------------------------------------------------------------

; "light" or "dark": the user's choice, or Windows' app mode for "System"
ThemeName(pref) {
    if (pref = "Light" || pref = "Dark")
        return StrLower(pref)
    try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") ? "light" : "dark"
    return "light"
}

; Dark or light context menus (tray menu) for this process. Undocumented
; uxtheme exports, available since Windows 10 1809; silently skipped before.
ApplyAppTheme(pref) {
    try {
        DllCall(UxOrdinal(135), "int", pref = "Dark" ? 2 : pref = "Light" ? 3 : 1)   ; SetPreferredAppMode
        DllCall(UxOrdinal(136))                                                        ; FlushMenuThemes
    }
}

UxOrdinal(n) {
    static ux := DllCall("LoadLibrary", "str", "uxtheme", "ptr")
    return DllCall("GetProcAddress", "ptr", ux, "ptr", n, "ptr")
}

ThemeCtl(ctl) {                         ; drop-down lists in dark mode
    dark := UI.th.dark
    try DllCall(UxOrdinal(133), "ptr", ctl.Hwnd, "int", dark)                      ; AllowDarkModeForWindow
    DllCall("uxtheme\SetWindowTheme", "ptr", ctl.Hwnd, "str", dark ? "DarkMode_CFD" : "Explorer", "ptr", 0)
}

ThemeTitleBar(hwnd) {
    static dwm := DllCall("LoadLibrary", "str", "dwmapi", "ptr")
    v := Buffer(4)
    NumPut("int", UI.th.dark ? 1 : 0, v)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 20, "ptr", v, "uint", 4)   ; dark title bar
    NumPut("uint", Bgr(UI.th.win), v)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", 35, "ptr", v, "uint", 4)   ; caption color (Windows 11)
}

; Windows switched between light and dark
OnSettingChange(wParam, lParam, msg, hwnd) {
    if (hwnd != A_ScriptHwnd || !lParam)
        return
    try {
        if (StrGet(lParam) != "ImmersiveColorSet")
            return
    } catch
        return
    ApplyAppTheme(CFG.theme)
    if (UI.gui && ThemeName(DRAFT.theme) != UI.themeName)
        SetTimer(RebuildSettings, -300)
}

OnSettingsErase(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd || !UI.bgBmp)
        return
    if UI.dpiShot {                         ; moving to another monitor: the scaled picture
        rc := Buffer(16)
        DllCall("GetClientRect", "ptr", hwnd, "ptr", rc)
        DllCall("SetStretchBltMode", "ptr", wParam, "int", 3)                     ; COLORONCOLOR: fast, fine for a moment
        DllCall("StretchBlt", "ptr", wParam, "int", 0, "int", 0, "int", NumGet(rc, 8, "int"), "int", NumGet(rc, 12, "int")
              , "ptr", UI.shotDC, "int", 0, "int", 0, "int", UI.shotW, "int", UI.shotH, "uint", 0x00CC0020)
        return 1
    }
    hdc := DllCall("CreateCompatibleDC", "ptr", wParam, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", UI.bgBmp, "ptr")
    DllCall("BitBlt", "ptr", wParam, "int", 0, "int", 0, "int", UI.bgW, "int", UI.bgH
          , "ptr", hdc, "int", 0, "int", 0, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteDC", "ptr", hdc)
    return 1
}

OnSettingsCtlColorList(wParam, lParam, msg, hwnd) {
    if (!UI.gui || hwnd != UI.gui.Hwnd || !UI.th.dark)
        return
    DllCall("SetTextColor", "ptr", wParam, "uint", Bgr(UI.th.text))
    DllCall("SetBkColor", "ptr", wParam, "uint", Bgr(UI.th.card))
    return UI.brushCard
}

; ---- Drawing (GDI+, reusing the toast library's helpers) --------------------

Argb(rgb, alpha := 0xFF) => (alpha << 24) | rgb
Bgr(rgb) => ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
Hex6(rgb) => Format("{:06X}", rgb)

GdipStart() {
    DllCall("LoadLibrary", "str", "gdiplus", "ptr")
    si := Buffer(24, 0), tok := 0
    NumPut("uint", 1, si)
    DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", si, "ptr", 0)
    return tok
}

FontFamily(name) {                      ; GDI+ font family (0 if missing), kept while the window is open
    if !UI.fam.Has(name)
        UI.fam[name] := GT_Family(name)
    return UI.fam[name]
}

Canvas(wL, hL, bg) {
    w := Round(wL * UI.k), h := Round(hL * UI.k), g := 0
    bmp := GT_Bitmap(w, h)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", bmp, "ptr*", &g)
    GT_Quality(g)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 5)     ; ClearType: the background is opaque
    DllCall("gdiplus\GdipGraphicsClear", "ptr", g, "uint", Argb(bg))
    return {bmp: bmp, g: g, w: w, h: h}
}

; Turns the canvas into an HBITMAP; dim fades it towards the background
CanvasDone(cv, bg, dim := false) {
    if dim {
        brush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", Argb(bg, 0xA8), "ptr*", &brush)
        DllCall("gdiplus\GdipFillRectangle", "ptr", cv.g, "ptr", brush, "float", 0, "float", 0, "float", cv.w, "float", cv.h)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    }
    hbm := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", cv.bmp, "ptr*", &hbm, "uint", Argb(bg))
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", cv.g)
    DllCall("gdiplus\GdipDisposeImage", "ptr", cv.bmp)
    return hbm
}

NewFormat(align) {                      ; 0 left, 1 center, 2 right; vertically centered, no wrap
    fmt := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0x1000, "int", 0, "ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", 1)
    return fmt
}

FreeAll(fonts, formats := "") {
    for f in fonts
        if f
            DllCall("gdiplus\GdipDeleteFont", "ptr", f)
    if IsObject(formats)
        for fmt in formats
            DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
}

FillPathFree(g, p, argb) {
    GT_FillPath(g, p, argb)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

StrokePathFree(g, p, argb, width) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", width, "int", 2, "ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", p)
    DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

FillCircle(g, x, y, d, argb) {
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &brush)
    DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", brush, "float", x, "float", y, "float", d, "float", d)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
}

; Window background: the rounded card groups (with row dividers) on the window color
RenderBackground(wL, hL, groups) {
    th := UI.th, k := UI.k
    cv := Canvas(wL, hL, th.win)
    for c in groups {
        x := Round(c.x * k), y := Round(c.y * k), cw := Round(c.w * k), ch := Round(c.h * k)
        FillPathFree(cv.g, GT_RoundPath(x, y, cw, ch, 8 * k), Argb(th.card))
        StrokePathFree(cv.g, GT_RoundPath(x + 0.5, y + 0.5, cw - 1, ch - 1, 8 * k), Argb(th.border), 1)
        for dy in c.dividers {
            pen := 0, ly := y + Round(dy * k) + 0.5
            DllCall("gdiplus\GdipCreatePen1", "uint", Argb(th.border), "float", 1, "int", 2, "ptr*", &pen)
            DllCall("gdiplus\GdipDrawLine", "ptr", cv.g, "ptr", pen, "float", x + 1, "float", ly, "float", x + cw - 1, "float", ly)
            DllCall("gdiplus\GdipDeletePen", "ptr", pen)
        }
    }
    return CanvasDone(cv, th.win)
}

RenderWidget(wd) {
    switch wd.kind {
        case "button": return RenderButton(wd)
        case "switch": return RenderSwitch(wd)
        case "nav":    return RenderNav(wd)
        case "link":   return RenderLink(wd)
        case "card":   return RenderAboutCard(wd)
        default:       return RenderKeys(wd)
    }
}

; A button with a "lip" (a darker edge under it), a bit retro: pressed, the
; face goes down onto the lip. Danger buttons are red text and turn red on
; hover, like GitHub's danger zone; accent ones are green.
RenderButton(wd) {
    th := UI.th, k := UI.k, v := wd.variant, on := wd._enabled, hot := on && wd.hover
    cv := Canvas(wd.lw, wd.lh, th.card), g := cv.g
    lip := Round(2 * k), fh := cv.h - lip, down := hot && wd.press ? lip : 0
    edge := th.btnEdge, lipColor := th.btnLip, face := hot ? th.btnHover : th.btnFace
    fg := !on ? th.dim : v = "danger" ? th.danger : th.text
    if (v = "danger" && hot)
        face := th.dangerFill, lipColor := th.dangerLip, fg := th.onDanger, edge := 0
    else if (v = "accent" && on)
        face := hot ? GT_Lerp(th.accent, th.dark ? 0xFFFFFF : 0x000000, 0.1) : th.accent
      , lipColor := th.accentLip, fg := th.onAccent, edge := 0
    if !on
        lipColor := th.btnEdge
    rad := 6 * k
    if !down
        FillPathFree(g, GT_RoundPath(0, lip, cv.w, fh, rad), Argb(lipColor))
    FillPathFree(g, GT_RoundPath(0, down, cv.w, fh, rad), Argb(face))
    if edge
        StrokePathFree(g, GT_RoundPath(0.5, down + 0.5, cv.w - 1, fh - 1, rad), Argb(edge), 1)
    font := GT_Font(FontFamily("Segoe UI"), 13.33 * k, 0), fmt := NewFormat(1)
    GT_Text(g, wd._text, font, Argb(fg), 0, down, cv.w, fh, fmt)
    FreeAll([font], [fmt])
    return CanvasDone(cv, th.card)
}

; Windows 11 style on/off switch. pos: 0 = off, 1 = on, in between (and a bit
; beyond, the overshoot) while it slides. The knob grows on hover and
; stretches while pressed.
RenderSwitch(wd) {
    th := UI.th, k := UI.k, p := wd.pos, on := wd._enabled
    q := Max(0, Min(1, p))                  ; colors don't overshoot
    cv := Canvas(40, 20, th.card), g := cv.g
    inset := k, ht := cv.h - 2 * inset, tw := cv.w - 2 * inset
    if (q < 1)
        StrokePathFree(g, GT_RoundPath(inset, inset, tw, ht, ht / 2), Argb(th.off, Round(255 * (1 - q))), 1.2 * k)
    if (q > 0)
        FillPathFree(g, GT_RoundPath(inset, inset, tw, ht, ht / 2), Argb(th.on, Round(255 * q)))
    d := (10 + 2 * q + (on && wd.hover ? 1.5 : 0)) * k
    kw := d + (on && wd.press && wd.hover ? 5 * k : 0)
    cx := (10 + 19 * p) * k
    x := p < 0.5 ? cx - d / 2 : cx + d / 2 - kw     ; stretches towards the middle
    FillPathFree(g, GT_RoundPath(x, (cv.h - d) / 2, kw, d, d / 2), Argb(GT_Lerp(th.knobOff, th.knobOn, q)))
    return CanvasDone(cv, th.card, !on)
}

; A sidebar entry: icon glyph and label. Hover and pressed get a pill; the
; selected one too, with an accent bar that grows in (pos).
RenderNav(wd) {
    th := UI.th, k := UI.k, sel := wd.page = UI.page
    cv := Canvas(wd.lw, wd.lh, th.win), g := cv.g
    pill := wd.press && wd.hover ? th.navPress : sel ? th.navSel : wd.hover ? th.navHover : 0
    if pill
        FillPathFree(g, GT_RoundPath(0, 0, cv.w, cv.h, 5 * k), Argb(pill))
    if (sel && (bh := 16 * k * Max(0, wd.pos)) >= 1)
        FillPathFree(g, GT_RoundPath(0, (cv.h - bh) / 2, 3 * k, bh, 1.5 * k), Argb(th.accent))
    fmt := NewFormat(0)
    fi := FontFamily(UI.iconFont) ? GT_Font(FontFamily(UI.iconFont), 15 * k, 0) : 0
    if fi
        GT_Text(g, Chr(wd.glyph), fi, Argb(th.text), 14 * k, 0, 24 * k, cv.h, fmt)
    ft := GT_Font(FontFamily("Segoe UI"), 13.5 * k, sel ? 1 : 0)
    GT_Text(g, wd.label, ft, Argb(th.text), 46 * k, 0, cv.w - 50 * k, cv.h, fmt)
    FreeAll([fi, ft], [fmt])
    return CanvasDone(cv, th.win)
}

; A clickable row on a card (About > Help and feedback): glyph, label, ↗
RenderLink(wd) {
    th := UI.th, k := UI.k
    cv := Canvas(wd.lw, wd.lh, th.card), g := cv.g
    if wd.hover
        FillPathFree(g, GT_RoundPath(0, 0, cv.w, cv.h, 4 * k), Argb(wd.press ? th.rowPress : th.rowHover))
    fmt := NewFormat(0), famI := FontFamily(UI.iconFont)
    fi := famI ? GT_Font(famI, 16 * k, 0) : 0, fs := famI ? GT_Font(famI, 12 * k, 0) : 0
    ft := GT_Font(FontFamily("Segoe UI"), 14 * k, 0)
    if famI {
        GT_Text(g, Chr(wd.glyph), fi, Argb(th.text), 12 * k, 0, 24 * k, cv.h, fmt)
        GT_Text(g, Chr(0xE8A7), fs, Argb(wd.hover ? th.text : th.sub), cv.w - 32 * k, 0, 20 * k, cv.h, fmt)
    }
    GT_Text(g, wd.label, ft, Argb(th.text), 44 * k, 0, cv.w - 90 * k, cv.h, fmt)
    FreeAll([fi, fs, ft], [fmt])
    return CanvasDone(cv, th.card)
}

; About: the app card, a link to the project page
RenderAboutCard(wd) {
    th := UI.th, k := UI.k
    cv := Canvas(wd.lw, wd.lh, th.win), g := cv.g
    fill := wd.press && wd.hover ? th.rowPress : wd.hover ? th.rowHover : th.card
    FillPathFree(g, GT_RoundPath(0, 0, cv.w, cv.h, 8 * k), Argb(fill))
    StrokePathFree(g, GT_RoundPath(0.5, 0.5, cv.w - 1, cv.h - 1, 8 * k), Argb(th.border), 1)
    famSB := FontFamily("Segoe UI Semibold"), famR := FontFamily("Segoe UI"), famI := FontFamily(UI.iconFont)
    fmt := NewFormat(0)
    fTitle := GT_Font(famSB ? famSB : famR, 18.67 * k, famSB ? 0 : 1)
    fSub := GT_Font(famR, 12 * k, 0)
    fLink := GT_Font(famR, 12 * k, wd.hover ? 4 : 0)           ; underlined on hover
    fi := famI ? GT_Font(famI, 12 * k, 0) : 0
    link := wd.hover ? th.accent : th.sub
    GT_Text(g, APP.name, fTitle, Argb(th.text), 84 * k, 14 * k, cv.w - 140 * k, 28 * k, fmt)
    GT_Text(g, "Version " APP.version " · MIT License · Remaps the NitroSense key, or any other key."
          , fSub, Argb(th.sub), 84 * k, 44 * k, cv.w - 100 * k, 18 * k, fmt)
    GT_Text(g, RegExReplace(APP.repo, "^https://"), fLink, Argb(link), 84 * k, 68 * k, cv.w - 140 * k, 18 * k, fmt)
    if fi                                                       ; "opens in the browser"
        GT_Text(g, Chr(0xE8A7), fi, Argb(link), cv.w - 32 * k, 12 * k, 20 * k, 20 * k, fmt)
    FreeAll([fTitle, fSub, fLink, fi], [fmt])
    hbm := CanvasDone(cv, th.win)
    DrawAppIcon(hbm, Round(20 * k), Round((cv.h - 48 * k) / 2), Round(48 * k))
    return hbm
}

DrawAppIcon(hbm, x, y, size) {          ; DrawIconEx keeps the icon's alpha (GDI+ wouldn't)
    if (!UI.cardIcon || UI.cardIconSize != size) {
        if UI.cardIcon
            DllCall("DestroyIcon", "ptr", UI.cardIcon), UI.cardIcon := 0
        UI.cardIconSize := size
        file := A_IsCompiled ? A_ScriptFullPath : IconPath()
        if (A_IsCompiled || FileExist(file)) {
            imgType := 0
            try UI.cardIcon := LoadPicture(file, (A_IsCompiled ? "Icon1 " : "") "w" size " h" size, &imgType)
            if (UI.cardIcon && imgType != 1)
                DllCall("DeleteObject", "ptr", UI.cardIcon), UI.cardIcon := 0
        }
    }
    if !UI.cardIcon
        return
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    DllCall("DrawIconEx", "ptr", hdc, "int", x, "int", y, "ptr", UI.cardIcon, "int", size, "int", size, "uint", 0, "ptr", 0, "uint", 3)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteDC", "ptr", hdc)
}

; A key or shortcut as keycaps. Hover darkens their edge; pressed, they go down.
RenderKeys(wd) {
    th := UI.th, k := UI.k, parts := wd.parts, dim := !wd._enabled
    cv := Canvas(wd.lw, wd.lh, th.card), g := cv.g
    famR := FontFamily("Segoe UI"), famSB := FontFamily("Segoe UI Semibold")
    fam := famSB ? famSB : famR
    fmtL := NewFormat(0), fmtC := NewFormat(1)
    font := 0, avail := cv.w
    capH := Round(26 * k), y0 := Round((cv.h - capH) / 2 - k), rad := 6 * k
    down := !dim && wd.press && wd.hover ? 2 * k : 0
    edge := !dim && wd.hover ? th.sub : th.keyEdge
    if wd.listen {
        font := GT_Font(fam, 12.5 * k, 0), text := "Press a key or shortcut…"
        cw := Min(avail - 2 * k, GT_MeasureW(g, text, font, fmtL) + 26 * k)
        FillPathFree(g, GT_RoundPath(k, y0, cw, capH + 2 * k, rad), Argb(th.accent, 0x24))
        StrokePathFree(g, GT_RoundPath(k, y0, cw, capH + 2 * k, rad), Argb(th.accent), 1.5 * k)
        GT_Text(g, text, font, Argb(th.accent), k, y0, cw, capH + 2 * k, fmtC)
    } else if !parts.Length {
        font := GT_Font(famR, 13 * k, 0)
        GT_Text(g, "Not set: click Change…", font, Argb(th.sub), 0, 0, avail, cv.h, fmtL)
    } else {
        size := 13
        loop {                              ; shrink the text if the shortcut is long
            font := GT_Font(fam, size * k, 0)
            plusW := GT_MeasureW(g, "+", font, fmtL) + 12 * k, total := 0
            for i, part in parts
                total += GT_MeasureW(g, part, font, fmtL) + 20 * k + (i > 1 ? plusW : 0)
            if (total <= avail || size <= 10)
                break
            DllCall("gdiplus\GdipDeleteFont", "ptr", font)
            size -= 1
        }
        x := k
        for i, part in parts {
            if (i > 1) {
                GT_Text(g, "+", font, Argb(th.sub), x, 0, plusW, cv.h, fmtC)
                x += plusW
            }
            capW := GT_MeasureW(g, part, font, fmtL) + 20 * k
            FillPathFree(g, GT_RoundPath(x, y0 + 2 * k, capW, capH, rad), Argb(th.keyShade))
            FillPathFree(g, GT_RoundPath(x, y0 + down, capW, capH, rad), Argb(th.keyFace))
            StrokePathFree(g, GT_RoundPath(x + 0.5, y0 + down + 0.5, capW - 1, capH - 1, rad), Argb(edge), 1)
            GT_Text(g, part, font, Argb(th.keyText), x, y0 + down, capW, capH, fmtC)
            x += capW
        }
    }
    FreeAll([font], [fmtL, fmtC])
    return CanvasDone(cv, th.card, dim)
}
