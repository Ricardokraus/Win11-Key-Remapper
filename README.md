<p align="center">
  <img src="assets/banner.svg" alt="Windows 11 Key Remapper - NitroSense Key Remapper" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense?color=30D158&label=release"></a>
  <a href="https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/total?color=30D158"></a>
  <img alt="Windows 10 | 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4">
  <a href="https://www.autohotkey.com/"><img alt="AutoHotkey v2" src="https://img.shields.io/badge/AutoHotkey-v2-334455?logo=autohotkey&logoColor=white"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense?color=blue"></a>
</p>

<h3 align="center">
  Keep hitting the NitroSense key instead of Num Lock or Backspace?<br>
  Turn it into Num Lock, disable it, or remap it — a small, free AutoHotkey app.
</h3>

<p align="center">
  <a href="#installation"><b>Get started</b></a> ·
  <a href="#features"><b>Features</b></a> ·
  <a href="docs/FAQ.md"><b>FAQ</b></a> ·
  <a href="SUPPORT.md"><b>Help and feedback</b></a> ·
  <a href="#more"><b>More</b></a>
</p>

On Acer Nitro laptops the **NitroSense key** sits right next to Backspace and
Num Lock. One slip and the NitroSense app pops up. **Windows 11 Key Remapper**
is a tiny tray app that gives that key a better job — or any other key you pick.

<p align="center">
  <img src="assets/KeyRemapper.gif" alt="The app's notification sliding in at the top of the screen: Key Remapper is active, NitroSense key → Num Lock">
</p>

---

<a name="installation"></a>
## 🚀 Get started

1. Download `Win11KeyRemapper-vX.Y.Z.zip` from the
   [latest release](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest)
   and extract it to a folder you'll keep, for example `Documents\Win11KeyRemapper`
   (not *Downloads*: *Start with Windows* points to wherever the app is).

2. Double-click **`Win11KeyRemapper.exe`**. Nothing to install, and you don't need
   AutoHotkey: that exe is the official AutoHotkey runtime, which runs the app's
   script ([what is it exactly?](docs/FAQ.md#why-no-exe)). It works with Windows
   11's *Smart App Control* on.

3. The settings window opens on *Keys*. Pick what the NitroSense key should do —
   changes apply at once. *Start with Windows* is already on. Close the window:
   the app lives in the tray. Double-click its icon, or open the app again, to
   come back.

> [!NOTE]
> **A signed installer is on the way** (Start menu shortcut, uninstall from
> *Installed apps*). The project is applying for free code signing from
> [SignPath Foundation](https://signpath.org/); until then, the
> `Win11KeyRemapper-Setup` file in the releases is a preview that Windows may
> block or warn about. The zip above works everywhere.

Everything is changed from the settings window. If you'd rather edit a text file,
`src\settings.ini` explains every option inside it (open it from *Settings* →
*Advanced* → *Open folder*), and [`settings.example.ini`](settings.example.ini)
shows them all with their defaults. *Advanced* → *Export…* / *Import…* saves them
to a file or loads them, on this or another PC.

Already have [AutoHotkey v2](https://www.autohotkey.com/) installed? You can also
double-click `src\Win11KeyRemapper.ahk`; it's the same app.

<a name="features"></a>
## ✨ Features

<details>
<summary><b>See all features</b></summary>
<br>

- **Remap the NitroSense key** (or any key) to another key or shortcut — **Num
  Lock** by default — or make it do nothing.

- **Holding it toggles Num Lock once** (or Caps / Scroll Lock), not over and
  over; other keys repeat like the real key.

- **Built-in key detector**: click *Change…*, press a key or a combination, done.

- **A shortcut to open NitroSense** (default: <kbd>Right Ctrl</kbd> + NitroSense
  key). It finds the app by itself, Microsoft Store version included, or opens any
  app you choose.

- **Windows 11 style settings**: a sidebar with sections, **light and dark
  mode**, changes applied at once, small animations, sharp on every monitor.

- **Notifications your way**: always (at startup, after unlocking, when the
  screen turns on), only at startup, or never; six positions, three animations,
  frosted glass or solid.

- **A tiny tray menu** (settings, pause, restart, exit), or **no tray icon** at
  all.

- **Tells you about new versions**: checks GitHub once a day (you can turn it
  off).

- **An optional log** of what the app does, for finding problems (off by
  default; it never records what you type).

- **Back up your settings**: export them to a file, import them on another PC.

- **Clean uninstall**: one click removes everything it created (it asks about
  your settings).

- **Light**: no admin rights, no driver, no service, no CPU use while idle.

- **Free and open source** (MIT).

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/screenshot-dark.png">
    <img src="assets/screenshot-light.png" alt="The settings window, Keys section: the key to remap, what it does and the shortcut that opens NitroSense" width="760">
  </picture>
</p>

</details>

<a name="updating"></a>
## 🔄 Updating and uninstalling

<details>
<summary><b>How to update</b></summary>
<br>

When there's a new version, the app tells you (*Settings* → *Updates*), and
*Download* opens the release page. Then:

1. Click *Exit* in the app (settings → *General* → *App*, or tray icon → *Exit*).

2. Download the new zip and extract it **over the same folder**, replacing the
   files. Your `settings.ini` isn't in the zip, so it stays.

3. Double-click `Win11KeyRemapper.exe` again.

</details>

<details>
<summary><b>How to uninstall</b></summary>
<br>

Settings → *General* → **Uninstall…** (or, with the installer, Windows' *Installed
apps* → *Windows 11 Key Remapper* → *Uninstall*). It removes the app's files, its
*Start with Windows* and Start menu shortcuts, its log, any update it downloaded
and its entry in *Installed apps*, and asks whether to delete your settings too
(keep them if you might install it again). Nothing else is left on your PC.

</details>

<a name="more"></a><a name="faq"></a><a name="help-and-contributing"></a>
## 📚 More

| Page | What you'll find |
|---|---|
| ❓ **[FAQ](docs/FAQ.md)** | Common questions: AutoHotkey, antivirus warnings, Task Manager, Win Lock, the settings file… |
| 💻 **[Tested models](docs/TESTED-MODELS.md)** | Laptops it works on. Tried it on yours? Tell us, even if it didn't work! |
| 💬 **[Help and feedback](SUPPORT.md)** | Report a bug, suggest an idea or ask a question, step by step. |
| 🛠️ **[Contributing](CONTRIBUTING.md)** | Help with code or docs. |
| 📜 **[Changelog](CHANGELOG.md)** | What changed in each version. |
| 🔒 **[Security](SECURITY.md)** | What the app does with your keys, and how to report a security problem privately. |

---

If the app helps you, a ⭐ helps others find it.

<a href="https://star-history.com/#Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&type=Date&theme=dark">
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense&type=Date" width="600">
  </picture>
</a>

<a name="code-signing-policy"></a>
## 🔏 Code signing policy

Releases are built from this repository by
[GitHub Actions](.github/workflows/build.yml) only; nothing is built or
uploaded by hand.

- **`Win11KeyRemapper.exe`** in the zip is the official, unmodified
  [AutoHotkey v2](https://github.com/AutoHotkey/AutoHotkey/releases) runtime
  (`AutoHotkey64.exe`, GPL v2: see `AutoHotkey-license.txt`), only renamed, as
  downloaded from AutoHotkey's GitHub releases. The app itself is the readable
  script next to it.
- **The installer** (`Win11KeyRemapper-Setup`) is built with
  [Inno Setup](https://jrsoftware.org/isinfo.php) from
  [`installer/`](installer/Win11KeyRemapper.iss). Once approved: *Free code
  signing provided by [SignPath.io](https://about.signpath.io/), certificate by
  [SignPath Foundation](https://signpath.org/)*. Until then it's unsigned.

Team roles:

- Committers and reviewers: [Ricardokraus](https://github.com/Ricardokraus)
- Approvers (every signing request): [Ricardokraus](https://github.com/Ricardokraus)

Privacy: this program will not transfer any information to other networked
systems unless specifically requested by the user or the person installing or
operating it. Its only network access is the check for a new version, a request
to GitHub's public API once a day that sends nothing about you or your keys; it
can be turned off in *Settings* → *Updates*. See [SECURITY.md](SECURITY.md).
## 📄 License

[MIT](LICENSE) © 2026 Ricardo
