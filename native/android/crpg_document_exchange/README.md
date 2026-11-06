# CRPG Document Exchange Android Plugin

This Godot Android v2 plugin provides the native document picker and share
sheet used by `.crpggame` files. It deliberately requests no storage
permission; save/open access is granted by Android's Storage Access Framework,
and sharing uses Godot's existing app-private `FileProvider` URI.

Build with the Godot project's installed Android Gradle wrapper:

```sh
ANDROID_HOME=/path/to/android/sdk ../../../android/build/gradlew -p . :plugin:assembleRelease
```

Copy `plugin/build/outputs/aar/plugin-release.aar` to
`../../../addons/crpg_document_exchange.aar`. Godot's Gradle export template discovers
AAR files placed directly under `addons/`.
