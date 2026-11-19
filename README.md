# 每天 Měitiān

A playful iPhone app for learning a little Chinese every day.

- **Confirm your level.** Say how good your Chinese is, then a short adaptive placement quiz (HSK 1–4) checks it. New words start just above what you already know.
- **New words daily.** Pick 3, 5 or 8 words a day. Swipe through flip cards (right = got it, left = again), hear native pronunciation, then take a quick quiz.
- **Friend challenge.** Every day you get a mission to use one of today's words in a real sentence, with a **Chinese friend** (ask, sneak it in, voice message…) or a **non‑Chinese friend** (teach them, charades, secret code…). Tick off the steps, rate how it went, add a note, and get +50 XP.
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
