# macOS setup — build & test the iPhone app locally

This is the macOS counterpart of [windows/SETUP.md](../windows/SETUP.md). Because a Mac
already has Xcode, you **don't** need the cloud build, Sideloadly, or the iTunes USB
drivers — WebDriverAgent (the automation "app") is built **locally**, and you can run
the whole thing against the **iOS Simulator** or a **real iPhone**.

```
Browser / any server  --POST /send-->  macOS (Flask + Appium)  --builds & drives-->  WebDriverAgent on the Simulator or iPhone
```

> **Important — about the simulator:** this project's real job is to drive the **Messages**
> app to send **real iMessages**. That only works on a **physical iPhone**. The iOS
> Simulator has no iMessage account or cellular, so in the sim you can exercise the app,
> the UI-driving, and the gateway plumbing — but not an actual send. The prebuilt
> `Payload/WebDriverAgentRunner-Runner.app` and `WebDriverAgent*.zip` in the repo are
> **device** builds and will not launch in the simulator; `build-wda-sim.sh` builds the
> simulator version, and `run-sim.sh` lets Appium do it for you.

---

## ① Install everything (once)

From the repo root:

```sh
./macos/setup.sh
```

It installs + verifies **Xcode (checks), Node.js, Appium + the XCUITest driver, a Python
venv at `macos/.venv`** (Flask + the Appium client), and confirms an **iOS simulator** is
available, then prints a summary table. Re-runnable; installs nothing that's already there.

```sh
./macos/setup.sh --verify-only   # check only, install nothing
```

Requirements it can't install for you:
- **Xcode** (full app, from the Mac App Store) — not just the Command Line Tools.
  After installing: `sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept`
- An **iOS Simulator runtime** — Xcode ▸ Settings ▸ Components.

---

## ② Test the app in the Simulator (fast path)

```sh
./macos/run-sim.sh                      # default "iPhone 17"
./macos/run-sim.sh --device "iPhone 17 Pro"
```

What it does: boots the simulator, starts Appium, and runs [sim_smoke.py](sim_smoke.py),
which drives the Messages UI (**open → read → scroll → Home**). The **first run compiles a
simulator WebDriverAgent and can take a few minutes**; later runs are fast. Success ends
with `PASS — WebDriverAgent drove the Messages UI in the simulator.`

Want a standalone simulator `.app` to inspect or install yourself?

```sh
./macos/build-wda-sim.sh            # -> macos/build/sim/WebDriverAgentRunner-Runner.app
./macos/build-wda-sim.sh --install  # also installs it on the booted sim
```

---

## ③ Run the full gateway (web UI + POST /send)

```sh
./macos/start-gateway.sh --api-key "pick-a-secret"          # against the simulator
```

Then open **http://localhost:5001**, enter the API key, a recipient, and a message.
`Ctrl-C` stops the server and the Appium instance this script started.

> **Why 5001 and not 5000?** On macOS, port 5000 is held by the **AirPlay Receiver**, which
> answers your browser with a **403** and blocks Flask from binding. The gateway defaults to
> **5001**. Use `--port N` to change it, or turn AirPlay Receiver off in
> System Settings ▸ General ▸ AirDrop & Handoff.

Trigger it from anywhere:
```sh
curl -X POST http://localhost:5001/send \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: pick-a-secret" \
  -d '{"to":"Person X","message":"Hello from my Mac"}'
```

### Against a real iPhone (actual sending)

Plug in the iPhone, tap **Trust**, enable **Developer Mode**
(Settings ▸ Privacy & Security ▸ Developer Mode), then:

```sh
./macos/start-gateway.sh --target device --team-id ABCDE12345 --api-key "pick-a-secret"
```

- `--team-id` is your Apple Developer **Team ID** (Xcode ▸ Settings ▸ Accounts ▸ your
  team) so Appium can sign & install WebDriverAgent on the phone. A free Apple ID works
  but the signed WDA expires after ~7 days.
- Already have WDA running and port-forwarded (the Windows-style flow)? Skip signing with
  `--wda-url http://127.0.0.1:8100` instead of `--team-id`.
- `--udid` overrides device auto-detection.

---

## What's in `macos/`

| File | What it is |
|---|---|
| [setup.sh](setup.sh) | Installer + verifier (Xcode check, Node, Appium + XCUITest driver, venv) |
| [build-wda-sim.sh](build-wda-sim.sh) | Builds a **simulator** WebDriverAgent `.app` (the sim counterpart of the device `.ipa`) |
| [run-sim.sh](run-sim.sh) | Boot sim → Appium → drive Messages (the quick "test the app" path) |
| [start-gateway.sh](start-gateway.sh) | Full gateway (Appium + Flask), `--target sim` or `--target device` |
| [sim_smoke.py](sim_smoke.py) | The simulator-safe automation the smoke test runs |
| [_common.sh](_common.sh) | Shared helpers (boot sim, start/stop Appium) |
| [requirements.txt](requirements.txt) | Python packages for the venv (Flask, Appium client) |

The gateway itself (`server.py`, `send_imessage.py`, `index.html`) is shared with the
Windows flow and lives in [../windows/](../windows/) — it's plain, cross-platform Python.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Anything missing | `./macos/setup.sh --verify-only` prints exactly what's `OK` vs `MISSING`. |
| `appium: command not found` after setup | Open a **new** shell so the npm global bin is on `PATH`. |
| `Only the Command Line Tools are selected` | `sudo xcode-select -s /Applications/Xcode.app` |
| Device build "installed" but won't launch in the sim | Expected — it's an `iphoneos` build. Use `run-sim.sh` / `build-wda-sim.sh` for a sim build. |
| First `run-sim.sh` hangs for minutes | Normal — Appium is compiling WebDriverAgent for the simulator. Watch `macos/.logs/appium.log`. |
| `Address already in use` / browser shows **403** at :5000 | Port 5000 is AirPlay Receiver. The gateway defaults to `--port 5001`; or disable AirPlay Receiver. Check with `lsof -iTCP:5000 -sTCP:LISTEN`. |
| `--target device` fails to sign WDA | Pass a valid `--team-id`, or a `--wda-url` for an already-running WDA. |
| No iPhone found for `--target device` | Plug in with a data cable, tap **Trust**, or pass `--udid` (find it: `xcrun xctrace list devices`). |
| `500` on `/send` in the sim: "Send is disabled…" | Expected. The automation opens the message and types it, but the sim has **no SMS/iMessage service**, so iOS greys out the Send button. Real sending needs a physical iPhone. |
| A send fails at typing/Send on a real device | The sender opens the message via the `sms:` deep link, then taps `messageBodyField` / `sendButton`. If a label changed, read the real element name in **Appium Inspector** and update the constant in [../windows/send_imessage.py](../windows/send_imessage.py). |
