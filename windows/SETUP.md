# Windows setup — remote iMessage gateway

Goal: your Windows PC runs a server; pinging it makes the iPhone send an iMessage.
No Mac required — WDA is built in GitHub Actions and signed on Windows.

```
POST /send {to, message}  ->  Windows (Flask + Appium)  ->  socket  ->  WDA on iPhone  ->  Messages sends
```

## Step 1 — Build WebDriverAgent (in the cloud, once)

1. Push this repo to GitHub.
2. Go to the repo's **Actions** tab → **Build WebDriverAgent** → **Run workflow**.
3. When it finishes, download the **WebDriverAgent-ipa** artifact → unzip → you get `WebDriverAgent.ipa`.

## Step 2 — Sign + install WDA on the iPhone (Windows, no Mac)

1. Install **iTunes** (the Apple version, for device drivers) and **[Sideloadly](https://sideloadly.io)** on Windows.
2. Plug in the iPhone, trust the computer.
3. Open Sideloadly → drag in `WebDriverAgent.ipa` → enter your **Apple ID** → **Start**.
   - Free Apple ID: the app works for **7 days**, then re-run Sideloadly to refresh it.
4. On the iPhone: **Settings → General → VPN & Device Management → (your Apple ID) → Trust**.
5. **Settings → Privacy & Security → Developer Mode → On**, then reboot.

## Step 3 — Install the Windows tooling

```powershell
# Node + Appium (the automation server)
npm install -g appium
appium driver install xcuitest

# tidevice — talks to the iPhone over USB from Windows, forwards the WDA port
pip install tidevice

# Python deps for this project
pip install -r requirements.txt
```

Find your device UDID and put it in `send_imessage.py` (`IPHONE_UDID`):

```powershell
tidevice list
```

## Step 4 — Start everything (3 terminals)

**Terminal A — launch WDA on the phone and forward its port to localhost:8100**
```powershell
tidevice wdaproxy -B com.facebook.WebDriverAgentRunner.xctrunner --port 8100
```
(If your WDA bundle id differs, `tidevice applist` shows it. Keep this window open.)

**Terminal B — the Appium server**
```powershell
appium
```

**Terminal C — the gateway server**
```powershell
$env:API_KEY = "pick-a-secret"
python server.py
```

## Step 5 — Send a message

**Easiest — the web UI:** open **http://localhost:5000** in a browser. You get a form
(API key / To / Message / Send). Fill it in and click **Send iMessage**.

**Or by API** (for other servers/scripts):
```powershell
curl -X POST http://localhost:5000/send `
  -H "Content-Type: application/json" `
  -H "X-Api-Key: pick-a-secret" `
  -d '{\"to\":\"Person X\",\"message\":\"Hello from my server\"}'
```

To trigger it from **another webserver / the internet**, expose your PC with a tunnel:
```powershell
# e.g. ngrok — gives you a public https URL that forwards to localhost:5000
ngrok http 5000
```
Then that other server just POSTs to the ngrok URL.

## Keeping it alive (it's an iPhone, so:)

- Keep the phone **plugged in, unlocked, on the same Wi-Fi**, screen-auto-lock off
  (Settings → Display & Brightness → Auto-Lock → Never).
- The WDA session can die if iOS backgrounds it; Terminal A (`tidevice wdaproxy`)
  auto-relaunches it. If sends start failing, that terminal is the first thing to check.
- Free Apple ID → re-sign with Sideloadly weekly.

## When a send fails on a specific tap

Apple's Messages labels change across iOS versions. Install **Appium Inspector**
(desktop app), connect to the same session, tap the element that failed, read its real
`name`/`label`, and update the matching constant at the top of `send_imessage.py`.
