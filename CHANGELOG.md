# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **No AutoHotkey to install**: the release zip has a `Win11KeyRemapper.exe` to
  double-click. It's the official AutoHotkey v2 runtime, unmodified and only
  renamed (with its license), which runs the app's script through a small
  launcher; Windows' Smart App Control lets it run.
- **Installer (preview)**: `Win11KeyRemapper-Setup` installs the same files per
  user (no admin), with a Start menu shortcut and an entry in *Installed apps*.
  It will be signed through SignPath Foundation once the project is approved;
  until then Windows may block or warn about it.
- **Uninstall** (Settings → *General* → *Uninstall…*, or *Installed apps*):
  removes the app's files, its shortcuts, its log, any update download and its
  *Installed apps* entry, and asks whether to delete the settings too.
  `--uninstall --quiet [--delete-settings]` does it without questions.
- **Export / import settings** (Settings → *Advanced*): save them to a file or
  load them on this or another PC; a file that isn't a valid settings file is
  refused without changing anything.
- README: *Code signing policy*; GitHub Actions now also checks the release end
  to end (the zip's exe starts the app, install, uninstall).

### Fixed

- SECURITY.md said `AutoHotkey64.exe` is signed: it isn't (Windows trusts it by
  reputation).

## [0.5.4] - 2026-10-20

### Changed

- **Light theme easier on the eyes**: a mid grey with a hint of blue instead of white, for
  the settings window, its notices and the solid notifications.
- **Drop-down lists of our own**, instead of Windows' white, square ones: they
  look like the app's buttons, with a chevron, and open a rounded list with a
  soft shadow that slides in, highlights the item under the mouse and marks the
  chosen one. A click outside, Esc or Alt closes it; arrows and Enter work too.
- **The ⓘ explanations** appear in a bubble in the window's colors instead of
  Windows' yellowish tooltip.
- *Action* is now *What it does*, and its choices read as states, not commands:
  *Works as another key or shortcut*, *Does nothing (disabled)*, *Works as
  usual (not remapped)*.
- README screenshots updated.

## [0.5.3] - 2026-10-20

### Added

- **Developer log** (*Settings* → *Advanced* → *Developer* → *Write a log*, off
  by default): one line per event with the time, in `Win11KeyRemapper.log` next
  to the settings file — start, settings changes, the remapped key's actions,
  notifications, updates, sleep, shutdown, errors. It never records the keys you
  type, each line takes a fraction of a millisecond, and the file stays under
  about 2 MB. *Open* shows it in Notepad. In `settings.ini`: `Log=1`.

### Changed

- Shutting down, restarting or signing out: the app answers Windows at once and
  starts nothing new (notifications, update checks) until the session ends, or
  carries on if the shutdown is cancelled. An update check in progress is
  stopped.
- The app's hidden window is now called *Windows 11 Key Remapper* instead of
  *Win11KeyRemapper.Instance*: it's the name Windows shows if it lists the app
  while shutting down.

## [0.5.2] - 2026-10-10

### Changed

- `settings.ini` explains itself: every option has a short comment above it
  with its possible values and default. A file from an older version is
  rewritten in the new format the next time the app starts (your values stay).
  `settings.example.ini` is the same file with the defaults.
- README reorganized: a short *Get started*, collapsible sections (features,
  updating, uninstalling, FAQ, help), more space between points, and *Feedback*
  and *Contributing* together. The settings table is gone: the file itself
  explains each option now. A GIF of the notification at the top; the settings
  window screenshot moved into *Features*.
- The FAQ, the tested models and the help steps have pages of their own
  (`docs/FAQ.md`, `docs/TESTED-MODELS.md`, `SUPPORT.md`), linked from a new
  *More* section in the README. The app's *About* → *Frequently asked questions*
  opens the new FAQ page.

## [0.5.1] - 2026-10-05

### Changed

- The app is now published as an AutoHotkey v2 script only: the release zip
  holds `src\Win11KeyRemapper.ahk` (double-click it, with AutoHotkey v2
  installed) and no longer an exe. Windows 11's Smart App Control blocks
  unsigned exes with no *Run anyway*, while AutoHotkey is signed. A signed exe
  that installs and updates itself is planned.
- Updating: the app still tells you about new versions; *Download* opens the
  release page and you extract the new zip over the old folder (your settings
  stay). README, FAQ, SECURITY.md and the bug form updated to match.

## [0.5.0] - 2026-10-05

First public release.

### Added

- Remap the Acer NitroSense key (VK `FF`, SC `175`) or any other key to another
  key or shortcut (Num Lock by default), or make it do nothing. When the action
  doesn't press a key, the *Sends* row disappears.
- *Exact key match* (scan code matching), so Win Lock (Fn+Win), which shares
  VK `FF`, keeps working.
- Holding the key toggles Num, Caps or Scroll Lock only once; other keys repeat
  like the real key.
- Optional shortcut to open NitroSense (default: Right Ctrl + NitroSense key),
  with auto-detection of the desktop and Microsoft Store versions, or any app
  you choose.
- Settings window in the Windows 11 style: a sidebar with General, Keys,
  Notifications, Updates, Advanced and About; setting cards with a description
  and, where useful, an ⓘ tooltip. Every change is applied and saved at once; if
  something is missing, the row says what.
- Custom-drawn buttons, switches and sidebar with hover and pressed states and
  small animations: buttons sink onto their edge when pressed, switches slide,
  the selected section's bar grows in. The hand cursor shows over everything
  clickable. Animations follow Windows' *Animation effects* setting.
- *General* → *App*: Restart and Exit buttons, in red.
- *About*: the app card opens the GitHub page; *Feedback* (works on my laptop,
  report a bug, suggest a feature) and *Help* (FAQ, ask a question).
- Built-in key detector: click "Change…" and press a key or a shortcut. Keys are
  shown as keycaps, with their codes below the row title. Ctrl + Num Lock is
  detected as that (Windows reports it as Pause).
- Light and dark mode for the settings window and the tray menu: follows
  Windows, or choose one (`Theme` setting). Switches live if Windows changes.
- Sharp on every monitor: the settings window and the tray menu follow each
  monitor's scale (Per-Monitor DPI v2), also when moved between monitors. Moving
  the window to a monitor with another scale relays out only what's visible, in
  one batch; every bigger change (switching sections, the new scale) is composed
  off-screen first and shown in one copy: no flicker, no half-drawn or black
  frames. While dragging it to another monitor, the window keeps up with the
  mouse (its picture is scaled at once) and gets sharp when you drop it.
- Message boxes (Reset, install an update) and *Browse…* are sharp on every
  monitor too.
- Notifications: when (always, only when the app starts, or never), where (top or
  bottom; center, left or right), how (slide, fade or none) and whether they're
  frosted glass or a solid card in the settings window's colors (*Transparency
  effects*, `ToastTransparency`: lighter for older or low-power PCs), with a
  preview. *Never* means no notifications on the desktop at all, except warnings.
- What you do in the settings window is confirmed inside it: a small solid
  notice rises from the bottom ("Theme: Dark · Saved", the result of *Check
  now*…), can't be clicked away and follows the window. It's independent from
  the desktop notifications: one never replaces the other.
- *Restart* from the settings window reopens it in the same section and place.
- Tray menu: Settings, Pause remapping, Restart, Exit.
- Option to hide the tray icon. Opening the app again shows the settings of the
  running copy instead of starting a second one.
- Update check: once a day (optional) or on demand. On the exe, "Install"
  downloads the release from GitHub, verifies it against `SHA256SUMS.txt`,
  replaces the exe and restarts; from source it opens the release page.
- "Start with Windows" (shortcut in the Startup folder, also when running from
  source).
- Glass-style notification at startup, after unlocking and when the display
  turns back on.
- `settings.ini` next to the exe (portable), or in `%APPDATA%\Win11KeyRemapper`
  when that folder isn't writable.
- Compiled `Win11KeyRemapper.exe` built by GitHub Actions, with SHA-256 sums
  and optional VirusTotal scan links in the release notes.

[0.5.4]: https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/tag/v0.5.4
[0.5.3]: https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/tag/v0.5.3
[0.5.2]: https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/tag/v0.5.2
[0.5.1]: https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/tag/v0.5.1
[0.5.0]: https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/tag/v0.5.0
