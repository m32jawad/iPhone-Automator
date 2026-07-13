"""
Open Messages -> scroll to the bottom -> return Home, driven from Windows.

This talks over a socket to WebDriverAgent (WDA) running ON the iPhone,
via an Appium server. No Mac needed to RUN this -- only to build WDA once.

Prereqs on this Windows PC:
    pip install Appium-Python-Client
    npm install -g appium
    appium driver install xcuitest
    # WDA already installed on the iPhone, and the port forwarded, e.g.:
    #   tidevice wdaproxy -B com.facebook.WebDriverAgentRunner.xctrunner --port 8100
    # Start the Appium server in another terminal:
    #   appium
"""

from appium import webdriver
from appium.options.ios import XCUITestOptions
from appium.webdriver.common.appiumby import AppiumBy
import time

# --- connection settings -----------------------------------------------------
APPIUM_SERVER = "http://127.0.0.1:4723"
MESSAGES_BUNDLE_ID = "com.apple.MobileSMS"

options = XCUITestOptions()
options.platform_name = "iOS"
options.automation_name = "XCUITest"
options.udid = "YOUR_IPHONE_UDID"          # get it from: tidevice list
options.bundle_id = MESSAGES_BUNDLE_ID     # launch Messages on start
options.set_capability("webDriverAgentUrl", "http://127.0.0.1:8100")  # reuse the WDA you launched
options.set_capability("newCommandTimeout", 120)


def scroll_to_bottom(driver, max_swipes: int = 40) -> None:
    """Swipe up until the visible text stops changing (i.e. we hit the bottom)."""
    previous = ""
    for _ in range(max_swipes):
        labels = [e.get_attribute("label") or "" for e in
                  driver.find_elements(AppiumBy.CLASS_NAME, "XCUIElementTypeStaticText")[:15]]
        snapshot = "|".join(labels)
        if snapshot == previous:
            break  # nothing changed -> bottom reached
        previous = snapshot

        size = driver.get_window_size()
        x = size["width"] // 2
        driver.swipe(x, int(size["height"] * 0.8), x, int(size["height"] * 0.2), 300)
        time.sleep(0.3)


def main() -> None:
    driver = webdriver.Remote(APPIUM_SERVER, options=options)
    try:
        time.sleep(2)               # let Messages settle
        scroll_to_bottom(driver)
        driver.execute_script("mobile: pressButton", {"name": "home"})  # "close" -> Home
    finally:
        driver.quit()


if __name__ == "__main__":
    main()
