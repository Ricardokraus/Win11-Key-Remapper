; ============================================================================
; Logic tests for Win11KeyRemapper.ahk - NOT a standalone script.
; tests\run-tests.ps1 appends this file to a patched copy of the app (no
; startup, no hook, side effects replaced by the Test* stubs below) and runs
; it. Fake key events are passed straight to KeyboardProc.
; ============================================================================
Critical                                ; no timer may run in the middle of a test
; A runtime error must fail the run, not open a dialog and wait
OnError((e, *) => (FileAppend("ERROR: " e.Message " (line " e.Line ")`n" e.Stack "`n", "*", "UTF-8"), ExitApp(2)))
TOASTS := [], SENT := [], RAN := []
TestToast(title, sub, kind := "ok", holdMs := 5000) {
    TOASTS.Push(title " | " sub)        ; system notifications; NT.last = the last notice in the window
}
TestSend(keys) => SENT.Push(keys)
TestRun(target, dir := "", opts := "") => RAN.Push(target)
LastToast() => TOASTS.Length ? TOASTS[TOASTS.Length] : ""
PASSES := 0, FAILS := 0
Check(cond, label) {
    global PASSES, FAILS
    if cond
        PASSES++
    else {
        FAILS++
        FileAppend("FAIL: " label "`n", "*", "UTF-8")
    }
}
Eq(a, b, label) => Check(a == b, label "  got [" a "] expected [" b "]")
Note(text) => FileAppend("note: " text "`n", "*", "UTF-8")

KEV := Buffer(24, 0)
Ev(vk, sc, up := false, injected := false) {
    flags := ((sc & 0x100) ? 1 : 0) | (up ? 0x80 : 0) | (injected ? 0x10 : 0)
    NumPut("uint", vk, KEV, 0), NumPut("uint", sc & ~0x100, KEV, 4), NumPut("uint", flags, KEV, 8)
    return KeyboardProc(0, up ? 0x101 : 0x100, KEV.Ptr)
}
TakeQueue() {
    out := ""
    for a in QUEUE
        out .= a.do (a.HasOwnProp("key") ? ":" a.key : "") (a.HasOwnProp("keys") ? ":" a.keys : "") ";"
    QUEUE.Length := 0
    return out
}
Reset(c) {
    global CFG, PAUSED
    CFG := c, PAUSED := false
    ApplySettings()
    HELD.Clear(), PRESS.Clear(), SWALLOW.Clear(), QUEUE.Length := 0
}

tmp := A_Temp "\kr-test-" A_TickCount
DirCreate(tmp)
SETTINGS_PATH := tmp "\settings.ini"
APP.lnk := tmp "\Windows 11 Key Remapper.lnk"

; ---- 1. Settings file ----
CFG := DefaultSettings()
WriteSettings(SETTINGS_PATH, CFG)
c := LoadSettings(SETTINGS_PATH)
Eq(c.sourceVK, 0xFF, "default SourceVK")
Eq(c.sourceSC, 0x175, "default SourceSC")
Eq(c.matchSC, 1, "default MatchSC")
Eq(c.mode " " c.targetVK " " c.targetSC, "Key 144 325", "default: press Num Lock")
Eq(c.targetMods.Length, 0, "default TargetMods empty")
Eq(JoinMods(c.launchMods), "RCtrl", "default LaunchMods")
Eq(c.launchVK, 0xFF, "default LaunchVK")
Eq(c.launchPath, "auto", "default LaunchPath")
Eq(c.toastWhen, "Always", "default ToastWhen")
f := FileOpen(SETTINGS_PATH, "r"), enc := f.Encoding, f.Close()
Eq(enc, "UTF-16", "ini encoding")
txt := FileRead(SETTINGS_PATH, "UTF-16")
Check(InStr(txt, "; Windows 11 Key Remapper - settings`r`n"), "header with CRLF")
Check(InStr(txt, "SourceVK=0xFF") && InStr(txt, "TargetMods=`r`n"), "hex + empty values written")
Check(!InStr(txt, "{") && !InStr(txt, "`n`n"), "every placeholder filled, CRLF only")
Check(InStr(txt, "; What the key does:`r`n;   Key     = press another key") && InStr(txt, "`r`n; Where it appears:"), "settings.ini explains each key")
Check(SettingsExplained(SETTINGS_PATH), "explained file recognized")
Check(!FileExist(SETTINGS_PATH ".tmp"), "no temporary file left")
pOld := tmp "\old-format.ini"
FileAppend("; Windows 11 Key Remapper - settings`r`n[Remap]`r`nSourceVK=0xFF`r`n", pOld, "UTF-16")
Check(!SettingsExplained(pOld) && !SettingsExplained(tmp "\missing.ini"), "old or missing file needs rewriting")

IniWrite("", SETTINGS_PATH, "Launcher", "LaunchMods")
Eq(LoadSettings(SETTINGS_PATH).launchMods.Length, 0, "empty LaunchMods stays empty")
IniDelete(SETTINGS_PATH, "Launcher", "LaunchMods")
Eq(JoinMods(LoadSettings(SETTINGS_PATH).launchMods), "RCtrl", "missing LaunchMods -> default")

p2 := tmp "\roadmap.ini"
FileAppend("[Remap]`r`nSourceVK=0x41          `; key to remap`r`nSourceSC=0x1E`r`nMatchSC=0`r`nMode=key  `; lower case`r`nTargetMods=lctrl, Shift`r`nTargetVK=0x43`r`nTargetSC=junk`r`n[Launcher]`r`nLaunchEnabled=0`r`nLaunchPath=`r`n[General]`r`nToastWhen=never`r`nTheme=dark`r`nToastPosition=bottomright`r`nToastAnimation=Spin`r`nTrayIcon=0`r`n", p2)
c := LoadSettings(p2)
Eq(c.sourceVK, 0x41, "inline comment stripped")
Eq(c.matchSC, 0, "MatchSC=0")
Eq(c.mode, "Key", "mode case-insensitive")
Eq(JoinMods(c.targetMods), "LCtrl,LShift", "mods parsed + aliases")
Eq(c.targetSC, 0x145, "invalid hex -> default")
Eq(c.launchEnabled, 0, "LaunchEnabled=0")
Eq(c.launchPath, "auto", "empty LaunchPath -> auto")
Eq(c.launchVK, 0xFF, "missing LaunchVK -> default")
Eq(c.toastWhen, "Never", "ToastWhen=never")
Eq(c.theme, "Dark", "Theme normalized")
Eq(c.toastPosition " " c.toastAnim " " c.trayIcon " " c.checkUpdates, "BottomRight Slide 0 1", "toast/tray/update settings")
Eq(LoadSettings(SETTINGS_PATH).theme, "System", "default Theme")
p3 := tmp "\legacy.ini"
FileAppend("[Remap]`r`nMode=CapsLock`r`nTargetMods=LCtrl`r`nTargetVK=0x41`r`n", p3)
c := LoadSettings(p3)
Eq(c.mode " " Hex(c.targetVK) " " Hex(c.targetSC) " " c.targetMods.Length, "Key 0x14 0x3A 0", "old Mode=CapsLock -> press Caps Lock")
c := DefaultSettings(), c.toastGlass := false
Check(DefaultSettings().toastGlass, "notifications: glass by default")
WriteSettings(SETTINGS_PATH, c)
Eq(LoadSettings(SETTINGS_PATH).toastGlass, 0, "ToastTransparency=0 round trip")

c := LoadSettings(A_ScriptDir "\..\settings.example.ini"), d := DefaultSettings()
for key in ["sourceVK", "sourceSC", "matchSC", "mode", "targetVK", "targetSC", "launchEnabled"
          , "launchVK", "launchSC", "launchAnySide", "launchPath", "toastWhen", "toastPosition"
          , "toastAnim", "toastGlass", "trayIcon", "checkUpdates", "theme"]
    Eq(c.%key% "", d.%key% "", "settings.example.ini matches defaults: " key)
Eq(JoinMods(c.targetMods) "|" JoinMods(c.launchMods), JoinMods(d.targetMods) "|" JoinMods(d.launchMods), "settings.example.ini mods")
example := FileRead(A_ScriptDir "\..\settings.example.ini", "UTF-8")
Check(InStr(example, "`r`n; Windows 11 Key Remapper - settings")
    && SubStr(example, InStr(example, "; Windows 11 Key Remapper - settings")) == SettingsText(d)
    , "settings.example.ini = what the app writes with the defaults")

; ---- 2. Labels ----
Eq(FieldText(0xFF, 0x175, ["RCtrl"]), "Right Ctrl + NitroSense key · VK FF SC 175", "field text")
Eq(FieldText(0, 0), "Not set", "field not set")
Eq(KeyLabel(0x41, 0x1E), "A", "letter")
Eq(KeyLabel(0x90, 0x145), "Num Lock", "numlock")
Eq(KeyLabel(0x14, 0x3A), "Caps Lock", "capslock")
Eq(KeyLabel(0x60, 0x52), "Numpad 0", "numpad0")
Eq(KeyLabel(0xB3, 0x122), "Media Play Pause", "media")
Eq(KeyLabel(0x7B, 0x58), "F12", "F12")
Eq(KeyLabel(0xFF, 0x159), "Win Lock on", "win lock")
Eq(KeyLabel(0xFF, 0x1AB), "Special key (SC 1AB)", "unknown vendor key")
Eq(KeyLabel(0xA3, 0x11D), "Right Ctrl", "right ctrl")
Eq(ComboLabel(["LCtrl", "RCtrl"], 0xFF, 0x175, true), "Ctrl + NitroSense key", "any side dedupe")
Eq(Summary(DefaultSettings()), "NitroSense key → Num Lock", "summary")

; ---- 2b. Toast placement, updates ----
; work area 0,0-1000,700; window 300x100 with a 20 px shadow pad; 10 px from the edges
P(pos, anim) {
    r := GT_Placement(0, 0, 1000, 700, 300, 100, 20, 10, pos, anim)
    return r.xVis "," r.yVis " " r.xHid "," r.yHid
}
Eq(P("TopCenter", "Slide"), "350,-10 350,-100", "toast top center slides from the top")
Eq(P("TopRight", "Slide"), "710,-10 1000,-10", "toast top right slides from the right")
Eq(P("TopLeft", "Slide"), "-10,-10 -300,-10", "toast top left slides from the left")
Eq(P("BottomCenter", "Slide"), "350,610 350,655", "toast bottom center rises")
Eq(P("BottomRight", "Fade"), "710,610 710,610", "toast fade stays in place")
Eq(P("BottomLeft", "None"), "-10,610 -10,610", "toast none stays in place")
c := DefaultSettings(), c.toastPosition := "BottomLeft", c.toastAnim := "Fade"
Reset(c)
Eq(GTCFG.position " " GTCFG.animation, "BottomLeft Fade", "toast style applied")
c := DefaultSettings(), c.toastGlass := false, c.theme := "Dark"
Reset(c)
Check(!GTCFG.glass && GTCFG.solidTheme = "dark" && !GT_SolidLight(), "solid notification in the app's dark colors")
c.theme := "System"
Reset(c)
Eq(GTCFG.solidTheme, "", "solid notification follows Windows with Theme=System")
Reset(DefaultSettings())

Check(VersionNewer("v0.3.0", "0.2.0") && VersionNewer("v1.0.0", "0.9.9") && VersionNewer("0.2.10", "0.2.9"), "newer versions")
Check(!VersionNewer("v0.2.0", "0.2.0") && !VersionNewer("v0.1.9", "0.2.0") && !VersionNewer("garbage", "0.2.0"), "not newer")
rel := ParseRelease('{"url":"x","html_url":"https://github.com/o/r/releases/tag/v0.3.0","tag_name":"v0.3.0","author":{"html_url":"https://github.com/o"},'
    . '"assets":[{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/o/r/releases/download/v0.3.0/SHA256SUMS.txt"},'
    . '{"name":"Win11KeyRemapper-v0.3.0.zip","browser_download_url":"https://github.com/o/r/releases/download/v0.3.0/Win11KeyRemapper-v0.3.0.zip"}]}')
Eq(rel.tag, "v0.3.0", "release tag")
Eq(rel.page, "https://github.com/o/r/releases/tag/v0.3.0", "release page")
Check(InStr(rel.zip, "/Win11KeyRemapper-v0.3.0.zip") && InStr(rel.sums, "/SHA256SUMS.txt"), "release assets")
FileAppend("abc", tmp "\abc.txt")
Eq(Sha256File(tmp "\abc.txt"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256")
Eq(Sha256File(tmp "\missing.txt"), "", "sha256 of a missing file")
FileAppend("BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD  Win11KeyRemapper.exe`r`n"
         . "0000000000000000000000000000000000000000000000000000000000000000  Win11KeyRemapper-v9.zip`r`n", tmp "\sums.txt")
sums := ReadSums(tmp "\sums.txt")
Eq(sums.Count " " sums["Win11KeyRemapper.exe"], "2 ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "read sums")
Eq(ParseArgs().restartPid " " ParseArgs().updated, "0 0", "no command-line arguments")

; ---- 3. Precomputed rules ----
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Eq(RT.down, "{Blind}{vk41sc01E down}", "key down")
Eq(RT.up, "{Blind}{vk41sc01E up}", "key up")
c.targetMods := ["LCtrl", "LShift"]
Reset(c)
Eq(RT.combo, "{LCtrl down}{LShift down}{vk41sc01E}{LShift up}{LCtrl up}", "combo")
c.targetVK := 0
Reset(c)
Eq(RT.mode, "None", "Key without target -> None")

; ---- 4. Hook: default settings ----
NL_DOWN := "send:{Blind}{vk90sc145 down};", NL_UP := "send:{Blind}{vk90sc145 up};"
Reset(DefaultSettings())
Eq(Ev(0xFF, 0x175), 1, "NitroSense down swallowed")
Eq(TakeQueue(), NL_DOWN, "Num Lock pressed")
Eq(Ev(0xFF, 0x175), 1, "repeat swallowed")
Eq(TakeQueue(), "", "a held lock key doesn't repeat (toggles once)")
Eq(Ev(0xFF, 0x175, true), 1, "up swallowed")
Eq(TakeQueue(), NL_UP, "Num Lock released")
Eq(Ev(0xFF, 0x175), 1, "2nd press")
Eq(TakeQueue(), NL_DOWN, "2nd press presses again")
Ev(0xFF, 0x175, true), TakeQueue()
Check(Ev(0xFF, 0x159) != 1 && Ev(0xFF, 0x159, true) != 1, "Win Lock on passes")
Check(Ev(0xFF, 0x162) != 1, "Win Lock off passes")
Check(Ev(0xFF, 0x175, false, true) != 1, "injected passes")
Eq(TakeQueue(), "", "nothing queued for passed keys")

REPEAT_MS := 50
Ev(0xFF, 0x175), Sleep(120)
Eq(Ev(0xFF, 0x175), 1, "stale press")
Eq(TakeQueue(), NL_DOWN NL_DOWN, "missed key-up: a new press")
REPEAT_MS := 1500
Ev(0xFF, 0x175, true), TakeQueue()

Check(Ev(0xA2, 0x1D) != 1, "LCtrl passes")
Check(HELD.Has("LCtrl"), "LCtrl tracked")
Eq(Ev(0xFF, 0x175), 1, "LCtrl+NitroSense")
Eq(TakeQueue(), NL_DOWN, "LCtrl+NitroSense presses Num Lock (launcher needs RCtrl)")
Ev(0xFF, 0x175, true), Ev(0xA2, 0x1D, true)
Check(!HELD.Has("LCtrl"), "LCtrl released")

Check(ModsMatch(Map("RCtrl", true)), "RCtrl matches launcher")
Check(!ModsMatch(Map("LCtrl", true)), "LCtrl doesn't match")
Check(!ModsMatch(Map("RCtrl", true, "LShift", true)), "extra modifier doesn't match")
Check(!ModsMatch(Map()), "no modifier doesn't match")
c := DefaultSettings(), c.launchAnySide := true
Reset(c)
Check(ModsMatch(Map("LCtrl", true)), "any side: LCtrl matches")
Check(!ModsMatch(Map("LAlt", true)), "any side: Alt doesn't")

; launcher without modifiers on F13
c := DefaultSettings(), c.launchMods := [], c.launchVK := 0x7C, c.launchSC := 0x64
Reset(c)
Eq(Ev(0x7C, 0x64), 1, "launch key swallowed")
Eq(Ev(0x7C, 0x64), 1, "launch repeat swallowed")
Eq(TakeQueue(), "launch;", "launch queued once")
Eq(Ev(0x7C, 0x64, true), 1, "launch up swallowed")
Check(Ev(0x7D, 0x65) != 1, "F14 passes")

; ---- 5. Hook: other modes ----
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Ev(0xFF, 0x175), Ev(0xFF, 0x175), Ev(0xFF, 0x175, true)
Eq(TakeQueue(), "send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E up};", "real remap down/repeat/up")
c.targetMods := ["LCtrl"]
Reset(c)
Ev(0xFF, 0x175), Ev(0xFF, 0x175), Ev(0xFF, 0x175, true)
Eq(TakeQueue(), "send:{LCtrl down}{vk41sc01E}{LCtrl up};send:{LCtrl down}{vk41sc01E}{LCtrl up};", "combo on each down, nothing on up")
c.mode := "Disable"
Reset(c)
Eq(Ev(0xFF, 0x175), 1, "disabled key swallowed")
Eq(Ev(0xFF, 0x175, true), 1, "disabled key-up swallowed")
Eq(TakeQueue(), "", "disable does nothing")
c.mode := "None", c.launchEnabled := false
Reset(c)
Check(Ev(0xFF, 0x175) != 1, "mode None passes")
Ev(0xFF, 0x175, true)
c := DefaultSettings(), c.matchSC := false
Reset(c)
Eq(Ev(0xFF, 0x159), 1, "MatchSC=0 also catches Win Lock (expected)")
Ev(0xFF, 0x159, true), TakeQueue()

Reset(DefaultSettings())
PAUSED := true
Check(Ev(0xFF, 0x175) != 1, "paused passes")
Check(Ev(0xFF, 0x175, true) != 1, "paused up passes")
PAUSED := false

; settings change while the key is held: release target, eat physical key-up
c := DefaultSettings(), c.mode := "Key", c.targetVK := 0x41, c.targetSC := 0x1E
Reset(c)
Ev(0xFF, 0x175)
CFG := DefaultSettings()
ApplySettings()
Eq(TakeQueue(), "send:{Blind}{vk41sc01E down};send:{Blind}{vk41sc01E up};", "held target released on apply")
Eq(Ev(0xFF, 0x175, true), 1, "physical key-up eaten after apply")
Eq(TakeQueue(), "", "nothing sent on that key-up")

; ---- 6. Capture ----
Reset(DefaultSettings())
StartCap(target) {
    CAP.target := target, CAP.mods := Map(), CAP.downs := Map(), CAP.result := 0, CAP.active := true
}
StartCap("launch")
Eq(Ev(0xA3, 0x11D), 1, "cap: RCtrl down eaten")
Eq(Ev(0xA3, 0x11D), 1, "cap: RCtrl repeat eaten")
Eq(Ev(0xFF, 0x175), 1, "cap: NitroSense eaten")
Check(!CAP.active, "cap: finished on non-modifier")
Eq(CAP.result.vk " " CAP.result.sc " " JoinMods(CAP.result.mods), 255 " " 0x175 " RCtrl", "cap: result")
Eq(TakeQueue(), "", "cap: no action fired")
Eq(Ev(0xFF, 0x175), 1, "cap: repeat after finish eaten")
Eq(Ev(0xFF, 0x175, true), 1, "cap: key-up eaten")
Eq(Ev(0xA3, 0x11D, true), 1, "cap: RCtrl key-up eaten")
Eq(SWALLOW.Count, 0, "cap: swallow list empty")
Eq(TakeQueue(), "", "cap: still no action")

StartCap("source")
Ev(0xA3, 0x11D)
Eq(Ev(0xA3, 0x11D, true), 1, "cap: lone modifier up")
Eq(CAP.result.vk " " CAP.result.sc " " JoinMods(CAP.result.mods), 0xA3 " " 0x11D " ", "cap: lone modifier captured")

StartCap("target")
Check(Ev(0x0D, 0x1C, true) != 1, "cap: key-up of a key pressed before passes")
Ev(0xA2, 0x21D), Ev(0xA5, 0x138), Ev(0x41, 0x1E)
Eq(JoinMods(CAP.result.mods), "RAlt", "cap: AltGr fake LCtrl ignored")
Ev(0x41, 0x1E, true), Ev(0xA5, 0x138, true), Ev(0xA2, 0x21D, true)
Eq(SWALLOW.Count, 0, "cap: AltGr ups eaten")

StartCap("target")
Ev(0xA3, 0x11D), Ev(0x13, 0x145)                    ; what Windows sends for Right Ctrl + Num Lock
Eq(Hex(CAP.result.vk) " " JoinMods(CAP.result.mods), "0x90 RCtrl", "cap: Ctrl + Num Lock isn't Pause")
Ev(0x13, 0x145, true), Ev(0xA3, 0x11D, true)

StartCap("target")
Ev(0xA0, 0x2A)
CaptureCancel()
Eq(Ev(0xA0, 0x2A, true), 1, "cancel: held modifier key-up eaten")
Check(Ev(0xA0, 0x2A) != 1, "cancel: next press works")
Ev(0xA0, 0x2A, true)

; ---- 7. Settings window (hidden; changes apply at once) ----
Reset(DefaultSettings())
WriteSettings(SETTINGS_PATH, CFG)
NS.checked := true, NS.target := ""
ShowSettings()
Check(UI.gui && UI.page = "keys" && UI.title.Value = "Keys", "gui: opens on Keys")
Check(!DEV_COPY && UI.gui.Title = APP.name, "gui: no Local project marker outside a git checkout")
Eq(CopyKind().kind, "script", "copy: a script run by an installed AutoHotkey")
Check(InStr(CopyKind().desc, "installed on this PC"), "copy: says which AutoHotkey runs it")
Eq(UI.keyText["source"], "NitroSense key", "gui: source keys")
Eq(UI.keyText["launch"], "Right Ctrl + NitroSense key", "gui: launch keys")
codes := 0
for item in UI.items
    if (item.page = "keys" && item.ctl.Type = "Text" && InStr(item.ctl.Value, "VK "))
        codes++
Eq(codes, 0, "gui: no description lines on the Keys page")
Eq(UI.srcKeys.codes[1] " | " UI.targetKeys.codes[1], "VK FF · SC 175 | VK 90 · SC 145", "gui: codes under the keys")
Eq(UI.launchKeys.codes[1] " | " UI.launchKeys.codes[2], "VK A3 · SC 11D | VK FF · SC 175", "gui: codes under each key of the shortcut")
Eq(UI.modeBtns[1].variant UI.modeBtns[2].variant, "accent", "gui: mode button lit")
Eq(MODE_LABELS.Length MODE_BUTTONS.Length, "33", "gui: only press a key, do nothing, normal")
Check(UI.targetKeys.Visible && UI.keyText["target"] = "Num Lock", "gui: works as Num Lock")
Check(InStr(UI.appList.Text, "missing"), "gui: app not found")
Eq(UI.status.Value, "Active", "gui: status")
Eq(UI.tgState["launchEnabled"] UI.tgState["distinguish"] UI.tgState["matchSC"] UI.tgState["trayIcon"]
 . UI.tgState["checkUpdates"] UI.tgState["remapping"] UI.tgState["autostart"], "1111110", "gui: switches")
Eq(UI.toastWhen.Value " " UI.toastPos.Value " " UI.toastAnim.Value " " UI.theme.Value, "1 1 1 1", "gui: lists")
Eq(UI.updBtn.Text, "Check now", "gui: update button")
ShowPage("about")
Check(UI.title.Value = "About" && !UI.srcKeys.Visible, "gui: switching section hides the others")
ShowPage("keys")
Check(UI.srcKeys.Visible, "gui: back to Keys")

DRAFT.toastPosition := "BottomRight", DRAFT.toastAnim := "Fade"
PreviewToast()
Check(InStr(TOASTS[TOASTS.Length], "Bottom right · Fade in · Glass") && GTCFG.position = "TopCenter", "gui: test notification uses the draft, then restores")
CommitDraft()
Eq(UI.toastPos.Value " " UI.toastAnim.Value " " CFG.toastPosition, "5 2 BottomRight", "gui: notification style applied")
UPD.state := "available", UPD.latest := "v9.9.9"
UpdateUpdatesRow()
Check(UI.updBtn.Text = "Install v9.9.9" && InStr(UI.updText.Value, "new version"), "gui: update available (installs itself)")
UPD.state := "", UPD.latest := ""
UpdateUpdatesRow()

CaptureToggle("source")
Check(UI.srcKeys.listen && UI.keyText["source"] = "listening", "gui: listening keys")
CaptureToggle("source")
Check(!CAP.active && UI.keyText["source"] != "listening", "gui: click again cancels")
CaptureToggle("source")
CaptureToggle("target")
Eq(CAP.target, "target", "gui: other capture replaces")
CaptureCancel()
CaptureToggle("source")
Ev(0x41, 0x1E)
CaptureDone()
Ev(0x41, 0x1E, true)
Eq(UI.keyText["source"] " " CFG.sourceVK, "A 65", "gui: detected key applied at once")
Check(InStr(NT.last, "Your key: A") && UI.srcKeys.codes[1] = "VK 41 · SC 1E", "gui: notice, and the new key's code under it  [" NT.last "]")
Eq(LoadSettings(SETTINGS_PATH).sourceVK, 0x41, "gui: and saved")

SetMode(2)
Check(CFG.mode = "Disable" && UI.keyText["target"] = "Nothing" && !UI.targetKeys._enabled, "gui: works as Nothing when the key does nothing")
Check(UI.modeBtns[2].variant = "accent" && UI.modeBtns[1].variant = "", "gui: Disabled lit")
Check(InStr(NT.last, "The key: Does nothing") && !InStr(LastToast(), "The key"), "gui: a notice inside the window says what was saved")
DRAFT.targetVK := 0
SetMode(1)
Eq(DRAFT.mode " " CFG.mode, "Key Disable", "gui: incomplete Key mode isn't applied")
Check(CAP.active && CAP.target = "target" && UI.targetKeys.listen, "gui: no key yet: it listens for it right away")
Ev(0x43, 0x2E)
CaptureDone()
Ev(0x43, 0x2E, true)
Eq(CFG.mode " " CFG.targetVK, "Key 67", "gui: applied once complete")

d := DefaultSettings(), d.targetVK := 0
Check(InStr(ValidateSettings(d, &where), "Works as") && where = "target", "validate: Key needs target")
d := DefaultSettings(), d.launchMods := []
Check(InStr(ValidateSettings(d, &where), "add a modifier") && where = "launch", "validate: launcher = source without modifier")
d := DefaultSettings(), d.launchVK := 0
Check(InStr(ValidateSettings(d), "shortcut that opens"), "validate: launcher needs shortcut")
d := DefaultSettings(), d.launchPath := "C:\nope\nope.exe"
Eq(ValidateSettings(d), "", "validate: a missing app only warns")
Eq(ValidateSettings(DefaultSettings()), "", "validate: defaults ok")

DRAFT.launchPath := "C:\nope\nope.exe", UpdateApp()
Check(UI.appList.Text = "nope (missing)" && UI.appList.items.Length = 3, "gui: custom app missing")
AutoApp()
Eq(CFG.launchPath, "auto", "gui: Auto = auto-detect")
FlipSwitch("distinguish")
Eq(UI.keyText["launch"] " " CFG.launchAnySide, "Ctrl + NitroSense key 1", "gui: either side")
FlipSwitch("distinguish")
FlipSwitch("launchEnabled")
Check(!CFG.launchEnabled && !UI.launchKeys._enabled && !UI.appList.Enabled && !UI.tg["distinguish"].Enabled, "gui: launcher off")
FlipSwitch("distinguish")
Eq(CFG.launchAnySide, 0, "gui: disabled switch can't flip")
FlipSwitch("remapping")
Check(PAUSED && UI.status.Value = "Paused", "gui: remapping off = paused")
FlipSwitch("remapping")
Check(!PAUSED, "gui: remapping back on")
FlipSwitch("trayIcon")
Check(A_IconHidden && InStr(NT.last, "The tray icon is hidden"), "gui: tray icon hidden, with a hint")
FlipSwitch("trayIcon")
Check(!A_IconHidden, "gui: tray icon back")
UI.toastWhen.Value := 2
DRAFT.toastWhen := TOAST_WHENS[2], CommitDraft()
Eq(LoadSettings(SETTINGS_PATH).toastWhen, "Startup", "gui: notifications only at startup")

; Drop-down lists of our own
ddw := UI.toastAnim
Check(ddw.kind = "select" && ddw.Text = TOAST_ANIM_LABELS[ddw.Value] && ddw.items.Length = 3, "select: shows the chosen item")
OpenSelect(ddw)
Check(!SEL.wd, "select: doesn't open while the window is hidden")
SEL.wd := ddw, SEL.gui := 0, SEL.hwnd := 0, SEL.alpha := 0, SEL.dy := 0
SEL.pad := 12, SEL.inset := 4, SEL.itemH := 36, SEL.w := 200, SEL.h := 3 * 36 + 8, SEL.x := 0, SEL.y := 0
Eq(SelectItemAt(30, 16) " " SelectItemAt(30, 16 + 2 * 36 + 5) " " SelectItemAt(5, 30) " " SelectItemAt(30, 16 + 3 * 36 + 1) " " SelectItemAt(30, 10)
 , "1 3 0 0 0", "select: the item under the mouse (outside = none)")
SEL.hot := 1, SEL.down := 0
OnSettingsKey(0x28, 0, 0x100, 0), OnSettingsKey(0x28, 0, 0x100, 0), OnSettingsKey(0x28, 0, 0x100, 0)
Eq(SEL.hot, 3, "select: arrow keys move, and stop at the last item")
OnSettingsKey(0x0D, 0, 0x100, 0)
Critical "Off"
loop 100                                ; onChange runs from a timer: wait for it (slow CI machines)
    Sleep 20
until CFG.toastAnim = "None"
Critical
Check(!SEL.wd && ddw.Value = 3 && CFG.toastAnim = "None" && InStr(NT.last, "Animation: None"), "select: Enter chooses, applies and saves")
SEL.wd := ddw, SEL.hot := 1, SEL.alpha := 0
OnSettingsKey(0x1B, 0, 0x100, 0)
Check(!SEL.wd && ddw.Value = 3, "select: Esc closes without changing")
Eq(OnSettingsKey(0x28, 0, 0x100, 0), "", "select: keys pass through when no list is open")
ddw.Value := 1, DRAFT.toastAnim := "Slide", CommitDraft()

; Never: no system notifications (warnings still show); notices inside the window do
DRAFT.toastWhen := "Never", CommitDraft()
n := TOASTS.Length
SystemToast("Update available: v9", "x", "update")
SetPaused(true), SetPaused(false)
Eq(TOASTS.Length, n, "never: no system notifications")
SystemToast("App not found", "x", "warn")
Check(InStr(LastToast(), "App not found"), "never: warnings still show")
UPD.latest := "v9.9.9"
UpdateDone("latest", true)
Check(InStr(NT.last, "You're up to date") && !InStr(LastToast(), "up to date"), "never: Check now answers inside the window")
UPD.state := "", UPD.latest := ""
UpdateUpdatesRow()
DRAFT.toastWhen := "Always", CommitDraft()

FlipSwitch("toastGlass")
Check(!CFG.toastGlass && !GTCFG.glass && UI.tgState["toastGlass"] = 0, "gui: transparency effects off")
FlipSwitch("toastGlass")

; Widgets: mouse down/up like a button, hand cursor, danger buttons, About links
Check(!UI.HasOwnProp("more"), "gui: no ⋯ menu")
hw := UI.srcKeys.Hwnd
OnSettingsMouseDown(0, 0x00050005, 0x201, hw)
Check(UI.srcKeys.press, "gui: key pressed on mouse down")
Eq(CAP.active, false, "gui: but nothing happens yet")
OnSettingsMouseUp(0, 0x00050005, 0x202, hw)
Critical "Off"
Sleep 30
Critical
Check(!UI.srcKeys.press && CAP.active && CAP.target = "source", "gui: action on mouse up over the key")
CaptureCancel()
OnSettingsMouseDown(0, 0x00050005, 0x201, hw)
OnSettingsMouseUp(0, 0x0005FFFB, 0x202, hw)          ; released outside (x = -5)
Critical "Off"
Sleep 30
Critical
Check(!CAP.active, "gui: released outside does nothing")
Eq(OnSettingsSetCursor(hw, 0x2000001, 0x20, UI.gui.Hwnd), 1, "gui: hand cursor over a button")
UI.modeBtns[1].Enabled := false
Eq(OnSettingsSetCursor(UI.modeBtns[1].Hwnd, 0x2000001, 0x20, UI.gui.Hwnd), "", "gui: normal cursor over a disabled button")
UI.modeBtns[1].Enabled := true
Eq(OnSettingsSetCursor(UI.theme.Hwnd, 0x2000001, 0x20, UI.gui.Hwnd), 1, "gui: hand cursor over a drop-down list")
danger := []
for hwnd, wd in UI.widgets
    if (wd.kind = "button" && wd.variant = "danger")
        danger.Push(wd.Text)
Eq(danger.Length, 4, "gui: Restart, Exit, Uninstall and Reset are danger buttons")
labels := "", nEdits := 0
for item in UI.items
    if (item.page = "about" && UI.widgets.Has(item.ctl.Hwnd) && UI.widgets[item.ctl.Hwnd].kind = "link")
        labels .= SubStr(UI.widgets[item.ctl.Hwnd].label, 1, 4) ","
for item in UI.items
    nEdits += item.ctl.Type = "Edit"
Eq(labels, "Tell,Repo,Sugg,Freq,Ask ,", "gui: About links in two groups")
Check(!nEdits && LINKS[2][2][1][2] = "/blob/main/docs/FAQ.md", "gui: FAQ on GitHub, no text box")
FlipSwitch("remapping")
Check(UI.anims.Has(UI.tg["remapping"]) || !AnimationsOn() || !UI.tg["remapping"].Visible, "gui: the switch slides")
FlipSwitch("remapping")

newDpi := UI.dpi = 120 ? 168 : 120     ; another monitor's scale, whichever one the window is on
UI.dpi := newDpi, UI.k := newDpi / 96
ApplyLayout()
ctx := PMv2()                           ; read sizes like the window sees them (no DPI virtualization)
UI.modeBtns[1].GetPos(, , &bw)
PMv2(ctx)
Eq(bw, Round(150 * UI.k), "gui: relaid out for another monitor's scale")
Check(UI.laidOut["general"] != newDpi, "gui: hidden sections are laid out later")
ShowPage("general")
ctx := PMv2()
UI.theme.GetPos(, , &lw)
PMv2(ctx)
Check(UI.laidOut["general"] = newDpi && lw = Round(160 * UI.k), "gui: laid out when shown  (" lw ")")
ShowPage("keys")

newTheme := UI.themeName = "dark" ? "Light" : "Dark"
DRAFT.theme := newTheme
CommitDraft()
RebuildSettings()
Check(UI.gui && UI.themeName = StrLower(newTheme) && CFG.theme = newTheme && UI.page = "keys", "gui: theme change rebuilds, same section")
SetMode(3)
Eq(CFG.mode " " UI.keyText["target"], "None " UI.keyText["source"], "gui: mode applied, works as itself")
Eq(ParseArgs().settings, "", "no --settings argument")

FlipSwitch("autostart")
Check(FileExist(APP.lnk), "gui: autostart on")
FileGetShortcut(APP.lnk, &lnkTarget, , &lnkArgs)
Eq(lnkTarget, A_AhkPath, "shortcut runs AutoHotkey")
Eq(lnkArgs, '"' A_ScriptFullPath '"', "shortcut passes the script")
CloseSettings()
Check(!UI.gui, "gui: closed")
CFG.theme := "System"

; ---- 8. Tray / pause ----
BuildTray()
Check(InStr(A_IconTip, "Windows 11 Key Remapper`nA → Caps Lock") || InStr(A_IconTip, "is off"), "tray tooltip  [" A_IconTip "]")
Eq(DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle), 5, "tray: Settings, Pause, Restart, Exit (+ line)")
TogglePause()
Check(PAUSED && InStr(A_IconTip, "(paused)"), "pause on")
TogglePause()
Check(!PAUSED, "pause off")
UPD.latest := "v9.9.9"
UpdateDone("available", false)
Check(InStr(LastToast(), "Update available: v9.9.9"), "update offered as a system notification")
n := TOASTS.Length
UpdateDone("available", false)
Eq(TOASTS.Length, n, "same update not announced twice")
UPD.state := ""

; ---- 9. NitroSense detection (real machine) ----
Note("NitroSense auto-detect -> [" DetectNitroSense(true) "] " NS.label)
CFG.launchPath := "auto"
LaunchApp()
Note("LaunchApp ran -> [" (RAN.Length ? RAN[RAN.Length] : "") "]")

; ---- 10. Developer log and shutdown ----
Eq(DefaultSettings().log, false, "log: off by default")
logFile := LogPath()
Check(!DEVLOG.on && !FileExist(logFile), "log: nothing written while off")
c := DefaultSettings(), c.log := true
WriteSettings(SETTINGS_PATH, c)
Eq(LoadSettings(SETTINGS_PATH).log, 1, "log: Log=1 round trip")
Reset(c)
Check(DEVLOG.on && FileExist(logFile), "log: turned on, file next to the settings")
txt := FileRead(logFile, "UTF-8")
Check(RegExMatch(txt, "^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}  ---- Log on: Windows 11 Key Remapper " APP.version ", AutoHotkey ")
    , "log: header with the time and the versions")
Ev(0xFF, 0x175), Ev(0xFF, 0x175, true), RunQueue()
txt := FileRead(logFile, "UTF-8")
Check(InStr(txt, "Remapped key: sent {Blind}{vk90sc145 down}") && InStr(txt, "Remapped key: sent {Blind}{vk90sc145 up}"), "log: the remapped key's actions")
before := StrLen(txt)
Ev(0x41, 0x1E), Ev(0x41, 0x1E, true), RunQueue()     ; typing "a": passes through
Eq(StrLen(FileRead(logFile, "UTF-8")), before, "log: typed keys are never written")
LogError(Error("boom"), "Exit")
Check(InStr(FileRead(logFile, "UTF-8"), "ERROR: boom"), "log: unexpected errors")
DllCall("QueryPerformanceFrequency", "int64*", &qf := 0), DllCall("QueryPerformanceCounter", "int64*", &q0 := 0)
loop 300
    Log("cost test " A_Index)
DllCall("QueryPerformanceCounter", "int64*", &q1 := 0)
perLine := (q1 - q0) * 1000 / qf / 300
Note("log: " Round(perLine, 3) " ms per line")
Check(perLine < 10, "log: a line costs a few milliseconds at most (~0.3 ms here; CI disks are slower)")
FileAppend(Format("{:1100000}", ""), logFile)
DEVLOG.n := 99
Log("after the size check")
Check(FileExist(DEVLOG.old) && FileGetSize(logFile) < 1000, "log: over 1 MB it becomes .old.log and starts again")

class FakeRequest {
    static aborted := 0
    Abort() => FakeRequest.aborted++
}
UPD.req := FakeRequest(), UPD.state := "checking"
n := TOASTS.Length
Check(OnQueryEndSession(0, 0) = true && ENDING, "shutdown: answered at once")
Check(FakeRequest.aborted = 1 && !UPD.req && UPD.state = "", "shutdown: an update check in progress is stopped")
StatusToast(), SystemToast("x", "y")
Eq(TOASTS.Length, n, "shutdown: no notifications while Windows ends the session")
CheckUpdates(false)
Check(UPD.state != "checking" && !UPD.req, "shutdown: no new update check")
OnEndSession(0, 0)
Check(!ENDING, "shutdown cancelled: back to normal")
SystemToast("x", "y")
Eq(TOASTS.Length, n + 1, "notifications again after a cancelled shutdown")
SetTimer(AutoCheckUpdates, 0)
txt := FileRead(logFile, "UTF-8")
Check(InStr(txt, "Windows asks to end the session (shutdown or restart)") && InStr(txt, "Update check stopped")
    && InStr(txt, "Shutdown cancelled: carrying on"), "log: the shutdown steps")
Eq(EndReason(0x80000000) "|" EndReason(0x40000000) "|" EndReason(1), "sign out|shutdown or restart, forced|an installer asks apps to close", "shutdown reasons")

ShowSettings("advanced")
Eq(UI.logPath.Value, logFile, "gui: log file path shown")
FlipSwitch("log")
Check(!DEVLOG.on && !CFG.log && InStr(NT.last, "Developer log: off"), "gui: log switch off")
FlipSwitch("log")
Check(DEVLOG.on && CFG.log && InStr(FileRead(SETTINGS_PATH), "`nLog=1"), "gui: log switch on, saved")
CloseSettings()
Reset(DefaultSettings())
Check(!DEVLOG.on, "log: off again with the defaults")

; ---- 11. Export / import settings ----
Reset(DefaultSettings())
WriteSettings(SETTINGS_PATH, CFG)
expFile := tmp "\exported.ini"
ExportSettings(expFile)
Eq(FileRead(expFile, "UTF-16"), SettingsText(CFG), "export: the active settings, explained")
c := DefaultSettings(), c.toastWhen := "Never", c.targetVK := 0x14, c.targetSC := 0x3A, c.theme := "Dark"
FileDelete(expFile), WriteSettings(expFile, c)
Eq(ImportSettings(expFile), "", "import: accepted")
Check(CFG.toastWhen = "Never" && CFG.targetVK = 0x14 && CFG.theme = "Dark", "import: applied")
Eq(LoadSettings(SETTINGS_PATH).targetVK, 0x14, "import: and saved")
FileAppend("hello", tmp "\notes.txt")
Check(InStr(ImportSettings(tmp "\notes.txt"), "isn't a settings file") && CFG.toastWhen = "Never", "import: other files refused, nothing changes")
FileAppend("[Remap]`r`nMode=Key`r`nTargetVK=0`r`n", tmp "\broken.ini")
Check(InStr(ImportSettings(tmp "\broken.ini"), "Works as") && CFG.targetVK = 0x14, "import: incomplete settings refused")
Check(InStr(ImportSettings(tmp "\missing.ini"), "can't be read"), "import: missing file")
Reset(DefaultSettings())
WriteSettings(SETTINGS_PATH, CFG)

; ---- 12. Uninstall (on a fake copy of the release in tmp) ----
Eq(UninstallApp(), false, "uninstall: nothing happens unless confirmed")
savedSettings := SETTINGS_PATH, savedLnk := APP.lnk, savedLnks := UNINSTALL_LNKS, savedKey := UNINSTALL_KEY
UNINSTALL_KEY := "HKCU\Software\Win11KeyRemapperTest\Uninstall"
MakeFakeInstall(root) {
    global SETTINGS_PATH, UNINSTALL_LNKS
    for file in PACKAGE_FILES {
        SplitPath(root "\" file, , &dir)
        DirCreate(dir)
        FileAppend("x", root "\" file)
    }
    SETTINGS_PATH := root "\src\settings.ini"
    WriteSettings(SETTINGS_PATH, DefaultSettings())
    FileAppend("log", root "\src\Win11KeyRemapper.log"), FileAppend("old", root "\src\Win11KeyRemapper.old.log")
    APP.lnk := root "\startup.lnk", FileAppend("x", APP.lnk)
    UNINSTALL_LNKS := [root "\menu.lnk"], FileAppend("x", root "\menu.lnk")
    RegWrite("x", "REG_SZ", UNINSTALL_KEY, "DisplayName")
}
root := tmp "\installed"
MakeFakeInstall(root)
UninstallFiles(root, false)
left := ""
loop files, root "\*", "FR"
    left .= StrReplace(A_LoopFilePath, root "\") " "    ; (A_LoopFilePath keeps root's form: CI's temp folder has a short 8.3 name)
Eq(Trim(left), "Win11KeyRemapper.exe src\settings.ini", "uninstall: only the running exe (removed after exit) and the kept settings remain")
Check(!DirExist(root "\docs") && !DirExist(root "\assets") && !DirExist(root "\src\lib"), "uninstall: empty folders removed")
Check(!FileExist(root "\startup.lnk") && !FileExist(root "\menu.lnk"), "uninstall: shortcuts removed")
regLeft := ""
try regLeft := RegRead(UNINSTALL_KEY, "DisplayName")
Eq(regLeft, "", "uninstall: Installed apps entry removed")
DirDelete(root, true)
MakeFakeInstall(root)
UninstallFiles(root, true)
left := ""
loop files, root "\*", "FR"
    left .= StrReplace(A_LoopFilePath, root "\") " "    ; (A_LoopFilePath keeps root's form: CI's temp folder has a short 8.3 name)
Check(Trim(left) = "Win11KeyRemapper.exe" && !DirExist(root "\src"), "uninstall: with the settings, nothing else is left  [" left "]")
try RegDeleteKey("HKCU\Software\Win11KeyRemapperTest")
SETTINGS_PATH := savedSettings, APP.lnk := savedLnk, UNINSTALL_LNKS := savedLnks, UNINSTALL_KEY := savedKey
Eq(ParseArgs().uninstall, false, "no --uninstall argument")

; ---- 13. Update: the new files go over this copy, or nothing changes ----
upRoot := tmp "\upd-root", upNew := tmp "\upd-new", upBak := tmp "\upd-bak"
DirCreate(upRoot "\src"), DirCreate(upNew "\src\lib")
FileAppend("old app", upRoot "\src\Win11KeyRemapper.ahk"), FileAppend("same", upRoot "\README.md")
FileAppend("[Settings]", upRoot "\src\settings.ini")
FileAppend("new app", upNew "\src\Win11KeyRemapper.ahk"), FileAppend("same", upNew "\README.md")
FileAppend("new lib", upNew "\src\lib\GlassToast.ahk")
Eq(ApplyUpdate(upNew, upRoot, upBak), 2, "update: changed and new files written, unchanged skipped")
Eq(FileRead(upRoot "\src\Win11KeyRemapper.ahk") FileRead(upRoot "\src\lib\GlassToast.ahk"), "new appnew lib", "update: new files in place")
Eq(FileRead(upRoot "\src\settings.ini"), "[Settings]", "update: settings.ini kept")
FileDelete(upNew "\src\Win11KeyRemapper.ahk"), FileAppend("newer app", upNew "\src\Win11KeyRemapper.ahk")
FileDelete(upNew "\src\lib\GlassToast.ahk"), FileAppend("newer lib", upNew "\src\lib\GlassToast.ahk")
FileSetAttrib("+R", upRoot "\src\lib\GlassToast.ahk")     ; this copy will fail
failed := false
try ApplyUpdate(upNew, upRoot, upBak "2")
catch
    failed := true
FileSetAttrib("-R", upRoot "\src\lib\GlassToast.ahk")
Check(failed, "update: a failed copy is reported")
Eq(FileRead(upRoot "\src\Win11KeyRemapper.ahk") FileRead(upRoot "\src\lib\GlassToast.ahk"), "new appnew lib", "update: a failed copy undoes the others")
Check(!DEV_COPY && CanInstallUpdate() = DirWritable(A_ScriptDir), "update: installs itself outside a git checkout")

QUEUE.Length := 0
try DirDelete(tmp, true)
FileAppend(PASSES " passed, " FAILS " failed`n", "*", "UTF-8")
ExitApp(FAILS ? 1 : 0)
