# 每天 Měitiān

A playful app for learning a little Chinese every day, for **iPhone** (SwiftUI) and **Android** (Kotlin + Jetpack Compose), with the shared logic in a **Rust core**.

- **Confirm your level.** Say how good your Chinese is, then a short adaptive placement quiz (HSK 1–4) checks it. New words start just above what you already know.
- **New words daily.** Pick 3, 5 or 8 words a day. Swipe through flip cards (right = got it, left = again), hear native pronunciation, then take a quick quiz.
- **Learning path.** Lessons, sentence nodes built only from words you've learned, a story after every unit, and the HSK level-up test. Lessons, sentence nodes and stories give you three ❤️: wrong answers cost one and come back at the end, and at zero the lesson starts over.
- **Stories and chats you can follow.** Every roadmap unit ends with its own story, alternating between picture stories and SMS chats: the lessons teach the words it needs, and at most three stay new. What a locked story is about stays hidden, but "learn words" gives you the lesson it needs. Chats use WeChat's own emoji. New words are highlighted wherever they first appear and recapped at the end. One line per story can be translated for free; more than that and it pays no XP.
- **Slot machine 🎰.** A free spin for every finished unit, and spins stack up: coins (rarely a 500 jackpot), a cosmetic you don't own, or a bonus sentence to hear, build and type for XP. The prize is decided by the core (seeded per player and spin).
- **Pinyin everywhere for beginners.** Pinyin sits right above each character (ruby style), colored by tone (1 red, 2 orange, 3 green, 4 blue). Switch it off in Progress when you want to test your reading; the placement quiz never shows it.
- **Arena: online battles for 2–4 players.** Quick-match a rated 1v1, queue for a group, or open a private party with a 6-character code (friends can be invited from the friends list). Ten modes: ⚔️ Duel, ⚡️ Blitz, 🎧 Listen, 🎵 Tone clash, 🧩 Sentence builder, ⌨️ Pinyin type, ☠️ Sudden death, ❤️ Survival, 👑 Battle royale (3–4) and 🤝 Team 2v2. 1v1s change your rating; groups pay 🪙 coins by place. Coins buy card frames, titles, particle hit effects (each with its own sound), auras and stickers. Profile pictures (or coloured initials) show who you are.
- **Arenas.** The scenery behind the path and the battles gets darker as the material gets harder: spring meadow, bamboo forest, misty temple mountains, volcanic badlands, lava fields, and the gates of hell at HSK 6. Tap the HSK badge for the arena road and see all six.
- **Battle invitations.** A banner anywhere in the app when a friend invites you, a notification when it's closed. There's no push service: Android checks about every 15 minutes, iOS when it grants a background refresh. Invitations stay open for 30 minutes.
- **Spaced repetition** reviews, listening drills and a speed mix.
- **Streaks, XP, levels** and an activity calendar. Daily reminder notifications.

Built with SwiftUI (iOS 17+), springs, sounds and haptics throughout (both adjustable), light and dark mode, and Reduce Motion support. Lessons, stories and reviews work offline and stay on the device. Only battles, friends and leaderboards need internet: they use a nickname-only profile on the Cloudflare server in `server/`.

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
- `Meitian/Models`: word bank, progress store (JSON in Documents), battle session, speech and reminders
- `Meitian/Views`: Onboarding/placement, Today, Practice, Arena, Progress
- `Meitian/Components`: theme, flashcard deck, quiz runner, confetti and other widgets
- `Meitian/Resources/words.tsv`: 191 words in 4 levels, each with an example sentence (edit it to add more)

## Architecture

```
core/        Rust: words (compiled in), pinyin + ruby alignment, spaced repetition, streaks,
             levels, placement, learning path, sentence lessons, story unlocking, hearts, the slot machine, title colours, quiz options,
             the battle engine (referee for 2–4 players), sounds, every hit effect, aura and arena (drawn as draw commands, see draw.rs), speech matching.
             Exposed to Swift and Kotlin through UniFFI. `cd core && cargo test`
Meitian/     iOS app (SwiftUI). scripts/build-core-ios.sh builds the core for aarch64-apple-ios
             and generates the Swift bindings; scripts/build-ipa.sh makes the .ipa.
android/     Android app (Kotlin, Jetpack Compose). scripts/build-core-android.sh builds the
             core with cargo-ndk and generates the Kotlin bindings; then `./gradlew assembleRelease`.
```

```
server/      Cloudflare Worker + Durable Objects: profiles, friends, parties, matchmaking, battle rooms,
             leaderboards. `cd server && npm ci && npx vitest run`
```

Battles run over a WebSocket room on the server. One phone hosts and referees; the server relays its messages,
names the next host when it drops, and settles forfeits and ratings. Both apps run the same state machine from
the core (`core/src/battle.rs`), which is tested with simulated phones for every mode. Deploying a new version:
`npx wrangler d1 migrations apply meitian --remote && npx wrangler deploy` in `server/`.

Lessons are downloaded from [meitian-content](https://github.com/asbestboi/meitian-content)
(GitHub Pages): HSK 1–6 words (all word lists, so story words can be explained and tagged), graded Tatoeba sentences
for the learner's band ±1 and illustrated stories, cached for offline use.

## Get the Android app

GitHub Actions builds `Meitian.apk` on every push (**Actions → Android → Artifacts**) and attaches
it to tagged releases. It's signed with a debug key, so you can install it directly: allow
"install unknown apps" for your browser or file manager and open the .apk.
