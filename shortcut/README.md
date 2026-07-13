# The "Start" Shortcut (iPhone only)

This makes a Home Screen icon that acts like an app with a Start button.
Tapping it opens Messages, waits, then returns to the Home Screen.

> Scrolling *inside* Messages is not possible from a Shortcut — that needs the XCUITest project.

## Build it (tap by tap)

1. Open the **Shortcuts** app (pre-installed; search "Shortcuts" if hidden).
2. Tap **+** (top-right) to create a new shortcut.
3. Tap **Add Action** → search **Open App** → tap it.
4. In the action, tap the blue word **App** → choose **Messages**.
5. Tap **Add Action** → search **Wait** → set the seconds (e.g. **3**).
6. Tap **Add Action** → search **Go to Home Screen** → add it.

Your shortcut now reads:

```
Open App        → Messages
Wait            → 3 seconds
Go to Home Screen
```

7. Tap the shortcut's name at the top → rename it **Auto Messages** → **Done**.

## Turn it into a Home Screen "app" (your Start button)

1. Find the shortcut, tap the **⋯** (three dots) on its tile.
2. Tap the **Share** icon (□ with ↑) at the bottom.
3. Choose **Add to Home Screen**.
4. Rename it, and tap the icon image to pick a custom picture.
5. Tap **Add**.

Now tapping that Home Screen icon = "open app and click Start" → Messages launches.

## Bonus: make it run by itself

Shortcuts app → **Automation** tab → **New Automation** → pick a trigger
(time of day, arriving/leaving a place, opening/closing an app, connecting a charger).
