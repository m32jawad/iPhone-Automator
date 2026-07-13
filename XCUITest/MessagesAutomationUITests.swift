import XCTest

/// Full-UI automation of Apple Messages using XCUITest.
///
/// XCUITest is the ONLY iOS mechanism allowed to drive another app's UI
/// (tap / swipe / scroll). It must be launched from Xcode on a Mac with the
/// iPhone connected (or from `xcodebuild test` on the command line).
///
/// Flow: launch Messages → scroll to the very bottom → return to Home Screen.
final class MessagesAutomationUITests: XCTestCase {

    /// Apple Messages' bundle identifier (the app's unique system ID).
    private let messagesBundleID = "com.apple.MobileSMS"

    /// The system Home Screen / app switcher process.
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenMessagesScrollToBottomAndClose() throws {
        // 1) Launch Messages.
        let messages = XCUIApplication(bundleIdentifier: messagesBundleID)
        messages.launch()

        // Wait until it's actually on screen before touching anything.
        XCTAssertTrue(
            messages.wait(for: .runningForeground, timeout: 10),
            "Messages did not come to the foreground."
        )

        // 2) Scroll to the bottom.
        scrollToBottom(of: messages)

        // 3) "Close" the app by returning to the Home Screen.
        //    (iOS apps aren't force-quit programmatically; going Home backgrounds it,
        //     which is the normal, App-Store-safe equivalent of closing.)
        goHome()
    }

    // MARK: - Helpers

    /// Repeatedly swipes up until the content stops moving (i.e. we've hit the bottom).
    ///
    /// We detect "no more scrolling" by comparing the screen before and after each
    /// swipe: when a swipe changes nothing, we're at the end.
    private func scrollToBottom(of app: XCUIApplication) {
        // Prefer scrolling the main table/collection if one is exposed; otherwise
        // fall back to swiping the whole window.
        let scrollable: XCUIElement = {
            if app.tables.firstMatch.exists { return app.tables.firstMatch }
            if app.collectionViews.firstMatch.exists { return app.collectionViews.firstMatch }
            return app.windows.firstMatch
        }()

        let maxSwipes = 40 // safety cap so we never loop forever
        var previousSnapshot = ""

        for _ in 0..<maxSwipes {
            // A cheap "fingerprint" of what's currently visible.
            let currentSnapshot = app.staticTexts
                .allElementsBoundByIndex
                .prefix(15)
                .map { $0.label }
                .joined(separator: "|")

            if currentSnapshot == previousSnapshot {
                break // nothing changed since the last swipe → we're at the bottom
            }
            previousSnapshot = currentSnapshot

            scrollable.swipeUp(velocity: .fast)
        }
    }

    /// Sends the device to the Home Screen (backgrounds the current app).
    private func goHome() {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            springboard.wait(for: .runningForeground, timeout: 5),
            "Did not return to the Home Screen."
        )
    }
}
