"""
sim_smoke.py — prove the automation "app" (WebDriverAgent) works in the iOS Simulator.

This is the simulator-safe equivalent of the real send flow. It does NOT send an
iMessage (the simulator has no iMessage account and can't), it proves the whole
Appium -> WebDriverAgent -> UI-driving chain runs end to end:

    open Messages  ->  read the UI  ->  scroll  ->  return Home

Appium builds & launches a *simulator* WebDriverAgent for us (no prebuilt .ipa, no
webDriverAgentUrl), so the first run compiles WDA and can take a few minutes.

Env (run-sim.sh sets these):
    APPIUM_SERVER   default http://127.0.0.1:4723
    SIM_UDID        the booted simulator's UDID (required)
"""

from __future__ import annotations

import os
import sys
import time

from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy

APPIUM_SERVER = os.environ.get("APPIUM_SERVER", "http://127.0.0.1:4723")
SIM_UDID = os.environ.get("SIM_UDID") or os.environ.get("IPHONE_UDID", "")
MESSAGES_BUNDLE_ID = "com.apple.MobileSMS"


def _make_driver() -> webdriver.Remote:
    if not SIM_UDID:
        sys.exit("SIM_UDID not set — launch this via ./macos/run-sim.sh (it boots a sim and sets it).")
    opts = XCUITestOptions()
    opts.platform_name = "iOS"
    opts.automation_name = "XCUITest"
    opts.udid = SIM_UDID                 # a booted simulator UDID -> Appium treats it as a sim
    opts.bundle_id = MESSAGES_BUNDLE_ID  # launch Messages on session start
    # No webDriverAgentUrl: let Appium build + run a *simulator* WDA itself.
    opts.set_capability("newCommandTimeout", 300)
    opts.set_capability("wdaLaunchTimeout", 600000)  # first WDA build can be slow
    opts.set_capability("usePrebuiltWDA", False)
    return webdriver.Remote(APPIUM_SERVER, options=opts)


def main() -> None:
    print(f"[..] Connecting to Appium at {APPIUM_SERVER} for sim {SIM_UDID}")
    print("[..] First run compiles WebDriverAgent for the simulator — this can take a few minutes.")
    driver = _make_driver()
    try:
        print("[ok] Session up. WebDriverAgent is running in the simulator.")
        time.sleep(2)

        texts = driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")
        labels = [t.get_attribute("label") or "" for t in texts[:8] if (t.get_attribute("label") or "").strip()]
        print(f"[ok] Messages is on screen. Sample UI labels: {labels}")

        # Scroll the list a couple of times, then return Home — the project's core gesture.
        size = driver.get_window_size()
        x = size["width"] // 2
        for _ in range(3):
            driver.swipe(x, int(size["height"] * 0.8), x, int(size["height"] * 0.2), 300)
            time.sleep(0.4)
        print("[ok] Scrolled the Messages list.")

        driver.execute_script("mobile: pressButton", {"name": "home"})
        print("[ok] Returned to the Home Screen.")
        print("\nPASS — WebDriverAgent drove the Messages UI in the simulator.")
    finally:
        driver.quit()


if __name__ == "__main__":
    main()
