# ❓ Frequently asked questions

[← Back to the README](../README.md)

**Installing and running**

- [Why do I need AutoHotkey? Is there an exe?](#why-no-exe)
- [My antivirus warns about it](#antivirus)
- [Where are my settings? Can I edit them by hand?](#settings)

**Using it**

- [It doesn't work while Task Manager is focused](#task-manager)
- [What does *Exact key match* do?](#exact-key-match)
- [I hid the tray icon. How do I open the settings?](#hidden-tray-icon)
- [The Acer Num Lock / Caps Lock pop-up still shows](#acer-pop-up)
- [Does it work on other laptops or keyboards?](#other-keyboards)
- [The notification stutters on my old or low-power PC](#stutter)
- [Windows says the app is preventing shutdown](#shutdown)
- [Something odd happened. How do I see what the app did?](#log)

**Privacy and internals**

- [Does it connect to the internet?](#internet)
- [How does it work?](#how-it-works)

Not here? [Ask a question](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/issues/new?template=question.yml).

---

## Installing and running

<a name="why-no-exe"></a>
### Why do I need AutoHotkey? Is there an exe?

Not for now. An exe made from an AutoHotkey script isn't code-signed, and
Windows 11's *Smart App Control* blocks unsigned apps it doesn't know, with no
*Run anyway* button (turning it off affects the whole PC, and often can't be
undone without reinstalling Windows). AutoHotkey itself is signed, so the script
runs everywhere, and you can read exactly what it does.

A standalone installer is on the way: a signed exe that doesn't need AutoHotkey,
installs with a double-click and updates itself. It needs a code-signing
certificate first (free programs for open-source projects exist, but they take
some steps).

<a name="antivirus"></a>
### My antivirus warns about it

This app installs a keyboard hook, which is also what keyloggers do, so a
heuristic scanner may flag it. It's a false positive: the whole app is the
readable script in `src\`, it never stores or sends your keys (see
[SECURITY.md](../SECURITY.md)), and every release has a `SHA256SUMS.txt` you can
compare with `Get-FileHash` on the zip you downloaded.

<a name="settings"></a>
### Where are my settings? Can I edit them by hand?

In `src\settings.ini`, next to `Win11KeyRemapper.ahk` (or in
`%APPDATA%\Win11KeyRemapper\settings.ini` when that folder isn't writable).
Settings → *Advanced* → *Open folder* takes you there.

Every option is explained inside the file, and
[`settings.example.ini`](../settings.example.ini) shows them all with their
defaults. After editing it, restart the app (tray icon → *Restart*). The app
writes the file again when you change something in the settings window, so your
own comments in it are lost.

---

## Using it

<a name="task-manager"></a>
### It doesn't work while Task Manager is focused

Windows doesn't pass keystrokes to apps without admin rights while an app with
admin rights (like Task Manager) is in the foreground. That's a Windows security
rule (UIPI). This app deliberately runs without admin rights so it can start
silently at logon. Click any normal window and it works again.

<a name="exact-key-match"></a>
### What does *Exact key match* do?

Some vendor keys share the same virtual-key code. On Acer laptops, turning Win
Lock on and off (<kbd>Fn</kbd>+<kbd>Win</kbd>) sends the NitroSense key's code
(`VK FF`) with other scan codes (`159` and `162`). With *Exact key match* on (the
default), the scan code must match too, so only the NitroSense key (`175`) is
remapped and Win Lock works as usual. The switch is in Settings → *Advanced*.

<a name="hidden-tray-icon"></a>
### I hid the tray icon. How do I open the settings?

Open the app again (double-click `src\Win11KeyRemapper.ahk`). Instead of
starting a second copy, the running one shows its settings window, where you can
turn the icon back on.

<a name="acer-pop-up"></a>
### The Acer Num Lock / Caps Lock pop-up still shows

That overlay comes from Acer Quick Access, which NitroSense needs. It's outside
this app's control.

<a name="other-keyboards"></a>
### Does it work on other laptops or keyboards?

Yes, for any key that reaches Windows as a key press: open the settings, go to
*Keys*, click *Change…* next to *Key* and press it. Keys handled entirely by the
firmware (like <kbd>Fn</kbd> itself) never reach Windows and can't be remapped.

Tried it on another laptop? See [Tested models](TESTED-MODELS.md) and tell us how
it went.

<a name="stutter"></a>
### The notification stutters on my old or low-power PC

The frosted glass takes a capture of the screen behind the notification and
blurs it, each time it appears. Turn off *Transparency effects* in Settings →
*Notifications*: you get a solid card in the settings window's colors, with no
capture at all. Or set *Show notifications* to *Only when the app starts* or
*Never*.

<a name="shutdown"></a>
### Windows says the app is preventing shutdown

When one app holds up a shutdown, Windows shows a list of every app that's still
open, so this one can appear there without being the cause: it answers Windows
in a few hundredths of a second and closes right after. If you think it is the
one blocking, turn on the [developer log](#log), and after the next shutdown
look at the last lines: they show when Windows asked and when the app closed.
Then [report it](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/issues/new?template=bug_report.yml).

(Up to version 0.5.2 the app appeared in that list as
*Win11KeyRemapper.Instance*; now it's *Windows 11 Key Remapper*.)

<a name="log"></a>
### Something odd happened. How do I see what the app did?

Turn on Settings → *Advanced* → *Write a log*. From then on the app writes one
line per event, with the time, to `Win11KeyRemapper.log` next to the settings
file: when it started, settings you changed, each time the remapped key worked,
notifications, sleep, shutdown, errors… *Open* shows it in Notepad.

It never records the keys you type, each line takes a fraction of a
millisecond, and the file stays under about 2 MB, so you can leave it on. If you
attach it to an issue, have a look first: it contains folder paths.

---

## Privacy and internals

<a name="internet"></a>
### Does it connect to the internet?

Only to check for updates: once a day it asks GitHub's API for the latest
release (nothing about you or your keys is sent). Turn off *Check for updates
automatically* in Settings → *Updates* to stop it; *Check now* still works on
demand. It never downloads anything by itself: *Download* opens the release page
in your browser.

<a name="how-it-works"></a>
### How does it work?

- The NitroSense key reports virtual-key code `0xFF` ("no mapping"), which
  AutoHotkey hotkeys can't target reliably. The app installs its own low-level
  keyboard hook (`WH_KEYBOARD_LL`) and matches each key by virtual-key code
  **and** scan code (with the extended bit).

- The matched key is swallowed, so neither Windows nor the vendor software sees
  it — otherwise both would react and Num Lock would toggle twice.

- Modifiers for the launcher shortcut are tracked by the hook itself.

- The hook never does real work: actions go to a queue that runs right after,
  because Windows silently removes hooks that respond too slowly. The hook is
  also reinstalled after unlocking and after sleep.

- Key-downs that arrive while the key is still held (auto-repeat) are passed on
  as repeats of the target, except for Num, Caps and Scroll Lock, so holding the
  key toggles them once.

- The settings window is standard Win32 with custom-drawn cards, buttons,
  keycaps, switches and sidebar, aware of each monitor's scale; the notification
  is drawn once with GDI+ and then only moved and faded by the window manager, so
  it costs next to nothing.

More details in [DEVELOPMENT.md](DEVELOPMENT.md).
