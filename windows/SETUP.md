# Complete setup guide (Windows 11 + iPhone)

Follow this top to bottom. It sets up a server on the Windows PC that, when pinged,
makes the connected iPhone send an iMessage.

```
Browser / any server  --POST /send-->  Windows PC (Flask + Appium)  --socket-->  WebDriverAgent on iPhone  -->  sends
```

There are **three setup areas**: ① GitHub (build the phone app once), ② the iPhone,
③ the Windows PC. Do them in that order.

---

## ① GitHub Actions — build WebDriverAgent once (~5 min, no Mac)

WebDriverAgent (WDA) is the tiny app that runs on the iPhone. Building an iOS app needs
a Mac, so we use GitHub's free cloud Macs.

1. Put this repo on GitHub (public or private).
2. On GitHub: **Actions** tab → **Build WebDriverAgent** → **Run workflow**.
3. Wait for the green check → open the run → download the **WebDriverAgent-ipa** artifact.
4. Unzip it → you now have **`WebDriverAgent.ipa`**. Copy it to the Windows PC.

> One build works for any iPhone — Sideloadly re-signs it per person in step ②.

---

## ② The iPhone

You need the iPhone's **Apple ID** (email + password). A **free** Apple ID works but the
app must be refreshed every 7 days; a paid Developer account lasts a year.

### 2a. Install WebDriverAgent with Sideloadly (done from Windows)

1. On the PC, install **iTunes** and **Sideloadly** (covered in step ③ — do ③ first if
   you haven't, then come back).
2. Plug the iPhone into the PC. On the phone tap **Trust This Computer** + passcode.
3. Open **Sideloadly** → drag in `WebDriverAgent.ipa` → enter the iPhone's **Apple ID** →
   click **Start**. (If Apple asks for an app-specific password, create one at
   appleid.apple.com → Sign-In & Security.)

### 2b. Trust the app + enable Developer Mode (on the phone)

4. **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
5. **Settings → Privacy & Security → Developer Mode → ON** → the phone reboots.
6. After reboot, unlock and confirm **Turn On** Developer Mode.

### 2c. Keep it automation-friendly

7. **Settings → Display & Brightness → Auto-Lock → Never** (so the screen stays awake).
8. Keep the iPhone **plugged in and unlocked** whenever you're sending.

That's everything on the phone. The scrolling/typing/sending is all automated later.

---

## ③ The Windows PC

### 3a. One command installs everything

Straight after `git clone`, open **PowerShell** in the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

That installs **Node.js, Python, iTunes (Apple drivers), Appium + the iOS driver, and the
Python packages** using `winget` (built into Windows 11), then **verifies each one** and
prints a summary table. Click **Yes** on any UAC prompt.

It's **safe to re-run** — anything already installed is skipped. Useful flags:

| Flag | Does |
|---|---|
| `-VerifyOnly` | Check what's installed, change nothing. Run this after a reboot to confirm you're good. |
| `-SkipITunes` | Leave iTunes alone (the Apple drivers are already working). |
| `-SkipSideloadly` | Don't open the Sideloadly download page. |

Notes:
- The Python packages go into a **virtual environment at `windows\.venv`**, not your
  system Python — nothing else on the PC is touched. `start-gateway.ps1` finds it
  automatically, so there's no "activate" step.
- **Reboot when it finishes** if it says so — the Apple USB drivers only register after a
  restart. Then run `.\setup.ps1 -VerifyOnly` and confirm every row says `OK`.
- If a fresh PowerShell says `appium` isn't recognised, just **open a new window** — the
  PATH change only applies to new shells.

### 3b. Install Sideloadly (one manual download)

`winget` doesn't carry Sideloadly, so grab it once (setup.ps1 opens this page for you):
- Download + install from **https://sideloadly.io**
- (Now go do step ② — install WDA on the phone — if you skipped it.)

### 3c. Start the whole gateway with one command

Plug in the iPhone (trusted), then:

```powershell
cd <path-to-repo>\windows
.\start-gateway.ps1 -ApiKey "pick-a-secret"
```

This **auto-detects the iPhone** and opens three windows: WDA proxy, Appium, and the
gateway server. Leave all three open.

### 3d. Send a message

- Open **http://localhost:5000** in a browser.
- Enter the **API key** you chose, a **recipient** (name/number/email), and a **message**.
- Click **Send iMessage**.

To trigger it from another machine/server instead of the browser:
```powershell
curl -X POST http://localhost:5000/send `
  -H "Content-Type: application/json" `
  -H "X-Api-Key: pick-a-secret" `
  -d '{\"to\":\"Person X\",\"message\":\"Hello from my server\"}'
```
To reach it over the internet, tunnel it: `ngrok http 5000` gives a public URL.

---

## Manual mode (if you prefer separate terminals over start-gateway.ps1)

`tidevice` and `python` live in the venv, so call them from `.venv\Scripts\` — or run
`.\.venv\Scripts\Activate.ps1` once per terminal and then use the bare names.

```powershell
cd <path-to-repo>\windows

# find the UDID
.\.venv\Scripts\tidevice.exe list

# Terminal A — WDA on the phone + port forward
.\.venv\Scripts\tidevice.exe wdaproxy -B com.facebook.WebDriverAgentRunner.xctrunner --port 8100

# Terminal B — Appium (this one IS global)
appium

# Terminal C — the gateway (set the phone id + secret first)
$env:IPHONE_UDID = "<udid from tidevice list>"
$env:API_KEY = "pick-a-secret"
.\.venv\Scripts\python.exe server.py
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **Anything at all seems missing** | Run `.\setup.ps1 -VerifyOnly` — it prints a table of exactly what's `OK` vs `MISSING`. |
| `winget not found` | Update **App Installer** in the Microsoft Store, then open a new PowerShell. |
| `The Python environment is missing` | The venv wasn't built → run `.\setup.ps1` and check the "Python packages" row. |
| `appium is not recognized` | PATH only updates for **new** shells → close PowerShell, open a fresh one. |
| Python install "worked" but pip fails | You're on the Microsoft Store's fake `python.exe` stub. `setup.ps1` skips it and installs a real Python — re-run it, then open a new shell. |
| `running scripts is disabled on this system` | Launch with `powershell -ExecutionPolicy Bypass -File .\setup.ps1` (as documented above). |
| `socket connect error` / port 27015 | Apple driver missing → install iTunes, **reboot** |
| `port 4723 refused` | Appium server not running → open a terminal and run `appium` |
| `tidevice list` shows nothing | Cable/trust issue → replug, tap **Trust**, use a **data** cable (not charge-only) |
| WDA window errors on launch | Re-open the WDA app via Sideloadly; on **iOS 17+**, tidevice can be flaky — tell me and I'll switch you to `go-ios`/`pymobiledevice3` |
| App "expires" after ~7 days | Free Apple ID limit → re-run Sideloadly, or use a paid dev account |
| A tap fails (compose/send button) | Messages' labels vary by iOS version → open **Appium Inspector**, read the real element `name`, update the matching constant in `send_imessage.py` |

## What runs where (recap)

| Device | Installed |
|---|---|
| **iPhone** | WebDriverAgent (only this) |
| **Windows** | Node + Appium/XCUITest (global), Python + iTunes drivers, and Flask/Appium-client/tidevice inside `windows\.venv` |
| **GitHub** | builds `WebDriverAgent.ipa` (cloud Macs) |
