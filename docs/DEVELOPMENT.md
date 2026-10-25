# Development notes

Technical notes for contributors: how the app is built, why, and the traps this
project already fell into. Read this before changing the hook or the toast.

## Layout

```
src/Win11KeyRemapper.ahk     the app: settings, hook, detector, tray, updates, settings window
src/lib/GlassToast.ahk       "liquid glass" notification (standalone library)
tests/run-tests.ps1          builds a patched copy of the app and runs tests/tests.ahk
tests/tests.ahk              logic tests (fake key events fed to the hook procedure)
tools/make-icon.ps1          regenerates assets/icon.ico
tools/build.ps1              compiles dist/Win11KeyRemapper.exe with Ahk2Exe (not published: see "The release")
tools/smoke-test.ps1         end-to-end checks of a release (CI): zip exe, install, uninstall
package/Win11KeyRemapper.ahk the launcher the release's Win11KeyRemapper.exe runs
installer/                   Inno Setup script (per-user installer)
assets/                      icon.ico, banner.svg, social-preview.png, screenshot-*.png
settings.example.ini         every setting with its default (a test checks it's what the app writes)
.github/workflows/build.yml  syntax check, tests, release folder + zip + installer, smoke test, signing, release on tag v*
docs/FAQ.md, docs/TESTED-MODELS.md, SUPPORT.md   pages linked from the README's "More"
.github/ISSUE_TEMPLATE/      bug, "works on my laptop", feature, question
.github/dependabot.yml       monthly PRs to update the GitHub Actions
SECURITY.md, CONTRIBUTING.md, CHANGELOG.md
```

## Everyday commands

```powershell
# Syntax check without running
AutoHotkey64.exe /ErrorStdOut /Validate src\Win11KeyRemapper.ahk

# Logic tests: no hook is installed, no keys are sent, nothing is shown
powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1

# Run it. If a copy is already running, this one just asks it to open its
# settings and exits; use tray → Restart instead.
AutoHotkey64.exe src\Win11KeyRemapper.ahk

# Regenerate the icon (add -Preview preview.png to see every size)
powershell -ExecutionPolicy Bypass -File tools\make-icon.ps1

# Build dist\Win11KeyRemapper.exe (downloads AutoHotkey + Ahk2Exe once into a
# cache). Only for working on the exe: it isn't published (see "The release: a runtime instead of an exe").
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

When you run from source, `settings.ini` is created in `src\` (gitignored).

`settings.ini` explains itself: `WriteSettings()` writes the whole file from
`SETTINGS_TEMPLATE` (a comment above every key, `{Key}` placeholders for the
values) into a `.tmp` file and moves it over the old one, in UTF-16 with BOM so
`IniRead` handles non-ASCII paths. At startup, a file without the comments (from
an older version) is written again in the new format. `settings.example.ini` is
the same text with the defaults plus a short note at the top; a test fails if
they drift apart, so when you add or change a setting, update the template,
`DefaultSettings()`, `LoadSettings()` and the example file together.

The tests patch the app before running it: startup (`Main()`) is removed, the
settings window is created hidden and `SendInput`, `Run`, `Download`,
`Set*LockState`, `GlassToast` and `MsgBox` are replaced by stubs. `run-tests.ps1`
refuses to run if one of those patches no longer applies, so renaming those calls
means updating the patch list too.

## How the hook works

A single `WH_KEYBOARD_LL` hook (`KeyboardProc`). For every event:

1. `nCode != 0` → pass. Read `vk`, `sc | ((flags & 1) << 8)` (scan code with the
   extended bit, as shown in AutoHotkey's Key History), `flags`.
2. **Injected** (`flags & 0x10`) → pass. That's our own `SendInput` and lock-key
   toggles; without this a remap could loop.
3. **Swallowed key-ups**: the key-up (and auto-repeats) of a key whose key-down we
   ate is eaten too, otherwise Windows would get an unpaired key-up. Entries go
   stale after `REPEAT_MS` without events, so a missed key-up can't eat a later,
   normal key press.
4. **Detection mode** (settings window listening) → handled by `CaptureKey`.
5. **Modifiers** are tracked in `HELD` by the hook itself (see hardware facts).
   The fake Left Ctrl that AltGr sends (scan code `0x21D`) is ignored.
6. **Paused** → pass.
7. **Keys already being handled** (`PRESS`): a key-up ends the press; a key-down
   within `REPEAT_MS` of the previous one is auto-repeat.
8. **Launcher**: key matches `LaunchVK/SC` and the held modifiers are exactly the
   required set (`LaunchModsHeld` first drops modifiers that `GetKeyState(…, "P")`
   says are up — missed key-ups).
9. **Remap**: key matches the source (`MatchSC` decides whether the scan code must
   match). Always swallowed, so Windows and the vendor software never see it.
10. Otherwise pass.

Rules:

- **Nothing heavy inside the hook.** Actions are pushed to `QUEUE` and run by
  `RunQueue` on a `SetTimer(…, -1)`, which keeps their order. GUI updates from the
  detector also go through a timer (`CaptureDone`).
- **Windows silently removes a low-level hook that doesn't answer in time**
  (`LowLevelHooksTimeout`), and nothing tells the app. AutoHotkey is single
  threaded, so anything slow on the main thread (the Apps-folder lookup, `Run`)
  can cause it. `HookInstall()` creates a new hook before removing the old one and
  is called after those operations, after unlocking, when the display turns on
  and after resuming from sleep.
- `REPEAT_MS` is 1500 ms: it must be longer than the slowest Windows repeat delay
  (1 s). With 500 ms the first auto-repeat could arrive after the window and
  toggle Num Lock a second time.
- `Mode=Key` without modifiers is a real remap (`{Blind}{vkXXscYYY down}` /
  `up`), so holding repeats and Shift+source gives Shift+target. Except for a
  lock key (Num, Caps, Scroll Lock: `RT.noRepeat`), whose auto-repeat is eaten so
  holding toggles it once. With modifiers, the whole combo is sent on every
  key-down. There used to be separate "toggle Num/Caps/Scroll Lock" modes; they
  were the same thing with more options to choose from, so they're gone, and
  `LoadSettings` turns an old `Mode=NumLock` into `Mode=Key` with Num Lock.
- Changing settings or pausing while a key is held calls `ReleasePresses()`: it
  sends the key-up of a held target key and marks the physical key-up to be eaten.

### Key detector

- Modifier key-down → remembered and swallowed.
- Non-modifier key-down → finishes with the held modifiers (ignored for the key to
  remap).
- Modifier key-up with nothing else pressed → that modifier is the key, so keys
  like Right Ctrl can be remapped.
- Key-ups of keys pressed *before* listening started are let through (e.g. the
  Enter that clicked the button).
- On finish or cancel, every key still held is added to the swallow list.
- It runs before the rules and even while paused, so the NitroSense key itself can
  be detected. 10 s timeout; clicking the button again cancels.

## The settings window

- **Layout**: Windows 11 Settings style. A sidebar with sections (`PAGES`), a page
  title, and setting cards: each row has a title, an optional description (also
  used for the current value, e.g. a key's codes, or for what's missing, in red)
  and the control on the right. `SL` holds the layout in logical pixels.
- **Changes apply at once** (`CommitDraft`): the window edits `DRAFT`; each change
  is validated and, if complete, copied to `CFG`, saved and applied. If something
  blocks it (e.g. *Works as another key* without a key), the row says so and the
  previous settings stay active. Restart and Exit are red buttons in *General*
  (no confirmation); Reset in *Advanced* asks first, because it loses settings.
- **Drawing**: standard Win32 controls can't draw rounded cards, buttons with
  states, keycaps, switches or the sidebar, so those are GDI+ bitmaps (reusing the
  toast library's helpers). The cards of the current section are one bitmap
  painted on `WM_ERASEBKGND`. Everything clickable is a **widget** (`UiWidget`):
  a Picture control (`SS_BITMAP | SS_NOTIFY`) redrawn by `RenderWidget` for each
  state: buttons (normal, `danger`, `accent`), drop-down lists (`select`),
  switches, sidebar entries, keycap views, the About card and its link rows.
  Bitmaps are opaque (drawn on their background color), so ClearType works.
- **Drop-down lists and ⓘ bubbles are our own** (Windows' list is always white
  and square, its tooltip yellowish, neither matched the window). A closed list
  (`NewList`, kind `select`) is drawn like a button with a chevron; `.Value` is
  the chosen item and `onChange(widget)` runs when it changes. Clicking it opens
  `OpenSelect`: a layered popup owned by the settings window (`PopupWindow`,
  never activated), drawn once per state with GDI+ (`PopupCard`: soft shadow,
  rounded card, hairline border; hover pill, accent bar on the chosen item),
  sliding in while it fades (150 ms). It holds the mouse capture: the captured
  `WM_MOUSEMOVE`/`WM_LBUTTONDOWN`/`UP` go to `SelectMouse` (a click outside
  closes it, release over an item chooses it), `WM_KEYDOWN` reaches
  `OnSettingsKey` (arrows, Home/End, Enter/Space choose, anything else closes),
  and `WM_CAPTURECHANGED` / `WM_ACTIVATEAPP` close it. It opens above the
  control if there's no room below. The ⓘ bubble (`ShowInfoTip`) is the same
  kind of popup, click-through, under the ⓘ and inside the window when it fits,
  closed when the mouse leaves the ⓘ (`CheckInfoTip`). Both are in physical
  pixels (PMv2 context), like the notice. Careful with names: the globals are
  `SEL` and `TIP`, so no local `sel`/`tip` (pitfall 18).
  Icons come from *Segoe Fluent Icons* (Windows 11) or *Segoe MDL2 Assets*
  (Windows 10).
- **Widgets and the mouse**: `WM_LBUTTONDOWN` on a widget presses it and captures
  the mouse; `WM_LBUTTONUP` releases it and runs its action only if the mouse is
  still over it (`InClient`), from a timer, not inside the message handler, like
  a real button. `WM_MOUSEMOVE` sets the hovered widget (`SetHot`), and a 50 ms
  timer (`CheckHot`) notices when the mouse left the window or a press got lost.
  `WM_SETCURSOR` reaches the window for its child controls: it returns the hand
  cursor for enabled widgets and ⓘ icons. A widget's bitmap is set with
  `STM_SETIMAGE` directly (3x faster than `.Value`); the static control keeps its
  own copy of a bitmap with alpha, so whatever isn't in use is freed (`Draw`,
  `Free`).
- **Animations**: a widget animates its `pos` (`Animate`, `AnimTick`, ease-out
  with overshoot): a switch's knob slides (and the color fades), the selected
  section's accent bar grows in. Buttons have a darker "lip" and sink onto it while
  pressed; keycaps too; the switch knob grows on hover and stretches while pressed.
  A frame costs under 1 ms. Skipped when Windows' animation effects are off
  (`SPI_GETCLIENTAREAANIMATION`).
- **No flicker, no cut**: changing many controls at once (switching sections, a
  DPI change, the *Sends* row appearing) happens inside `Freeze()`, which stops
  painting with `WM_SETREDRAW`. Then `Flip()` composes the whole client area
  off-screen (`ComposeWindow`: the background bitmap, then each visible control
  printed with `WM_PRINT` into a bitmap of its own and copied to its place),
  turns painting back on, copies the image in one `BitBlt` and validates
  everything so nothing repaints piece by piece. (Windows' drop-down lists
  didn't print their text, which needed special cases; ours are widgets.)
  Repainting control by
  control on screen (`RedrawWindow`) let DWM show half-painted frames at 180 Hz:
  a visible "cut". `PrintWindow` isn't used: it clips to the window's current
  size.
- **Moving to a monitor with another scale** (`OnSettingsDpiChanged`): laying
  everything out again takes ~45 ms, which stalled the window in the middle of
  the drag. Like Chromium, the window takes the new size at once showing its
  current picture scaled (`StretchToNewSize`; the picture is composed with
  `ComposeWindow`, because reading it from the window while it moves between
  monitors gave a broken mix), and the real layout is done when
  the drag ends (`WM_EXITSIZEMOVE` → `ApplyPendingDpi` → `Flip`), or right away
  if the window wasn't dragged. Meanwhile the controls are hidden and the window
  paints the scaled picture as its background (`OnSettingsErase`): Windows makes
  every control repaint after a DPI change, and they did it at their old places
  on top of the picture. `SWP_NOCOPYBITS`, or Windows copies the old pixels back
  over the scaled picture. Hover and animations wait meanwhile. The monitors
  don't line up, so part of the window can be outside every screen while it
  crosses: on every `WM_MOVE` the scaled picture is invalidated again, so no
  stale pixels show when that part comes back. `WS_EX_COMPOSITED` was not used:
  it fights DWM and makes child windows sluggish ([Raymond
  Chen](https://devblogs.microsoft.com/oldnewthing/20171018-00/?p=97245)).
  Only while the window is visible: `WM_SETREDRAW` on a hidden window would show
  it. Controls of the other sections
  are created hidden, and a hidden widget is only marked `dirty` and drawn when its
  section is shown. Text colors go through `SetColor`, which remembers them, so a
  DPI change can re-apply fonts without losing the color.
- **Per-monitor DPI**: the app is system-DPI-aware, so on a monitor with another
  scale Windows stretched the window (blurry) and misplaced the menus. The
  settings window is created in a **Per-Monitor v2** thread context with
  `-DPIScale`; every control goes through `Place()`, which scales positions
  (`Px`) and font sizes (`FontPts`: AutoHotkey sizes fonts for the main
  monitor's DPI, so points are converted) and remembers the control. On
  `WM_DPICHANGED` (`OnSettingsDpiChanged`) only the sidebar and the visible
  section are laid out again (`LayoutPage`, one `DeferWindowPos` batch); the other
  sections when they're shown (`UI.laidOut`). Then the window takes the size
  Windows suggests and is painted once. Measured: ~150 ms down to ~40 ms; switching
  sections ~55 ms with flicker down to ~20 ms in one paint. A `WM_DPICHANGED` for
  the DPI the window already uses (it's created on the main monitor, then shown on
  another) is ignored, or the window would shrink. The tray menu and the popups
  (lists, ⓘ bubbles, notices) are shown with the thread temporarily in PMv2
  (`PMv2()`), at physical coordinates.
- **Reading positions**: a system-aware thread asking for the position of a PMv2
  window gets coordinates "virtualized" for its own DPI. Always switch to PMv2
  (`PMv2()`) before `WinGetPos`/`GetPos` on the settings window.
- **Light/dark**: `Theme=System` reads `AppsUseLightTheme`. Dark mode uses the
  undocumented but widely used uxtheme exports (ordinals 135
  `SetPreferredAppMode`, 136 `FlushMenuThemes`) for the tray menu, and
  `DwmSetWindowAttribute` 20 (dark title bar) / 35 (caption color, Windows 11).
  Everything else uses the colors in `THEMES`. The light theme is a mid grey
  with a hint of blue (window `C8CDD3`, cards `D5D9DE`), not white: easier on the eyes; the
  solid notification (`GT_THEMES.solidLight`) uses the same colors. When the
  theme changes, the window is rebuilt in place.
- Widgets are clickable but not reachable with Tab; Esc works as usual.

## One copy at a time, restart, hidden tray icon

- `#SingleInstance Off`: at startup the app looks for a hidden AutoHotkey main
  window titled exactly `Windows 11 Key Remapper` (it renames its own; up to
  0.5.2 the title was `Win11KeyRemapper.Instance`, still recognized). If another
  copy exists, it posts it a registered message ("open your settings") and exits.
  That is how users reach the settings when the tray icon is hidden, and it also
  stops a source copy and an exe copy from running two hooks. The title is the
  app's name because Windows shows it when it lists the app at shutdown.
- *Restart* (and an update) starts the app again with `--restart <old pid>`: the
  new copy waits for the old one to exit before installing its hook, and skips the
  "already running" check.

## Shutdown

Windows sends `WM_QUERYENDSESSION` to every top-level window, then
`WM_ENDSESSION`; AutoHotkey runs `ExitApp` on the second one. An app that
doesn't answer within a few seconds is listed as "preventing shutdown" under its
window title. The app handles both messages (`OnQueryEndSession`,
`OnEndSession`): it answers at once, sets `ENDING`, stops the update check in
progress and the timers that start work (notifications, update checks, hook
reinstalls), and starts nothing new until the session ends, or carries on if
another app cancelled the shutdown.

Measured by sending both messages to a running copy: ~20 ms to answer, ~30 ms
to exit, also while a notification is being built (~60 ms). While another app
blocks a shutdown, Windows lists every app still open, so seeing this one in
the list doesn't mean it's the one blocking; the developer log shows when each
message arrived.

## Developer log

*Settings* → *Advanced* → *Developer* → *Write a log* (`Log=1`), off by default.
`Log()` appends one timestamped line per event to `Win11KeyRemapper.log` next to
`settings.ini`: start (versions, path, monitors), settings changes, hook
installs, the remapped key's actions, the app shortcut, notifications (with the
time to build them), notices that warn, session lock/unlock, display, sleep,
update checks, the settings window (with build/layout times), shutdown messages,
exit, and unexpected errors (`OnError`). Each line is written at once (a crash
or a forced shutdown keeps everything up to it) and costs ~0.2–0.4 ms; at 1 MB
the file becomes `Win11KeyRemapper.old.log`. Rules: never log inside the
keyboard hook, and never log keys the user types (only the configured target
that the app sends).

## Updates

- `CheckUpdates()` asks `api.github.com/repos/.../releases/latest` with
  `WinHttp.WinHttpRequest` in **async** mode and polls it with a timer: a blocking
  request would stall the keyboard hook. Automatic checks run 1 minute after
  startup and then every 24 h (`CheckUpdates=1`).
- The JSON is read with three regexes (`tag_name`, the release `html_url`, the
  `browser_download_url` of the zip and of `SHA256SUMS.txt`). Version comparison
  is numeric (`VersionNewer`).
- *Install vX* (one click, no questions; the zip and the installed app alike):
  `Download()` the zip and `SHA256SUMS.txt` to `%TEMP%\Win11KeyRemapper-update`
  (blocking, but the user asked for it; the hook is reinstalled right after),
  check the zip's SHA-256 (`BCryptHash`), unzip with `Shell.Application`
  (`UnzipTo`), then `ApplyUpdate` copies every file over this copy: unchanged
  files are skipped, replaced ones are backed up first and everything is put
  back if one copy fails. The running `Win11KeyRemapper.exe` is renamed to
  `.old` (Windows allows renaming a running exe) and deleted at the next start.
  `settings.ini` and the log aren't in the zip, so they stay. Then
  `--restart <pid> --updated` with the (new) runtime and exit; the new start
  writes `DisplayVersion` in the Installed apps entry if it's the installed
  copy. Only the AutoHotkey runtime runs, so Smart App Control has nothing new
  to judge. A local project (`DEV_COPY`) or a folder it can't write to gets
  *Download vX* instead, which opens the release page (`CanInstallUpdate`).
- Measured end to end (a copy claiming 0.5.0 updating to the real 0.5.5): check
  ~0.5 s, download + check + unzip + copy ~2 s, restart ~0.1 s.
- The release assets' names are part of this contract: `Win11KeyRemapper-v*.zip`
  (with `src\Win11KeyRemapper.ahk` inside) and `SHA256SUMS.txt` listing it.

## Notifications

- **System notifications** (`SystemToast`): updates found by the daily check,
  pause/resume from the tray, the startup/unlock one (`StatusToast`).
  `ToastWhen=Never` turns them all off except warnings (`kind = "warn"`), which
  need the user (e.g. *App not found* after the NitroSense shortcut).
- **Notices inside the settings window** (`Notice`): whatever the user just did
  there: "*Theme: Dark* · Saved", the answer of *Check now*, errors. A separate
  component on purpose, not a mode of `GlassToast`: its own small window, state
  (`NT`) and timer, so a notice and a notification never replace each other and
  the notifications setting can't leak into it. A small solid pill (40 px high)
  in the window's colors, drawn once, at the bottom center of the window, rising
  a little while fading in; click-through (`WS_EX_TRANSPARENT`), so it can't be
  clicked away; owned by the window, so it stays above it and closes with it;
  `WM_MOVE` → `NoticeFollow` keeps it in place. With the window closed, a notice
  becomes a system notification (and follows `ToastWhen`).
- Message boxes (Reset, install an update) are created in a PMv2 thread context
  (`Dialog`), or Windows stretches them on a monitor with another scale (blurry).
- *Restart* from the settings window starts the new copy with
  `--settings <section> <x> <y>`: it reopens the window where it was.


`GTCFG.position` (`TopCenter`, `TopRight`, `TopLeft`, `BottomCenter`,
`BottomRight`, `BottomLeft`) and `GTCFG.animation` (`Slide`, `Fade`, `None`) are
and `GTCFG.glass` (`ToastTransparency`) are read when each toast is built. Without
glass the card is solid, in the settings window's colors (`GTCFG.solidTheme`:
the app's theme, or Windows' app mode for *System*), and nothing is captured.
`GT_Placement` computes the resting position and
where the toast comes from: *Slide* enters from the top edge (top center), rises a
little (bottom center, so it doesn't cross the taskbar), or comes in from the side
(left/right positions); *Fade* and *None* stay in place. The glass capture is
clamped to the monitor. The settings window's test button builds a toast with the
draft's style and restores `GTCFG` afterwards.

## Hard-won facts about the hardware (Acer Nitro V 16S AI, ANV16S-41)

- The NitroSense key reports **VK `0xFF`, SC `0x175`**. Other Acer keys share
  VK `0xFF`: **Win Lock on (Fn+Win) = SC `0x159`**, **Win Lock off = SC `0x162`**.
  Matching by VK only made Win Lock toggle Num Lock. Hence `MatchSC=1`.
- In early tests the key seemed to report SC `0x145` sometimes. That was almost
  certainly the Num Lock key (`VK 90 SC 145`) injected by the script itself.
- AutoHotkey hotkeys on the raw scan code (`$sc175::`) gave double toggles and are
  fragile → the DllCall hook.
- Returning `1` for the key is required: if Acer's software also handles it, Num
  Lock toggles twice.
- `GetKeyState()` for Ctrl/Alt is unreliable while an elevated window (Task
  Manager) has the focus (UIPI), in both logical and physical mode → modifiers are
  tracked in the hook. Even so, a non-elevated hook simply doesn't receive keys
  while an elevated window is focused. **Accepted limitation.** Do not add
  self-elevation or a "run with highest privileges" scheduled task: self-elevation
  broke autostart because the UAC prompt can't be answered at logon.
- Acer Quick Access (`QAAdmin`) shows its own Caps/Num Lock overlay. NitroSense
  needs Quick Access, so it can't be removed. Out of scope.
- **Autostart:** a shortcut in `shell:startup` pointing to the `.ahk` did **not**
  start at logon (the `.ahk` association isn't ready yet). The shortcut must run
  `AutoHotkey64.exe "script.ahk"`, or the compiled exe. `SetAutostart()` does that
  and recreates the shortcut on every launch, in case the app was moved.
- NitroSense's desktop install lives in
  `%ProgramFiles%\NitroSense\Prerequisites\NitroSenseLauncher.exe` on the test
  laptop. The Store version is found through `shell:AppsFolder`.

## AutoHotkey v2 pitfalls already hit here

1. **Variable names are case-insensitive.** `S` (DPI scale) and `s` (a parameter)
   were the same variable, so the toast icon was scaled by the DPI and overflowed.
   Never use pairs like `S/s`, `W/w`, `H/h`, `B/b`, `R/r` in one function — and
   don't name a local like a global (`held` *is* `HELD`).
2. **Reserved words** can't be variables: `is`, `in`, `and`, `or`, `not`,
   `contains`, `super`, `unset`, `this`.
3. **`DllCall("lib\Func")` unloads the DLL after the call if it wasn't loaded.**
   Handles from `pdh`, `winmm` (`timeBeginPeriod`), `wtsapi32` and `gdiplus` broke
   until `DllCall("LoadLibrary", …)` was added at startup.
4. **Timers can interrupt other threads between lines.** Use `Critical` in hook
   callbacks and animation steps; when swapping resources (like the hook), create
   the new one before freeing the old one.
5. **No heavy or GUI work inside the low-level hook** (see above).
6. **Closures capturing loop variables / nested closures** didn't fire reliably for
   the old Gui toast → toast state lives in a global object (`GT`).
7. **Default parameter values must be literals** in v2.0 (`mods := []` is a syntax
   error; use `0` and replace it inside).
8. **DPI:** the app is system-DPI-aware. The toast switches the thread to
   Per-Monitor v2 (`SetThreadDpiAwarenessContext(-4)`) only while building and
   animating, then restores it; otherwise the screen capture on a monitor with a
   different scale came out black. Don't make the whole thread PMv2: the settings
   window would break on the second monitor.
9. In Git Bash, `/ErrorStdOut` and `/Validate` get converted to paths
   (`C:/Program Files/Git/ErrorStdOut`). Call AutoHotkey from PowerShell or cmd.
10. **`switch` is a keyword**: a function can't be called `Switch()`.
11. **`try` without braces inside `if … else`** makes `else` attach to the `try`
    ("Unexpected Else"). Use braces.
12. **COM booleans are -1** (`VARIANT_TRUE`): don't use -1 as an error marker for
    a COM call's result.
13. **A parameter can't share a global's name, in any case**: `SetPaused(paused)`
    with `global PAUSED` is a load error.
14. **Picture controls**: `*w32 *h32 file` only works when *changing* the image
    (`.Value`); when creating it, put the size in the options. `SetFont` isn't
    supported on pictures.
15. **PowerShell `Start-Process -PassThru`**: read `.Handle` right away and call
    `WaitForExit()` without a timeout at the end, or `ExitCode` stays empty.
16. **Tests must never show a dialog**: `tests.ahk` sets `OnError` to print the
    error and exit, and `run-tests.ps1` kills the run after 90 s. Never start
    `AutoHotkey64.exe` without a script either: it shows "Script file not found".
17. **Checking what's really on screen**: an off-screen window (x -32000) has an
    empty clip region, so nothing drawn into its DC lands anywhere, and
    `PrintWindow` re-renders the window instead of returning what's shown. To
    test drawing code, show the window on screen but cloaked
    (`DwmSetWindowAttribute` 13) and read its surface with `BitBlt` from
    `GetDCEx(hwnd, 0, DCX_CACHE)`.
18. **Functions and variables share one namespace**: a local named like a function
    (`animate` next to an `Animate()` function) hides it in that function. Same for
    globals at the top level of a script (`links` *is* `LINKS`).

## The glass toast

Design (user preferences): rounded card, not a pill; concentric icon tile (icon
radius = card radius − margin); glass = blurred capture of what's behind
(blur 60, saturation 1.3) with a tint per theme; light/dark theme from the
background's luminance (the light theme uses softer colors). By default it slides
down from the top center of the monitor under the mouse with a small overshoot,
holds, and slides up while fading; position and animation are configurable (see
*Notifications* above). Click dismisses it with the same animation.

Shown at startup, on session unlock (`WTS_SESSION_UNLOCK`) and when the display
turns back on without a password (`GUID_CONSOLE_DISPLAY_STATE` 0 → 1, only if the
session isn't locked, so it never shows twice). Hidden on lock / display off.

Performance (measured with a telemetry build before optimizing):

- The cost came from redrawing the shadow every frame, blurring at full
  resolution, and recomposing/re-uploading the bitmap every frame.
- Now it draws **once**, frees every GDI+ object (and calls `GdiplusShutdown`),
  then only moves/fades the layered window with `UpdateLayeredWindow` **without a
  bitmap** (`hdcSrc = NULL`). dwm.exe GPU use went back to idle.
- AutoHotkey timers can't go below ~15.6 ms even with `timeBeginPeriod(1)` → about
  60 fps. A custom loop was rejected (risky next to the hook). `timeBeginPeriod`
  is only active while animating.
- A "live" glass (recapturing every 40 ms) was tried and rejected: choppy at
  180 Hz and +13 % CPU.

## Things tried and rejected

- Hotkeys on the scan code (`$sc145::`, `$sc175::`) with `Send "{NumLock}"`:
  double toggles, fragile.
- Self-elevation at startup: broke autostart (UAC at logon).
- Matching only VK `0xFF`: caught Win Lock.
- A separate key-probe tool: annoying and filled the screen → the detector lives
  in the settings window.
- No auto-repeat filter: holding the key toggled many times.

## Manual test checklist

The tests cover the logic; this needs real keys:

- [ ] NitroSense key → Num Lock toggles once per press, also when held; Caps Lock too.
- [ ] Win Lock (Fn+Win) still works and doesn't touch Num Lock.
- [ ] Right Ctrl + NitroSense key opens NitroSense; Left Ctrl + key toggles Num Lock.
- [ ] *Change…* captures a single key, a combo, and a lone modifier (Right Ctrl);
  Right Ctrl + Num Lock is captured as that, not as Pause.
- [ ] *What it does*: *Does nothing* / *Works as usual* hide the *Sends* row.
- [ ] Drop-down lists: open under the control (above it near the bottom of the
  screen), hover, click an item, click outside, arrows + Enter, Esc; light and
  dark; on both monitors.
- [ ] `Mode=Key`: holding the key repeats the target; Shift+key gives Shift+target.
- [ ] Changes apply at once without restarting; incomplete ones (no key to send) show a red hint.
- [ ] Every section of the settings window; changes apply at once; the ⓘ bubbles.
- [ ] Switching sections doesn't flicker; the accent bar grows in.
- [ ] Hover and press: buttons sink onto their lip, switches slide, the hand cursor
  shows over everything clickable; releasing outside a button does nothing.
- [ ] Move the settings window to the other monitor and back while dragging: it
  follows the mouse without stalling, shows a scaled picture (never a mix of
  old and new) and gets sharp, with everything in place, when dropped.
- [ ] Tray menu (Settings, Pause, Restart, Exit) on each monitor: opens at the icon, at the right size.
- [ ] Every change in the settings window shows a notice inside it, from the
  bottom; clicking it does nothing; it moves with the window. With *Show
  notifications* = *Never*, nothing appears on the desktop (only warnings).
- [ ] *Restart* from the settings window reopens it in the same section and place.
- [ ] Reset's question and *Browse…* are sharp on the 125 % monitor.
- [ ] *General*: *Restart* and *Exit* (red, no confirmation); *About*: the card
  opens the GitHub page, the rows open the FAQ and the issue forms.
- [ ] Light, dark and *System* themes; switching Windows' mode with the window open.
- [ ] Every notification position and animation, with *Show a test*; *Show notifications*:
  Always / Only when the app starts / Never (lock and unlock to check);
  *Transparency effects* off: a solid card, light or dark like the window.
- [ ] Pause / resume and *Restart* from the tray.
- [ ] Hide the tray icon, open the app again: the settings appear; turn it back on.
- [ ] *Check now* (up to date / update available); *Install* updates and restarts the
  app with the settings kept (a local project shows *Download*, which opens the page).
- [ ] Start with Windows: sign out and in, the app starts.
- [ ] *Advanced* → *Write a log* on; use the app, shut down and start again:
  the log shows "Windows asks to end the session", "Exit (Shutdown…)" and the
  new start. *Open* shows it; off again stops it.
- [ ] Toast at startup, after unlock (Win+L) and after the display turns off/on.
- [ ] Toast on a second monitor with a different scale isn't black.
- [ ] Settings window on both monitors looks right.
- [ ] *Advanced* → *Export…* then *Import…* (also a file that isn't a settings file:
  refused).
- [ ] The release zip: double-click `Win11KeyRemapper.exe`, the app starts; *Start with
  Windows* points to it. *General* → *Uninstall…*: No / Yes to the settings.

## Releasing

1. Bump the version in `src/Win11KeyRemapper.ahk` (`APP.version` **and**
   `;@Ahk2Exe-SetVersion`, the workflow checks they match), and in
   `CHANGELOG.md` replace "Unreleased" with the date.
2. Commit, then tag and push: `git tag v0.5.5` and `git push origin v0.5.5`.
3. The workflow refuses a tag that doesn't match the version, checks, tests,
   builds the release folder (below), zips it, builds the installer, runs
   `tools/smoke-test.ps1` (the zip's exe starts the app; silent install, the
   installed app starts, uninstall keeps only `settings.ini`; with
   `--delete-settings` nothing is left), signs the installer if SignPath is set
   up (you approve it on signpath.io while the job waits), writes
   `SHA256SUMS.txt`, creates the release as a draft with install notes and
   publishes it (that order also works with immutable releases).
4. Running copies find the new version within a day (or with *Check now*) and
   *Download* opens the release page.

## The release: a runtime instead of an exe

A compiled script (Ahk2Exe: the AutoHotkey runtime with the script inside) is
an unsigned exe nobody knows, and **Windows 11's Smart App Control blocks those**
with no *Run anyway*; v0.5.0 shipped one and it didn't open on the author's
laptop. `AutoHotkey64.exe` isn't signed either, but Windows knows it: tested
under Smart App Control (2026-10-25) with the 2.0.28 and 2.0.31 runtimes from
AutoHotkey's GitHub releases, renamed and marked as downloaded (Zone 3), both
ran, even 2.0.31 published that same day. So the release folder is:

```
Win11KeyRemapper.exe       AutoHotkey64.exe, unmodified, renamed (AHK_VERSION in the workflow)
Win11KeyRemapper.ahk       package/Win11KeyRemapper.ahk: the launcher
AutoHotkey-license.txt     the runtime's GPL v2 license (it's redistributed)
src\Win11KeyRemapper.ahk   the app; settings.ini is created here
src\lib\GlassToast.ahk
assets\icon.ico            the app's icon (..\assets from src\)
README.md, LICENSE, CHANGELOG.md, settings.example.ini, SUPPORT.md, SECURITY.md, docs\FAQ.md, docs\TESTED-MODELS.md
```

Run without a script, AutoHotkey runs the `.ahk` with its own name, so
double-clicking `Win11KeyRemapper.exe` runs the launcher, which starts
`src\Win11KeyRemapper.ahk` with the same runtime. `A_AhkPath` is then that exe,
so *Start with Windows* points to it. `PACKAGE_FILES` in the app must list
exactly these files (the workflow fails otherwise): the uninstall deletes them.
Bumping `AHK_VERSION`: test the new runtime under Smart App Control first.

The exe's icon is AutoHotkey's (changing it would modify the binary); the tray
and the windows use the app's icon.

## The installer and the uninstall

`installer/Win11KeyRemapper.iss` (Inno Setup 7): the same folder, per user, in
`%LOCALAPPDATA%\Programs\Win11KeyRemapper`, no admin; a Start menu shortcut
(optional desktop one) that runs `Win11KeyRemapper.exe src\Win11KeyRemapper.ahk`;
it closes a running copy first (`WM_COMMAND 65307` to the hidden `Windows 11 Key
Remapper` window, or `Win11KeyRemapper.Instance` up to 0.5.2).

**No Inno uninstaller** (`Uninstallable=no`): `unins000.exe` is written on the
user's PC, unsigned, and Smart App Control would block it, leaving the app
impossible to uninstall. The installer writes the *Installed apps* entry itself
(`HKCU\...\Uninstall\Win11KeyRemapper`) with
`UninstallString = Win11KeyRemapper.exe src\Win11KeyRemapper.ahk --uninstall`:
the app uninstalls itself (`UninstallApp`), and so does Settings → *General* →
*Uninstall…* for the zip. It asks to confirm and whether to delete the settings
(`--quiet` skips the questions and keeps them, `--delete-settings` deletes
them), closes a running copy, deletes the `PACKAGE_FILES`, the startup, Start
menu and desktop shortcuts, the log, an update download, the entry, and empty
folders; a hidden `cmd` deletes the running exe and the remaining folders once
the app has exited. A git checkout is refused (it would delete the source).

`DEV_COPY` is true when the folder above `src\` has a `.git` (a folder, or a
file in a git worktree): the settings window then says "Local project" (title,
sidebar, version row) and uninstalling is refused. `CopyKind()` tells how the
copy is set up — `dev`, `installed` (the Installed apps entry points to this
folder), `zip` (run by its own `Win11KeyRemapper.exe`) or `script` — and which
AutoHotkey runs it; Settings → *Updates* → *This copy* and the log's first line
show it.

## Code signing (SignPath Foundation)

Free for open-source projects; the certificate is issued to "SignPath
Foundation". Their rules that matter here: only binaries built from the
project's own source in CI are signed (so the installer, not the AutoHotkey
runtime, which goes inside it unmodified), every signing request is approved by
hand, MFA for every team member, a *Code signing policy* section on the home
page (the README has it) with the attribution wording, team roles and a privacy
statement, product name and version in the signed file's metadata (the
installer's `VersionInfo*`).

Setting it up, once the project is accepted:

1. Repository secret `SIGNPATH_API_TOKEN` (a SignPath CI user's API token) and
   repository variables `SIGNPATH_ORGANIZATION_ID`, `SIGNPATH_PROJECT_SLUG`,
   `SIGNPATH_POLICY_SLUG` (from the SignPath project).
2. In SignPath, GitHub as the trusted build system for the project, and an
   artifact configuration for a single `Win11KeyRemapper-Setup-v*.exe`
   (Authenticode).
3. That's all: the workflow's signing steps only run when the secret exists.
   Until then the installer is published unsigned, as a preview.
## Ideas for later

Multiple remap rules, Spanish UI (and README), a community model list.
