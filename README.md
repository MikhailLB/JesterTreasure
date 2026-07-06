# Jester Treasure

Hyper-casual mobile game built with Flutter. The player controls a jolly court jester defending the royal vault from greedy monsters by throwing enchanted golden coins with a simple drag-to-aim / release-to-throw gesture.

- **Bundle ID:** `com.jestertreas.jesterstreasure`
- **Platform:** Android
- **Version:** 1.0.1 (build 1)

## Features

- One-finger drag-to-aim / release-to-throw controls (tap also throws).
- Two enemy types: Gold Goblin (fast, 1 HP) and Treasure Mimic (slow, 2 HP) with escalating difficulty.
- Treasure Burst super power that clears the screen and grants bonus score.
- Persistent high score and total coin count via `shared_preferences`.
- Loading screen that adapts to portrait and landscape orientations, with a horizontal progress bar that only fills 100% right before the game launches.
- In-app WebView screens for Privacy Policy and Support.
- Adaptive launcher icon that fills the entire icon canvas without empty edges.

## Build

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```

The release build is signed via `android/key.properties` and `android/app/jestertreasure-release.jks` (both intentionally excluded from git).
