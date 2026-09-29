# Android Distribution Roadmap

You do not need the partner's exact device details to make an Android build. The useful minimum is:

- Confirm that the device runs Android, not iOS.
- Ideally obtain the Android version and device model.
- Because the project currently uses Godot's **Mobile** renderer, target Android 9 or newer with Vulkan support. Older devices may require the Compatibility renderer and additional testing.

## Current Project Status

Project-side Android support is now in place:

- A checked-in Android export preset produces a debug APK at `android/crpg-debug.apk` once the external toolchain is configured.
- A multitouch D-pad and A/B overlay emits the existing movement, interaction, and back actions; it hides automatically on desktop and during ordinary battle play.
- Dialogue can request the controls over either the overworld or a chess scene.
- Chess squares accept direct screen touches in both native and fixed-logical viewport modes without relying on mouse emulation.
- Touch controls account for Android's display safe area, and handheld orientation is sensor-landscape.
- The keyboard developer console is disabled on Android. The MCP toolkit already strips and disables its runtime during exports.

The development toolchain is configured and a signed debug APK has been produced at `android/crpg-debug.apk`. The package targets Android API 34, supports ARMv7 and ARM64, and has been signature-verified. Final appearance, device cutouts, audio, suspend/resume, performance, and control feel still require testing on real Android hardware.

## 1. Add Basic Mobile Controls (Implemented)

Create a touchscreen overlay owned by `Main`:

- Four directional buttons or a D-pad mapped to `move_up`, `move_down`, `move_left`, and `move_right`.
- An A-style button mapped to `interact`.
- A B-style button mapped to `back`.
- Hide the overlay automatically on desktop.
- Hide or alter it during chess battles if direct board touches are sufficient.

Godot's `TouchScreenButton` can emit the existing input actions directly, so this should not require mobile-specific changes to the player movement state machine.

For a very early test, a Bluetooth keyboard can substitute for on-screen controls. The Android device will not generate game controls on its own.

## 2. Install the Android Export Toolchain

On the development Mac:

1. Install the Godot 4.4 export templates from **Editor > Manage Export Templates**.
2. Install OpenJDK 17.
3. Install Android Studio and the required Android SDK components.
4. In Godot's Editor Settings, configure:
   - Java SDK path
   - Android SDK path

Reference: [Godot 4.4: Exporting for Android](https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_android.html)

## 3. Create an Android Export Preset (Implemented)

In **Project > Export**:

The current preset uses:

- Package identifier: `com.max.crpg`
- Display name: `CRPG`
- ARMv7 and ARM64
- Immersive fullscreen
- Sensor-landscape orientation
- Debug output: `android/crpg-debug.apk`

Direct testing does not require a Play Store account, an Android App Bundle (`.aab`), or a formal release-signing key. A debug-signed `.apk` is sufficient.

## 4. Test Locally

If an Android device is available, connect it over USB:

1. Enable Developer Options and USB debugging on the device.
2. Allow the Mac's debugging connection when prompted.
3. Deploy the APK from Godot.
4. Verify:
   - Scaling and letterboxing
   - Notches and navigation bars
   - Touch-target sizes
   - Overworld controls
   - Chess square selection and dragging
   - Dialogue advancement and choices
   - Audio startup and looping
   - App suspension and resumption

Testing through Godot provides more useful error output than repeatedly sending experimental builds to another person.

## 5. Send the APK to the Partner

Send the generated `.apk`, not a Windows `.exe`.

A cloud-storage link is generally more reliable than attaching an APK directly to email, because some email services block executable attachments.

The partner should:

1. Download the APK.
2. Allow **Install unknown apps** for the browser or file-manager app used to open it.
3. Open and install the APK.
4. Accept Android's warning that the app did not come from the Play Store.
5. Launch it normally.

If a later APK uses the same package name but is signed with a different key, Android may require the existing installation to be removed before installing the new build.

## Useful Device Information

The exact device is not required before development begins. For the first external test, ask for:

- Phone or tablet model
- Android version
- Screen resolution, if readily available
- Whether the device uses gesture navigation or the three-button navigation bar

These details become important if the APK refuses to install, Vulkan initialization fails, touch coordinates are wrong, or performance is unexpectedly poor.

Reference: [Godot 4.4 system requirements](https://docs.godotengine.org/en/4.4/about/system_requirements.html)

## Next Required Step

Send `android/crpg-debug.apk` and `ANDROID_PARTNER_TEST.md` to the partner. Use their first real-device test to verify installation, rendering, controls, audio, suspend/resume, and performance. Preserve `android/debug.keystore` locally: future APKs must use the same key and package identifier to install as updates.
