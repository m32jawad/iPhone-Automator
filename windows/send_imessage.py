"""
Appium flow: open Messages -> new message -> type recipient -> type body -> Send.

Runs on Windows. Talks over a socket to WebDriverAgent on the iPhone via Appium.

HOW IT ADDRESSES A RECIPIENT: iOS 26's Messages removed the tappable "compose"
button, so we open a new message with the `sms:` URL scheme instead — that's stable
across iOS versions. We then only need the body field and the Send button.

NOTE ON SELECTORS: if a step can't find an element, open **Appium Inspector**, tap
the element, read its real `name`/`label`, and update the constant below.
"""

from __future__ import annotations

import os
import time
from urllib.parse import quote
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy

# --- connection settings (read from environment; start-gateway.ps1 sets these) ---
# You normally don't edit these by hand — start-gateway.ps1 auto-detects the UDID
# and exports it. They only fall back to defaults for manual runs.
APPIUM_SERVER = os.environ.get("APPIUM_SERVER", "http://127.0.0.1:4723")
# Point at a prebuilt WDA (Windows/tidevice flow). Set to "" or "auto" to let Appium
# build & manage WDA itself — that's what the macOS simulator/device flow uses.
WDA_URL = os.environ.get("WDA_URL", "http://127.0.0.1:8100")
IPHONE_UDID = os.environ.get("IPHONE_UDID", "")   # auto-detected: tidevice list --usb --one
MESSAGES_BUNDLE_ID = "com.apple.MobileSMS"

# --- selectors (verified on iOS 26; older iOS covered by the fallbacks below) -
BODY_FIELD_ID = "messageBodyField"          # the message text box (a11y id; label "Message")
SEND_BTN_ID = "sendButton"                  # the blue up-arrow send button (a11y id; label "Send")


def _make_driver() -> webdriver.Remote:
    if not IPHONE_UDID:
        raise RuntimeError(
            "No iPhone UDID set. Start the stack with start-gateway.ps1 (it auto-detects "
            "the device), or set the IPHONE_UDID environment variable manually "
            "(find it with: tidevice list)."
        )
    opts = XCUITestOptions()
    opts.platform_name = "iOS"
    opts.automation_name = "XCUITest"
    opts.udid = IPHONE_UDID
    opts.bundle_id = MESSAGES_BUNDLE_ID
    if WDA_URL and WDA_URL.lower() != "auto":
        opts.set_capability("webDriverAgentUrl", WDA_URL)
    # macOS + a real device with no prebuilt WDA: let Appium build & sign one.
    team_id = os.environ.get("XCODE_TEAM_ID", "")
    if team_id:
        opts.set_capability("xcodeOrgId", team_id)
        opts.set_capability("xcodeSigningId", "Apple Development")
        # WDA's stock bundle id (com.facebook.WebDriverAgentRunner) is already
        # registered to another team, so a fresh team can't sign it. Build under a
        # unique id instead. Overridable via WDA_BUNDLE_ID (start-gateway.sh flag).
        wda_bundle_id = os.environ.get("WDA_BUNDLE_ID", "")
        if wda_bundle_id:
            opts.set_capability("updatedWDABundleId", wda_bundle_id)
    opts.set_capability("newCommandTimeout", 120)
    opts.set_capability("waitForIdleTimeout", 0)  # Messages animates a lot; don't over-wait
    return webdriver.Remote(APPIUM_SERVER, options=opts)


def _find_first(driver, locators, timeout=10):
    """Return the first of several (by, value) locators that appears (no click)."""
    end = time.time() + timeout
    last_err = None
    while time.time() < end:
        for by, value in locators:
            try:
                el = driver.find_element(by, value)
                if el.is_displayed():
                    return el
            except Exception as e:  # noqa: BLE001 - broad on purpose, we retry
                last_err = e
        time.sleep(0.4)
    raise TimeoutError(f"None of these appeared in {timeout}s: {locators} ({last_err})")


def _tap_first(driver, locators, timeout=10):
    """Tap the first of several (by, value) locators that appears."""
    el = _find_first(driver, locators, timeout)
    el.click()
    return el


def send_imessage(recipient: str, message: str) -> None:
    """Open Messages and send `message` to `recipient` (phone number or email).

    Contact *names* are less reliable than a number/address, since the sms: scheme
    addresses by phone/email — prefer those.
    """
    driver = _make_driver()
    try:
        # 1) Open a fresh compose addressed to `recipient` via the sms: URL scheme.
        #    (iOS 26 removed the tappable compose button; this works on every iOS.)
        driver.execute_script("mobile: deepLink", {
            "url": "sms:" + quote(recipient),
            "bundleId": MESSAGES_BUNDLE_ID,
        })

        # 2) Type the message into the body field.
        body = _tap_first(driver, [
            (AppiumBy.ACCESSIBILITY_ID, BODY_FIELD_ID),
            (AppiumBy.IOS_PREDICATE,
             "label == 'Message' OR value == 'iMessage' OR value == 'Text Message'"),
            (AppiumBy.CLASS_NAME, "XCUIElementTypeTextView"),
        ], timeout=15)
        body.send_keys(message)

        # 3) Tap Send (the blue up-arrow). If it's disabled, the recipient can't be
        #    reached from here — e.g. the iOS Simulator has no SMS/iMessage service.
        send_btn = _find_first(driver, [
            (AppiumBy.ACCESSIBILITY_ID, SEND_BTN_ID),
            (AppiumBy.IOS_PREDICATE, "name == 'sendButton' OR label == 'Send'"),
        ], timeout=10)
        if (send_btn.get_attribute("enabled") or "").lower() == "false":
            raise RuntimeError(
                "Send is disabled — the recipient can't receive a message here. "
                "The iOS Simulator has no SMS/iMessage service; use a real iPhone."
            )
        send_btn.click()

        time.sleep(1.0)  # let it fire off

        # Leave the phone on the Home screen. Otherwise quitting terminates
        # Messages and the phone is left sitting on WebDriverAgent's own
        # "Automation Running" screen instead of returning to normal.
        try:
            driver.execute_script("mobile: pressButton", {"name": "home"})
        except Exception:  # noqa: BLE001 - cosmetic; a sent message must not fail here
            pass
    finally:
        driver.quit()


if __name__ == "__main__":
    # Quick manual test: python send_imessage.py
    send_imessage("YOUR_TEST_CONTACT", "Hello from my Windows server 👋")
