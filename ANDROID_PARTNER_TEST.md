# Android Partner Test

## Install

1. Download `crpg-debug.apk` onto the Android device.
2. Open it from the browser or Files app.
3. If prompted, allow that app to **Install unknown apps**.
4. Accept Android's warning and install **CRPG**.
5. Launch **CRPG** from the app launcher.

This is a private debug build signed by the developer, not a Play Store release. Android 5.0 is the package minimum, but Android 9 or newer with Vulkan support is the practical target for the game's Mobile renderer.

## First Test Checklist

- The app installs and opens without immediately closing.
- The game stays in landscape orientation and fills the display sensibly.
- The D-pad and A/B buttons remain inside rounded corners, notches, and system gesture areas.
- D-pad directions can be held, including walking continuously into walls.
- A advances dialogue and B cancels where supported.
- Dialogue choices can be changed and confirmed.
- Entering battle completes the spiral transition without a blank frame.
- Tapping chess pieces and destination squares selects and moves them correctly.
- Active-ability UI buttons respond to touch.
- Music and sound effects play in both the overworld and battle.
- Switching to another app and returning does not freeze, restart, or lose audio permanently.
- Reopening the game after closing it still launches normally.

## Report Back

Please send:

- Device model
- Android version
- A screenshot showing the touch controls
- Which checklist item failed, if any
- Whether the failure happens every time
- A short screen recording for touch-coordinate, scaling, or animation problems if practical

If Android reports that an update cannot be installed because the package conflicts with an existing app, uninstall the older **CRPG** build and install this APK again. Future builds signed with the same debug key should update normally.
