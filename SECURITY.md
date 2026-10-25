# Security policy

## Supported versions

Only the [latest release](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/releases/latest)
gets fixes. The app tells you when there's a new one (Settings → *Updates* →
*Check now*); see [Updating](README.md#updating).

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Report them
privately through GitHub instead:
[**Report a vulnerability**](https://github.com/Ricardokraus/Win11-Key-Remapper-Acer-Nitrosense/security/advisories/new)
(Security tab → *Report a vulnerability*).

Include what you found, how to reproduce it and which version you used. You'll
get an answer as soon as possible; once a fix is released, the report can be
published as a security advisory with credit to you, if you want.

## What this app does that matters for security

- It installs a low-level keyboard hook (`WH_KEYBOARD_LL`) to see key presses.
  Keys are only compared against your settings; nothing you type is logged,
  stored or sent anywhere. (The optional developer log, off by default, records
  what the app does, such as "sent Num Lock", never the keys you type.)
- It runs without admin rights and never asks for elevation.
- Its only network access is the update check against GitHub's API. It never
  downloads anything by itself: a new version is downloaded from the release
  page in your browser, and each release lists the SHA-256 of its files in
  `SHA256SUMS.txt`.
- It's a plain AutoHotkey v2 script: what runs is exactly the source you can
  read in `src\`. `Win11KeyRemapper.exe` in the release is the official
  AutoHotkey runtime (`AutoHotkey64.exe`) from AutoHotkey's GitHub releases,
  unmodified, only renamed. Releases are built by GitHub Actions; see the
  [Code signing policy](README.md#code-signing-policy).
