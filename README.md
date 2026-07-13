# iPhone Automator — remote iMessage gateway

Send iMessages from your **Windows server** (or any webserver) without touching the phone.
Ping an endpoint → the connected iPhone opens Messages and sends your text.

```
POST /send {to, message}  ->  Windows PC (Flask + Appium)  ->  socket  ->  WebDriverAgent on iPhone  ->  sends
```

**No Mac required:** WebDriverAgent is built on GitHub's cloud macOS runners and
signed/installed from Windows with Sideloadly.

## Start here

➡️ **[windows/SETUP.md](windows/SETUP.md)** — full step-by-step: build WDA, install it,
run the server, send your first message.

## What's in here

| Path | What it is |
|---|---|
| [.github/workflows/build-wda.yml](.github/workflows/build-wda.yml) | Cloud build of WebDriverAgent → downloadable `.ipa` |
| [windows/server.py](windows/server.py) | Flask API — `POST /send` fires an iMessage |
| [windows/send_imessage.py](windows/send_imessage.py) | Appium flow: open Messages → recipient → type → Send |
| [windows/SETUP.md](windows/SETUP.md) | Windows setup & run instructions |
| [windows/requirements.txt](windows/requirements.txt) | Python deps |
| [shortcut/](shortcut/) | Bonus: iPhone-only "tap to open Messages" Shortcut |
| [XCUITest/](XCUITest/) | Reference: the same automation as native Swift (needs a Mac to run) |

## Honest limitations

- The iPhone must stay **plugged in, unlocked, on your Wi-Fi**, with WDA running —
  it's a UI robot, not a background service.
- iMessage sending is UI-driven, so ~1 message every few seconds, not bulk blasting.
- A **free Apple ID** means re-signing WDA weekly; a paid dev account lasts a year.
- Messages' UI labels shift between iOS versions — see the Appium Inspector note in SETUP.
- This is for **your own** personal automation. Don't use it for spam/unsolicited messaging.
