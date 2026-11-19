import SwiftUI

struct ChallengeView: View {
    @Environment(AppStore.self) private var store
    @State private var checked: Set<Int> = []
    @State private var mood: Int? = nil
    @State private var note = ""
    @State private var confetti = 0
    @State private var showHistory = false
    @Namespace private var friendNS

    private var friend: FriendKind { store.profile.preferredFriend }

    private var pool: [Word] {
        let t = store.today.newWordIds.compactMap(WordBank.word)
        return t.isEmpty ? store.learnedWords : t
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    friendPicker
                    if let c = Challenge.make(dayKey: store.todayKey, words: pool, friend: friend) {
                        if let log = store.today.challenge {
                            completed(log, challenge: c)
                        } else {
                            mission(c)
                        }
                    }
                    if !store.challengeHistory.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Challenge")
        }
        .overlay { ConfettiView(trigger: confetti) }
        .sensoryFeedback(.success, trigger: confetti)
    }

    // MARK: pieces

    private var friendPicker: some View {
        HStack(spacing: 6) {
            ForEach(FriendKind.allCases) { kind in
                Button {
                    withAnimation(Theme.spring) {
                        store.profile.preferredFriend = kind
                        checked = []
                    }
                    store.save()
                } label: {
                    HStack(spacing: 6) {
                        Text(kind.emoji)
                        Text(kind.label).font(.rounded(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(friend == kind ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if friend == kind {
                            Capsule().fill(Theme.warmGradient).matchedGeometryEffect(id: "pill", in: friendNS)
                        }
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .disabled(store.today.challenge != nil)
            }
        }
        .padding(5)
        .background(Theme.card, in: Capsule())
        .sensoryFeedback(.selection, trigger: friend)
    }

    private func wordHeader(_ c: Challenge) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's word").font(.rounded(.caption, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                Text(c.word.hanzi).font(.hanzi(52, weight: .bold))
                Text("\(c.word.pinyin) · \(c.word.meaning)")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .opacity(0.9)
            }
            Spacer()
            SpeakButton(text: c.word.hanzi, size: 54, tint: .white)
        }
        .foregroundStyle(.white)
        .padding(22)
        .background(Theme.levelGradient(c.word.level), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Theme.levelColor(c.word.level).opacity(0.35), radius: 16, y: 10)
    }

    private func mission(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            wordHeader(c)

            VStack(alignment: .leading, spacing: 8) {
                Pill(text: c.title, color: Theme.red, systemImage: "target")
                Text(c.mission).font(.rounded(.title3, weight: .bold))
            }

            sentenceCard(c.word)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(c.steps.indices, id: \.self) { i in
                    stepRow(i, text: c.steps[i])
                }
            }
            .cardSurface(padding: 12)

            Label(c.bonus, systemImage: "star.circle.fill")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.gold)

            if checked.count == c.steps.count {
                reflection(c).transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tick off the steps as you go. 你可以的！(nǐ kěyǐ de · you can do it!)")
                    .font(.rounded(.footnote)).foregroundStyle(.secondary)
            }
        }
        .animation(Theme.spring, value: checked.count == c.steps.count)
    }

    private func sentenceCard(_ w: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your sentence").font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button { Speaker.shared.say(w.example, slow: true) } label: {
                    Label("Slow", systemImage: "tortoise.fill").font(.rounded(.caption, weight: .bold))
                }
                .buttonStyle(PressableStyle())
                SpeakButton(text: w.example, size: 36, tint: Theme.jade)
            }
            RubyText(hanzi: w.example, pinyin: w.examplePinyin, size: 26, weight: .semibold, alwaysShow: true)
            Text(w.exampleMeaning).font(.rounded(.subheadline)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func stepRow(_ i: Int, text: String) -> some View {
        let on = checked.contains(i)
        return Button {
            withAnimation(Theme.bouncy) {
                if on { checked.remove(i) } else { checked.insert(i) }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? Theme.jade : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                Text(text)
                    .font(.rounded(.body, weight: .medium))
                    .strikethrough(on, color: .secondary)
                    .foregroundStyle(on ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .sensoryFeedback(.impact(weight: .light), trigger: on)
    }

    private func reflection(_ c: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How did it go?").font(.rounded(.headline, weight: .bold))
            HStack(spacing: 10) {
                ForEach(0..<3) { m in
                    let opts = [("😅", "Tough"), ("🙂", "Good"), ("🤩", "Amazing")]
                    Button { withAnimation(Theme.bouncy) { mood = m } } label: {
                        VStack(spacing: 4) {
                            Text(opts[m].0).font(.system(size: 34))
                                .scaleEffect(mood == m ? 1.2 : 1)
                            Text(opts[m].1).font(.rounded(.caption, weight: .bold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(mood == m ? Theme.gold.opacity(0.2) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .sensoryFeedback(.selection, trigger: mood)
            TextField("What did they say? Anything new you learned?", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .font(.rounded(.body))
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            BigButton(title: "I did it! +50 XP", systemImage: "trophy.fill", gradient: Theme.goldGradient) {
                withAnimation(Theme.bouncy) {
                    store.completeChallenge(word: c.word, friend: friend, mood: mood, note: note)
                }
                confetti += 1
            }
        }
    }

    private func completed(_ log: ChallengeLog, challenge c: Challenge) -> some View {
        let word = WordBank.word(log.wordId) ?? c.word
        return VStack(spacing: 18) {
            Text("🏆").font(.system(size: 80))
            Text("Challenge complete!").font(.system(size: 28, weight: .bold, design: .rounded))
            Text("You used \(word.hanzi) with a \(log.friend == .chinese ? "Chinese" : "non‑Chinese") friend today. That's how words stick. 你真棒！(nǐ zhēn bàng · you're great!)")
                .font(.rounded(.body)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !log.note.isEmpty {
                Text("“\(log.note)”").font(.rounded(.body, weight: .medium)).italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: 16)
            }
            Text("New challenge tomorrow. 明天见！(míngtiān jiàn)")
                .font(.rounded(.subheadline, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past challenges").font(.rounded(.headline, weight: .bold))
            ForEach(store.challengeHistory.prefix(14)) { entry in
                let day = entry.day
                let log = entry.log
                HStack(spacing: 12) {
                    Text(log.friend.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(WordBank.word(log.wordId)?.hanzi ?? "—").font(.hanzi(20, weight: .semibold))
                            if let w = WordBank.word(log.wordId) {
                                PinyinText(pinyin: w.pinyin, font: .rounded(.subheadline, weight: .bold))
                            }
                        }
                        Text(day).font(.rounded(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let m = log.mood { Text(["😅", "🙂", "🤩"][m]).font(.title2) }
                }
                .cardSurface(padding: 14)
            }
        }
        .padding(.top, 10)
    }
}
