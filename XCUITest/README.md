# XCUITest: full-UI Messages automation

Drives the real Messages UI on a physical iPhone: launch → scroll to bottom → Home.
This is the only iOS-supported way to scroll *inside* another app.

## What you need

- A **Mac** with **Xcode** installed (free from the Mac App Store).
- A **free Apple ID** (a paid $99 developer account is NOT required for running on your own device).
- Your **iPhone + a USB cable**.

## One-time setup

1. On the Mac, open Xcode → **File ▸ New ▸ Project** → **iOS ▸ App** → name it `IphoneAutomator`.
2. When creating it, check **Include Tests** (or later: **File ▸ New ▸ Target ▸ UI Testing Bundle**).
3. In the new **UITests** group, delete the sample test file and drag in
   [`MessagesAutomationUITests.swift`](MessagesAutomationUITests.swift).
4. Select the project ▸ **Signing & Capabilities** ▸ pick your Apple ID under **Team**
   (do this for the app target *and* the UITests target).
5. Plug in the iPhone. On the phone: **Settings ▸ Privacy & Security ▸ Developer Mode ▸ On**, then reboot.
6. In Xcode's top bar, select your iPhone as the run destination.

## Run it

- Open [`MessagesAutomationUITests.swift`](MessagesAutomationUITests.swift), click the
  diamond ◇ next to `testOpenMessagesScrollToBottomAndClose`, **or**
- Press **⌘U** to run all UI tests, **or**
- From Terminal:
  ```sh
  xcodebuild test \
    -scheme IphoneAutomator \
    -destination 'platform=iOS,name=YOUR_IPHONE_NAME' \
    -only-testing:IphoneAutomatorUITests/MessagesAutomationUITests
  ```

The first run may ask you to trust the developer on the phone:
**Settings ▸ General ▸ VPN & Device Management ▸ (your Apple ID) ▸ Trust**.

## How the code works

- `XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")` targets Apple Messages.
- `.launch()` opens it; `wait(for: .runningForeground)` blocks until it's visible.
- `scrollToBottom` swipes up repeatedly and stops when the visible text stops changing
  (a reliable "we hit the bottom" signal), capped at 40 swipes for safety.
- `XCUIDevice.shared.press(.home)` returns to the Home Screen — the App-safe way to
  "close" (iOS doesn't allow programmatic force-quit).

## Tweaks

- **Scroll inside a specific conversation** instead of the list: before `scrollToBottom`,
  tap a conversation, e.g. `messages.cells.firstMatch.tap()`.
- **Scroll the other direction**: change `swipeUp` to `swipeDown`.
- **Slower/faster**: change `velocity: .fast` to `.slow`.

## Caveats

- Apple system apps (like Messages) can change their internal view structure between iOS
  versions, so element queries may need small adjustments.
- This runs under the test harness; it's for personal automation/learning and testing,
  not something you can ship on the App Store.
