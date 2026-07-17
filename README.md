# iPhone Automator — remote iMessage gateway

Send iMessages from a **Windows PC** (or any webserver) without touching the phone.
Ping an endpoint (or use the built-in web page) → the connected iPhone opens Messages
and sends your text.

```
Browser / any server  --POST /send-->  Windows PC (Flask + Appium)  --socket-->  WebDriverAgent on iPhone  -->  sends
```

**No Mac to own:** WebDriverAgent is built on GitHub's cloud macOS runners and
signed/installed from Windows with Sideloadly.

---

## 🚀 Setting this up on a (friend's) Windows 11 PC

Everything is in one guide: **[windows/SETUP.md](windows/SETUP.md)**. Short version:

1. **GitHub** → Actions tab → run **Build WebDriverAgent** → download `WebDriverAgent.ipa`.
2. **Windows** → clone the repo, then from the repo root:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```
   Installs + verifies Node, Python, iTunes drivers, Appium + the iOS driver, and the
   Python packages, then prints a table of what's `OK`. Re-runnable; reboot if it asks.
   It also opens the **Sideloadly** download page (the one thing winget can't install).
3. **iPhone** → Sideloadly installs `WebDriverAgent.ipa`; trust it + enable Developer Mode.
4. **Run** → `cd windows` → `.\start-gateway.ps1 -ApiKey "secret"` → open **http://localhost:5000**.

Stuck? `.\setup.ps1 -VerifyOnly` tells you exactly what's missing.

## What's in the repo

| Path | What it is |
|---|---|
| [.github/workflows/build-wda.yml](.github/workflows/build-wda.yml) | Cloud build of WebDriverAgent → downloadable `.ipa` |
| [setup.ps1](setup.ps1) | **Start here** — run after cloning; forwards to the installer below |
| [windows/setup.ps1](windows/setup.ps1) | The real installer: Node, Python, iTunes, Appium + iOS driver, venv, and verification |
| [windows/start-gateway.ps1](windows/start-gateway.ps1) | Auto-detects the iPhone and launches all 3 services |
| [windows/server.py](windows/server.py) | Flask web UI + `POST /send` |
| [windows/send_imessage.py](windows/send_imessage.py) | Appium flow: open Messages → recipient → type → Send |
| [windows/index.html](windows/index.html) | The browser UI |
| [windows/SETUP.md](windows/SETUP.md) | **Full step-by-step guide** |
| [shortcut/](shortcut/) | Bonus: iPhone-only "tap to open Messages" Shortcut |
| [XCUITest/](XCUITest/) | Reference: the same automation as native Swift (needs a Mac to run) |

## Honest limitations

- The iPhone must stay **plugged in, unlocked, on Wi-Fi**, with WDA running — it's a UI
  robot, not a background service.
- iMessage sending is UI-driven: ~1 message every few seconds, not bulk blasting.
- **Free Apple ID** → re-sign WDA weekly; a paid dev account lasts a year.
- Messages' UI labels shift between iOS versions — one-line selector tweaks may be needed
  (see the Troubleshooting table in SETUP.md).
- **iOS 17+**: tidevice can be flaky launching WDA; a `go-ios` fallback exists if needed.
- For **your own** personal automation only — don't use it for spam/unsolicited messaging.
