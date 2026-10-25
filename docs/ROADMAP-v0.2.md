# v0.2 — first public release (spec)

> Shipped as **v0.5.0**: the version number was raised before the release.
> Since then the exe is no longer published (Smart App Control blocks unsigned
> exes): see "The release: a runtime instead of an exe" in DEVELOPMENT.md.

Decisions taken with the user:

- Name: **Windows 11 Key Remapper** (subtitle: *NitroSense Key Remapper*). Exe:
  `Win11KeyRemapper.exe`. Repo: `Win11-Key-Remapper-Acer-Nitrosense`.
- Language: **English** (repo, UI, README). License: **MIT**.
- Skip a config-only v0.1: ship v0.2 directly **with a visual settings panel**.
- No separate KeyProbe tool (the user found it annoying, it filled the screen). Key
  detection lives **inside the settings panel**: click "Detect…", press a key or a
  combination, done.
- End users must NOT need AutoHotkey installed → compiled `.exe` (Ahk2Exe), plus the
  `.ahk` source for those who prefer it.

---

## 1. Configuration — `settings.ini`

Location: next to the exe if that folder is writable, otherwise
`%APPDATA%\Win11KeyRemapper\settings.ini`. Everything optional: missing keys fall back
to defaults. Use a sentinel default in `IniRead` so an intentionally **empty** value
(e.g. no modifiers) is not replaced by the default.

```ini
[Remap]
SourceVK=0xFF          ; key to remap (NitroSense by default)
SourceSC=0x175
MatchSC=1              ; 1 = exact scan code (needed: Win Lock shares VK 0xFF)
Mode=NumLock           ; NumLock | CapsLock | ScrollLock | Key | Disable | None
TargetMods=            ; Mode=Key: modifiers, e.g. LCtrl,LShift
TargetVK=0x0
TargetSC=0x0

[Launcher]
LaunchEnabled=1        ; optional shortcut to open an app (NitroSense by default)
LaunchMods=RCtrl       ; exact modifier set (side-specific)
LaunchVK=0xFF
LaunchSC=0x175
LaunchAnySide=0        ; 1 = Ctrl/Alt/Shift/Win on either side
LaunchPath=auto        ; auto = detect NitroSense, or a path / shell:AppsFolder\AUMID

[General]
ShowToast=1            ; toast at startup, unlock and display-on
```

Modifier names: `LCtrl RCtrl LAlt RAlt LShift RShift LWin RWin`
(VK `A2 A3 A4 A5 A0 A1 5B 5C`; map generic `10/11/12` to the left ones).
Write VK/SC as hex (`0x…`). First run: create the file with a short comment header
(UTF-16, same encoding `IniWrite` uses).

## 2. Keyboard hook (single `WH_KEYBOARD_LL`)

Order of checks for every event:

1. `nCode != 0` → pass. Read `vk`, `sc | ((flags & 1) << 8)`, `flags`.
2. **Injected** (`flags & 0x10`) → pass (our own `SendInput`).
3. **Swallowed key-ups**: if it's a key-up whose key-down we ate during capture → `return 1`.
4. **Capture mode active** → hand to the capture routine, always `return 1`.
5. Track modifiers in a `HELD` map (down → add, up → remove). Before matching a
   combo, prune entries whose `GetKeyState(name, "P")` is false (missed key-ups).
6. **Paused** → pass.
7. **Launcher**: key matches `LaunchVK/SC` (exact SC) and held modifiers == required
   set (exact, optional "any side" by family) → on first down queue `launch`, swallow
   the down and the matching up. Use a `LAUNCH.down` flag to ignore auto-repeat.
8. **Remap**: `Mode != None` and key matches source (`MatchSC` decides exact SC):
   - Toggle modes: act on down only, **ignore auto-repeat** (down while already down
     within 500 ms) — fixes the "holding the key toggles many times" issue.
   - `Key` without modifiers: real remap → `SendInput "{Blind}{vkXXscYYY down}"` on down,
     `up` on up (holding repeats naturally, Shift+source → Shift+target).
   - `Key` with modifiers: full combo on each down (no `{Blind}`), side-specific
     `{LCtrl down}…{vk..sc..}…{LCtrl up}`.
   - `Disable`: nothing.
   - Always `return 1` so Windows / vendor software never sees the source key.
9. Otherwise pass.

All actions go through a **queue** (`QUEUE.Push(action)` + `SetTimer(RunQueue, -1)`) so
order is preserved and nothing heavy runs inside the hook.

Toggles: `SetNumLockState(!GetKeyState("NumLock","T"))` (Caps/Scroll the same).

Drop the old `$NumLock::` hotkey from the personal script (not needed in a generic tool).

## 3. Key / shortcut detector (inside the settings panel)

Three capture targets: `source` (single key), `target` (key or combo), `launch` (combo).

- Click "Detect…": button shows "Listening…", the field shows
  "Press the key or shortcut now (click again to cancel)". 10 s timeout. Clicking the
  same button again cancels; starting another capture cancels the current one.
- Modifier key-down → remember it (`CAP.mods[name] := vk`), swallow.
- Non-modifier key-down → finish with the held modifiers (ignored for `source`), mark
  its key-up as swallowed.
- Modifier key-up while nothing else was pressed → capture **that modifier** as the key
  (lets users remap e.g. Right Ctrl).
- On finish, mark the still-held modifiers' key-ups as swallowed, leave capture mode,
  update the panel via `SetTimer` (never touch the GUI from the hook).
- Capture runs before rules and even while paused, so the NitroSense key itself can be
  detected.

Friendly names: known Acer codes (`FF:175` NitroSense key, `FF:159` Win Lock on,
`FF:162` Win Lock off), modifiers ("Right Ctrl"), otherwise `GetKeyName("vkXXscYYY")`,
fallback "Special key (SC 175)". Field text: `Right Ctrl + NitroSense key · VK FF SC 175`.

## 4. Settings window

Single window, Segoe UI 10, ~480 px content width, sections with accent headers.
Edits go to a draft copy; **Save** applies without restarting the script.

1. **Key to remap** — read-only field + "Detect key…"; checkbox
   "Match the exact scan code (recommended for vendor keys like NitroSense)".
2. **What it should do** — dropdown: Toggle Num Lock · Toggle Caps Lock · Toggle
   Scroll Lock · Press another key / shortcut · Disable the key · Off (keep original
   behavior). Target field + "Detect…" enabled only for "another key".
3. **Shortcut to open NitroSense (optional)** — checkbox "Enable", combo field +
   "Detect shortcut…", checkbox "Either left or right modifiers", app path edit (cue
   banner "Auto-detect NitroSense" via `EM_SETCUEBANNER 0x1501`), "Browse…" (exe/lnk),
   "Auto"; hint line shows what auto-detect found or "not found — use Browse…".
4. **General** — "Start with Windows", "Show a notification at startup and when
   unlocking".
5. Buttons: Reset defaults · Cancel · **Save** (default). Validate: `Key` mode needs a
   target; enabled launcher needs a shortcut.

First run (no ini): write defaults, open the panel with "Start with Windows" pre-checked
and show a welcome toast.

## 5. Tray menu

`Settings…` (default, double-click) · `Pause remapping` (checkmark, toast on change) ·
`Start with Windows` (checkmark) · `Open settings folder` · `About / GitHub` · `Exit`.
Tooltip = app name + current summary.

## 6. Start with Windows

Shortcut `A_Startup "\Windows 11 Key Remapper.lnk"`:
- compiled → target `A_ScriptFullPath`;
- source → target `A_AhkPath`, args `"A_ScriptFullPath"` (see CLAUDE.md: pointing to the
  `.ahk` doesn't start at logon).
On every launch, if the shortcut exists, recreate it (handles moved exe).

## 7. NitroSense auto-detection

1. `%ProgramFiles%\NitroSense\Prerequisites\NitroSenseLauncher.exe` (author's machine),
   `%ProgramFiles%\NitroSense\NitroSense.exe`, `%ProgramFiles(x86)%\…`.
2. Fallback: enumerate `Shell.Application` → `NameSpace("shell:AppsFolder").Items()`,
   first item whose name contains "NitroSense" → `Run "shell:AppsFolder\" item.Path`
   (covers the Microsoft Store version).
On failure: warning toast "App not found — choose it in Settings".

## 8. Toasts (use `src/lib/GlassToast.ahk`)

`GlassToast(title, sub, kind := "ok"|"warn"|"info", holdMs := 5000)`
- Startup / unlock / display-on: "Key Remapper is active" + summary
  ("NitroSense key → Num Lock"), or "Key Remapper is paused" (`info`).
- Save: "Settings saved" (2.5 s). Pause/resume: short toasts. Errors: `warn`.
Keep the session (`WTSRegisterSessionNotification`) and display-state
(`RegisterPowerSettingNotification`) logic from `legacy/NitroSenseRemap.ahk`.

## 9. Repo files

- `README.md`: banner (SVG), shields.io badges (release, downloads, license, Windows
  10/11, AutoHotkey v2, build), one-line hook — *"Keep hitting the NitroSense key
  instead of Num Lock or Backspace? Turn it into Num Lock, disable it, or remap it — no
  install."* — features, 3-step quick start, demo GIF (user records it with
  ScreenToGif; leave a commented placeholder, no broken image), settings table, tested
  models table (Acer Nitro V 16S AI ANV16S-41), `<details>` FAQ (antivirus false
  positive, SmartScreen, Task Manager limitation, Win Lock, uninstall, config location,
  run from source), `<details>` how it works, build from source, contributing,
  Star History chart, license.
- `docs/DEVELOPMENT.md`: the technical history from CLAUDE.md, in English, for
  contributors.
- `.github/workflows/build.yml`: `windows-latest`; download AutoHotkey v2
  (`https://www.autohotkey.com/download/ahk-v2.zip`) and Ahk2Exe
  (`gh release download -R AutoHotkey/Ahk2Exe -p "Ahk2Exe*.zip"`); compile with
  `Ahk2Exe.exe /in src\Win11KeyRemapper.ahk /out dist\Win11KeyRemapper.exe /base
  AutoHotkey64.exe` via `Start-Process -Wait`; zip exe + README + LICENSE + example ini;
  SHA-256 file; on tag `v*` publish a Release (`softprops/action-gh-release`); artifact
  on manual runs. Verify the URLs/asset names when writing it.
- `.github/ISSUE_TEMPLATE/`: `bug_report.yml`, `works_on_my_laptop.yml` (model, Windows
  version, codes shown by the detector), `feature_request.yml`, `config.yml`.
- `assets/icon.ico` (multi-size keycap icon, green accent `#30D158`), `assets/banner.svg`.
- `settings.example.ini`, `CHANGELOG.md` (0.2.0), `.gitignore`.
- Ahk2Exe directives at the top of the main script: `;@Ahk2Exe-SetName`,
  `SetDescription`, `SetVersion 0.2.0`, `SetMainIcon ..\assets\icon.ico`.
- `#Include %A_ScriptDir%\lib\GlassToast.ahk`.

## Later (v0.3+)

Multiple remap rules, Spanish UI, community model list, update check, code signing
(look into free OSS signing programs).
