# 每天 Měitiān

A playful app for learning a little Chinese every day, for **iPhone** (SwiftUI) and **Android** (Kotlin + Jetpack Compose), with the shared logic in a **Rust core**.

- **Confirm your level.** Say how good your Chinese is, then a short adaptive placement quiz (HSK 1–4) checks it. New words start just above what you already know.
- **New words daily.** Pick 3, 5 or 8 words a day. Swipe through flip cards (right = got it, left = again), hear native pronunciation, then take a quick quiz.
- **Friend challenge.** Every day you get a mission to use one of today's words in a real sentence, with a **Chinese friend** (ask, sneak it in, voice message…) or a **non‑Chinese friend** (teach them, charades, secret code…). Tick off the steps, rate how it went, add a note, and get +50 XP.
- **Pinyin everywhere for beginners.** Pinyin sits right above each character (ruby style), colored by tone (1 red, 2 orange, 3 green, 4 blue). Switch it off in Progress when you want to test your reading; the placement quiz never shows it.
- **Arena: battle friends offline.** Scan each other's QR code and the phones link directly over Bluetooth / peer‑to‑peer Wi‑Fi (MultipeerConnectivity), so no server or internet is needed. ⚔️ **Duel**: same question for both, first right answer hits (faster = harder), knock their HP to 0. ⚡️ **Blitz**: 45‑second race, most correct wins. 📱 **Same‑phone duel**: split screen on one phone. Wins earn 🪙 coins for the shop (avatars, card frames, titles, hit effects), and you get battle stats plus head‑to‑head records per rival.
- **Spaced repetition** reviews, listening drills and a speed mix.
- **Streaks, XP, levels** and an activity calendar. Daily reminder notifications.

Built with SwiftUI (iOS 17+), springs and haptics throughout, light and dark mode, and Reduce Motion support. No accounts or servers: everything stays on the device.

## Get the .ipa

GitHub Actions builds `Meitian.ipa` on every push to `main` (**Actions → iOS → latest run → Artifacts**).
Push a tag like `v1.0.0` to also attach it to a release.

The .ipa is unsigned. Install it with **Sideloadly**, **AltStore** or **SideStore**, which sign it with your Apple ID. With a free Apple ID the app has to be re-signed every 7 days; AltStore/SideStore can do that automatically.

## Build locally (macOS)

```sh
brew install xcodegen
scripts/build-ipa.sh          # -> build/Meitian.ipa
# or: xcodegen generate && open Meitian.xcodeproj
```

## Layout

- `project.yml`: XcodeGen project spec
- `Meitian/Models`: word bank, progress store (JSON in Documents), challenge generator, speech and reminders
- `Meitian/Views`: Onboarding/placement, Today, Challenge, Practice, Progress
- `Meitian/Components`: theme, flashcard deck, quiz runner, confetti and other widgets
- `Meitian/Resources/words.tsv`: 191 words in 4 levels, each with an example sentence (edit it to add more)

## Architecture

```
core/        Rust: words (compiled in), pinyin + ruby alignment, spaced repetition, streaks,
             levels, placement, daily challenges, quiz options, battle rules, speech matching.
             Exposed to Swift and Kotlin through UniFFI. `cd core && cargo test`
Meitian/     iOS app (SwiftUI). scripts/build-core-ios.sh builds the core for aarch64-apple-ios
             and generates the Swift bindings; scripts/build-ipa.sh makes the .ipa.
android/     Android app (Kotlin, Jetpack Compose). scripts/build-core-android.sh builds the
             core with cargo-ndk and generates the Kotlin bindings; then `./gradlew assembleRelease`.
```

Battles are offline and peer-to-peer: iPhones use MultipeerConnectivity, Android phones use
Nearby Connections. The two can't talk to each other, so battles are iPhone↔iPhone or
Android↔Android. Both pair by scanning the same `meitian-duel:<id>` QR codes.

## Get the Android app

GitHub Actions builds `Meitian.apk` on every push (**Actions → Android → Artifacts**) and attaches
it to tagged releases. It's signed with a debug key, so you can install it directly: allow
"install unknown apps" for your browser or file manager and open the .apk.
