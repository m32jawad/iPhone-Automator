"""
Appium flow: open Messages -> new message -> type recipient -> type body -> Send.

Runs on Windows. Talks over a socket to WebDriverAgent on the iPhone via Appium.

NOTE ON SELECTORS: Apple changes Messages' internal accessibility labels between
iOS versions. If a step can't find an element, open **Appium Inspector**, tap the
element, read its real `name`/`label`, and update the constant below. Every selector
here has a comment marking what to check.
"""

from __future__ import annotations

import os
import time
from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

# --- connection settings (read from environment; start-gateway.ps1 sets these) ---
# You normally don't edit these by hand — start-gateway.ps1 auto-detects the UDID
# and exports it. They only fall back to defaults for manual runs.
APPIUM_SERVER = os.environ.get("APPIUM_SERVER", "http://127.0.0.1:4723")
WDA_URL = os.environ.get("WDA_URL", "http://127.0.0.1:8100")
IPHONE_UDID = os.environ.get("IPHONE_UDID", "")   # auto-detected: tidevice list --usb --one
MESSAGES_BUNDLE_ID = "com.apple.MobileSMS"

# --- selectors to verify in Appium Inspector if a step fails ------------------
COMPOSE_BTN = "compose"                     # the "new message" pencil icon (top-right)
TO_FIELD_PLACEHOLDER = "To:"                # the recipient field
BODY_FIELD_NAMES = ("iMessage", "Text Message")  # message text box placeholder
SEND_BTN = "Send"                           # the up-arrow send button


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
    opts.set_capability("webDriverAgentUrl", WDA_URL)
    opts.set_capability("newCommandTimeout", 120)
    opts.set_capability("waitForIdleTimeout", 0)  # Messages animates a lot; don't over-wait
    return webdriver.Remote(APPIUM_SERVER, options=opts)


def _tap_first(driver, locators, timeout=10):
    """Try several (by, value) locators; tap the first that appears."""
    end = time.time() + timeout
    last_err = None
    while time.time() < end:
        for by, value in locators:
            try:
                el = driver.find_element(by, value)
                if el.is_displayed():
                    el.click()
                    return el
            except Exception as e:  # noqa: BLE001 - broad on purpose, we retry
                last_err = e
        time.sleep(0.4)
    raise TimeoutError(f"None of these appeared in {timeout}s: {locators} ({last_err})")


def send_imessage(recipient: str, message: str) -> None:
    """Open Messages and send `message` to `recipient` (name, phone, or email)."""
    driver = _make_driver()
    try:
        wait = WebDriverWait(driver, 15)

        # 1) New message.
        _tap_first(driver, [
            (AppiumBy.ACCESSIBILITY_ID, COMPOSE_BTN),
            (AppiumBy.IOS_PREDICATE, "name == 'compose' OR label == 'New Message'"),
        ])

        # 2) Recipient -> type, then pick the first suggestion.
        to_field = wait.until(EC.presence_of_element_located(
            (AppiumBy.IOS_PREDICATE,
             f"value CONTAINS '{TO_FIELD_PLACEHOLDER}' OR name CONTAINS '{TO_FIELD_PLACEHOLDER}'")
        ))
        to_field.click()
        to_field.send_keys(recipient)
        time.sleep(1.2)  # let contact suggestions populate
        # Tap the first matching suggestion cell (falls back to the field itself).
        try:
            driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeCell")[0].click()
        except Exception:  # noqa: BLE001
            pass

        # 3) Message body.
        body = _tap_first(driver, [
            (AppiumBy.IOS_PREDICATE,
             " OR ".join(f"value == '{n}'" for n in BODY_FIELD_NAMES)),
            (AppiumBy.CLASS_NAME, "XCUIElementTypeTextView"),
        ])
        body.send_keys(message)

        # 4) Send.
        _tap_first(driver, [
            (AppiumBy.ACCESSIBILITY_ID, SEND_BTN),
            (AppiumBy.IOS_PREDICATE, f"name == '{SEND_BTN}' OR label == '{SEND_BTN}'"),
        ])

        time.sleep(1.0)  # let it fire off
    finally:
        driver.quit()


if __name__ == "__main__":
    # Quick manual test: python send_imessage.py
    send_imessage("YOUR_TEST_CONTACT", "Hello from my Windows server 👋")
