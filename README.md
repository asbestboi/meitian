# 每天 Měitiān

A playful app for learning a little Chinese every day, for **iPhone** (SwiftUI) and **Android** (Kotlin + Jetpack Compose), with the shared logic in a **Rust core**.

- **Confirm your level.** Say how good your Chinese is, then a short adaptive placement quiz (HSK 1–4) checks it. New words start just above what you already know.
- **New words daily.** Pick 3, 5 or 8 words a day. Swipe through flip cards (right = got it, left = again), hear native pronunciation, then take a quick quiz.
- **Learning path.** Lessons, sentence nodes built only from words you've learned, a story after every unit, and the HSK level-up test. Lessons, sentence nodes and stories give you three ❤️: wrong answers cost one and come back at the end, and at zero the lesson starts over.
- **Stories and chats you can follow.** A story unlocks once at most three of its words are new to you; locked ones show how many words are missing. New words are highlighted wherever they first appear and recapped at the end. One line per story can be translated for free; more than that and it pays no XP.
- **Friend challenge.** Every day you get a mission to use one of today's words in a real sentence, with a **Chinese friend** (ask, sneak it in, voice message…) or a **non‑Chinese friend** (teach them, charades, secret code…). Tick off the steps, rate how it went, add a note, and get +50 XP.
- **Pinyin everywhere for beginners.** Pinyin sits right above each character (ruby style), colored by tone (1 red, 2 orange, 3 green, 4 blue). Switch it off in Progress when you want to test your reading; the placement quiz never shows it.
- **Arena: battle friends offline.** Scan each other's QR code and the phones link directly over Bluetooth / peer‑to‑peer Wi‑Fi (MultipeerConnectivity), so no server or internet is needed. ⚔️ **Duel**: same question for both, first right answer hits (faster = harder), knock their HP to 0. ⚡️ **Blitz**: 45‑second race, most correct wins. 📱 **Same‑phone duel**: split screen on one phone. Wins earn 🪙 coins for the shop (avatars, card frames, titles, particle hit effects, auras), and you get battle stats plus head‑to‑head records per rival.
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
             levels, placement, learning path, sentence lessons, story unlocking, hearts, daily challenges, quiz options, battle rules, speech matching.
             Exposed to Swift and Kotlin through UniFFI. `cd core && cargo test`
Meitian/     iOS app (SwiftUI). scripts/build-core-ios.sh builds the core for aarch64-apple-ios
             and generates the Swift bindings; scripts/build-ipa.sh makes the .ipa.
android/     Android app (Kotlin, Jetpack Compose). scripts/build-core-android.sh builds the
             core with cargo-ndk and generates the Kotlin bindings; then `./gradlew assembleRelease`.
```

Battles are offline and peer-to-peer. iPhone↔iPhone uses MultipeerConnectivity and
Android↔Android uses Nearby Connections (Bluetooth / Wi‑Fi). **iPhone↔Android** goes over the
same Wi‑Fi or one phone's hotspot: each phone listens on a TCP port and puts its local addresses
in its QR code (`meitian-duel:<id>?os=…&lan=…&port=…`); the scanning phone connects. That link
(handshake, keep-alive, auto-reconnect) lives in the Rust core (`core/src/lan.rs`), and the
messages are the same JSON on both platforms.

Lessons are downloaded from [meitian-content](https://github.com/asbestboi/meitian-content)
(GitHub Pages): HSK 1–6 words (all word lists, so story words can be explained and tagged), graded Tatoeba sentences
for the learner's band ±1 and illustrated stories, cached for offline use.

## Get the Android app

GitHub Actions builds `Meitian.apk` on every push (**Actions → Android → Artifacts**) and attaches
it to tagged releases. It's signed with a debug key, so you can install it directly: allow
"install unknown apps" for your browser or file manager and open the .apk.
