# SnapText ✿

**English** | [繁體中文](README.zh-Hant.md) | [简体中文](README.zh-Hans.md)

**Copy text from anything on your Mac screen.**

Lecture slides in a video, a screenshot someone sent you, a PDF that won't let you select, text inside an image — press **⇧⌘2**, drag over it, and the words are on your clipboard. It uses the Mac's built-in text recognition, so it works offline and nothing leaves your computer.

<!-- Add a demo GIF here: ![demo](docs/demo.gif) -->

## Features

- ⌨️ **One shortcut** — ⇧⌘2, drag, done (or pick another shortcut)
- 🈶 **Chinese, English, Japanese, Korean** — Traditional and Simplified Chinese, mixed with English
- 📐 **Keeps reading order** — lines come out top to bottom, left to right; no stray spaces between Chinese characters
- ↩️ **Your choice of line breaks** — keep them as on screen, or join into paragraphs (great for slides and PDFs)
- ✏️ **Fix before you paste** — a popup shows what was read; edit a word and press Copy
- 🔳 **Reads QR codes too** — scan a QR code on screen and open the link
- 🕘 **Recent captures** — your last captures are one click away in the menu bar
- 🎨 **Make it yours** — popup look (Glass / Light / Dark), accent color, font, text size, position, how long it stays
- 🔒 **Private & offline** — uses Apple's on-device Vision framework. No internet, no account
- 🪶 **Tiny & native** — a single Swift file, no dependencies

## Install

Requires macOS 12 or later.

1. Download this repo (**Code → Download ZIP**) and unzip it
2. Open **Terminal**, type `bash ` (with a space), drag `build.sh` into the window, press Enter
3. If macOS asks you to install **Command Line Tools**, install them and run step 2 again
4. **Allow Screen Recording:** System Settings → Privacy & Security → **Screen & System Audio Recording** → turn on **SnapText**. Then quit SnapText (menu bar icon → Quit SnapText) and open it again from Applications

> SnapText only looks at the area you select, at the moment you select it. Screen Recording is the permission macOS requires for any app that reads what's on screen.

## Usage

| Action | How |
|---|---|
| Copy text from the screen | Press **⇧⌘2** and drag over the text (Esc to cancel) |
| Fix a mistake | Edit the text in the popup, then press **Copy** |
| One paragraph / keep lines | Buttons in the popup, or set the default in Settings |
| Open a QR code link | Capture the QR code → **Open link** |
| Copy something from earlier | Menu bar icon → **Recent** |
| Settings | Menu bar icon → **Settings…** (⌘,) |
| Launch at login | Menu bar icon → **Open at Login** |

**Tips**
- Text in a small font? Zoom in first (⌘+) — bigger text is read more accurately.
- Wrong characters for Chinese? Pick the right language in **Settings → Capture → Language** instead of Automatic.

## Build manually

```bash
swiftc -O -parse-as-library SnapText.swift -o SnapText
```

Use `build.sh` for a proper app — the shortcut and the Screen Recording permission work best when SnapText is installed in Applications.

## Support

If SnapText saved you some retyping, you can support it here:

- ☕ Buy Me a Coffee: https://buymeacoffee.com/sirene122

## License

[MIT](LICENSE)
