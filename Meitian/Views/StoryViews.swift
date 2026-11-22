import SwiftUI

/// Reading history (ordered, oldest first) and the current "next story" surprise for each kind.
enum StoryProgress {
    private static let readKey = "storiesRead"
    private static let legacyKey = "storiesDone"

    static func read() -> [String] {
        let d = UserDefaults.standard
        if d.string(forKey: readKey) == nil, let old = d.string(forKey: legacyKey) { d.set(old, forKey: readKey) }
        return (d.string(forKey: readKey) ?? "").split(separator: ",").map(String.init)
    }

    static func isRead(_ id: String) -> Bool { read().contains(id) }

    static func markRead(_ id: String) {
        var r = read()
        guard !r.contains(id) else { return }
        r.append(id)
        UserDefaults.standard.set(r.joined(separator: ","), forKey: readKey)
    }

    /// Kept for older call sites.
    static func done() -> Set<String> { Set(read()) }
    static func markDone(_ id: String) { markRead(id) }

    private static func pickKey(_ chat: Bool) -> String { chat ? "nextChat" : "nextStory" }

    /// Forget everything read and the waiting surprises (reset all progress).
    static func reset() {
        let d = UserDefaults.standard
        for key in [readKey, legacyKey, pickKey(true), pickKey(false), pickKey(true) + "At", pickKey(false) + "At"] {
            d.removeObject(forKey: key)
        }
    }

    /// The surprise waiting for this learner, picked to fit the lesson they're on. It stays the same until it's
    /// read or the learner finishes another lesson (so reopening doesn't reroll), then a new unread one is
    /// picked. Only unlocked stories; nil when they've all been read.
    @MainActor
    static func next(chat: Bool, store: AppStore, unit: Int? = nil) -> Story? {
        let d = UserDefaults.standard
        let readIds = read()
        let known = store.known
        let dayKey = store.todayKey
        let atKey = pickKey(chat) + "At"
        if let id = d.string(forKey: pickKey(chat)), !readIds.contains(id), d.integer(forKey: atKey) == known.count,
           let s = storyById(id: id, knownWordIds: known),
           (s.style == "chat") == chat, s.date.isEmpty || s.date <= dayKey,
           storyUnlocked(story: s, knownWordIds: known) {
            return s
        }
        guard let s = nextStory(chat: chat, dayKey: dayKey, read: readIds, knownWordIds: known,
                                recent: store.unitWordIds(unit), upcoming: store.upcomingIds,
                                seed: UInt64.random(in: 0...UInt64.max)) else {
            d.removeObject(forKey: pickKey(chat))
            return nil
        }
        d.set(s.id, forKey: pickKey(chat))
        d.set(known.count, forKey: atKey)
        return s
    }
}

/// Illustration from the story pack. The whole picture is shown (fit) over a blurred, filled copy of
/// itself, so wide images never push the layout off screen and nothing gets cropped away.
struct StoryImageView: View {
    let image: StoryImage?
    var height: CGFloat = 240
    /// Cards and covers fill and crop; story panels show the whole picture.
    var fill = false

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.chrome.opacity(0.5))
            .overlay {
                if let image, let url = URL(string: image.url) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.3))) { phase in
                        switch phase {
                        case .success(let img):
                            if fill {
                                img.resizable().scaledToFill()
                            } else {
                                ZStack {
                                    img.resizable().scaledToFill().blur(radius: 24).opacity(0.7)
                                    img.resizable().scaledToFit()
                                }
                            }
                        case .failure: Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                        default: ProgressView()
                        }
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Downloads a story's pictures into the shared URL cache as soon as the story is opened, so they're
/// already there when each panel or message appears (AsyncImage reads the same cache).
enum ImagePrefetch {
    static func run(_ urls: [String]) {
        for s in urls {
            guard let url = URL(string: s) else { continue }
            let request = URLRequest(url: url)
            if URLCache.shared.cachedResponse(for: request) != nil { continue }
            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard let data, let response else { return }
                URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            }.resume()
        }
    }

    static func run(_ story: Story) { run(storyImageUrls(story: story)) }
}

struct ImageRef: Identifiable {
    let image: StoryImage
    var id: String { image.url }
}

/// Full-screen picture: pinch or double-tap to zoom, drag to pan, swipe down or ✕ to close.
struct FullScreenImage: View {
    let image: StoryImage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    /// The black fades as you drag the picture down to close it.
    private var backgroundOpacity: Double {
        guard scale <= 1 else { return 1 }
        let drag = Double(abs(offset.height))
        return max(0.4, 1.0 - drag / 500.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(backgroundOpacity)
            AsyncImage(url: URL(string: image.url)) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(baseScale * v.magnification, 1), 5) }
                    .onEnded { _ in
                        baseScale = scale
                        if scale <= 1 { withAnimation(Theme.spring) { offset = .zero; baseOffset = .zero } }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { v in
                            offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                        }
                        .onEnded { v in
                            if scale <= 1 {
                                if abs(v.translation.height) > 140 { dismiss(); return }
                                withAnimation(Theme.spring) { offset = .zero }
                            }
                            baseOffset = offset
                        })
            )
            .onTapGesture(count: 2) {
                withAnimation(Theme.spring) {
                    if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 }
                    baseScale = scale
                    baseOffset = offset
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                Spacer()
                Button { if let u = URL(string: image.source) { openURL(u) } } label: {
                    Text("art: \(image.artist)").font(.rounded(.caption)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(20)
        }
        .statusBarHidden()
    }
}

/// Practice tab: a mystery "next story" (no cover, no title: a surprise, like Duolingo), the stories that unlock
/// next, and the history of stories already read, which can be revisited (no XP the second time).
struct StoryHub: View {
    /// true: SMS chats; false: picture stories.
    var chats = false
    @Environment(AppStore.self) private var store
    @Environment(ContentSync.self) private var content
    @State private var open: StoryRef?
    @State private var next: Story?
    @State private var history: [Story] = []
    /// Unlocked stories, and how many of them were read.
    @State private var total = 0
    @State private var readCount = 0
    /// Stories with too many unlearned words, the soonest to unlock first.
    @State private var locked: [ShelfStory] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chats ? "chats 💬" : "stories").font(.rounded(.title3, weight: .bold))
                Sparkle(size: 12, color: chats ? Theme.sky : Theme.hot)
                Spacer()
                if total > 0 {
                    Text("\(readCount) / \(total) read").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            mysteryCard
            if !locked.isEmpty {
                Text("coming up").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(locked, id: \.story.id) { s in
                            StoryCard(story: s.story, missing: Int(s.missingWords), width: 180)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
            if !history.isEmpty {
                Text("history").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(history, id: \.id) { s in
                            Button { ImagePrefetch.run(s); open = StoryRef(story: s) } label: {
                                StoryCard(story: s, width: 160)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task(id: "\(content.generation)-\(store.todayKey)-\(store.currentLevel)-\(store.cards.count)") { refresh() }
        .fullScreenCover(item: $open, onDismiss: refresh) { ref in
            StoryPlayer(story: ref.story).environment(store)
        }
    }

    @ViewBuilder
    private var mysteryCard: some View {
        if let next {
            Button { ImagePrefetch.run(next); open = StoryRef(story: next) } label: {
                HStack(spacing: 16) {
                    Text(chats ? "💬" : "📖").font(.system(size: 44))
                        .frame(width: 72, height: 72)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chats ? "a new message" : "your next story").font(.rounded(.title3, weight: .heavy))
                        Text("HSK \(next.level) · it's a surprise ✦").font(.rounded(.subheadline, weight: .medium)).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.headline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Color(red: 0.78, green: 1.0, blue: 0.24), in: Circle())
                        .foregroundStyle(.black)
                }
                .foregroundStyle(.white)
                .streetBlock(Theme.nightGradient, padding: 18)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        } else if total > 0 || !locked.isEmpty {
            Text(nothingNew)
                .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: 16)
        }
    }

    private var nothingNew: String {
        if let soonest = locked.first {
            return "\(learnMoreWords(Int(soonest.missingWords))) the next \(chats ? "chat" : "story") ✦"
        }
        return chats ? "You've read every chat ✦ new ones arrive soon." : "You've read every story ✦ new ones arrive soon."
    }

    private func refresh() {
        let known = store.known
        let shelf = shelfStories(dayKey: store.todayKey, knownWordIds: known).filter { ($0.story.style == "chat") == chats }
        let read = StoryProgress.read()
        let readIds = Set(read)
        total = Int(storyAvailability(chat: chats, dayKey: store.todayKey, knownWordIds: known).unlocked)
        readCount = shelf.filter { $0.unlocked && readIds.contains($0.story.id) }.count
        locked = shelf.filter { !$0.unlocked && !readIds.contains($0.story.id) }
        let byId = Dictionary(shelf.map { ($0.story.id, $0.story) }, uniquingKeysWith: { a, _ in a })
        history = read.reversed().compactMap { byId[$0] }   // most recent first
        next = StoryProgress.next(chat: chats, store: store)
    }
}

/// "learn 4 more words to unlock"
func learnMoreWords(_ missing: Int) -> String { "learn \(missing) more word\(missing == 1 ? "" : "s") to unlock" }

struct StoryRef: Identifiable {
    let story: Story
    var id: String { story.id }
}

struct StoryCard: View {
    let story: Story
    /// Words still to learn before it unlocks (0 = open).
    var missing = 0
    var width: CGFloat = 200

    private var locked: Bool { missing > 0 }

    var body: some View {
        let done = StoryProgress.isRead(story.id)
        VStack(alignment: .leading, spacing: 0) {
            StoryImageView(image: story.cover, height: 130, fill: true)
                .overlay(alignment: .topLeading) {
                    Text(story.emoji).font(.title2).padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    if story.style == "chat" || !story.date.isEmpty {
                        Text(story.style == "chat" ? "💬 chat" : "daily")
                            .font(.rounded(.caption2, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.title3)
                            .foregroundStyle(.white, Theme.jade).padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(story.title).font(.hanzi(18, weight: .bold)).lineLimit(1)
                Text(story.titleEn.lowercased()).font(.rounded(.caption)).foregroundStyle(.secondary).lineLimit(1)
                Pill(text: "HSK \(story.level)", color: Theme.levelColor(Int(story.level)))
                    .padding(.top, 4)
            }
            .padding(12)
        }
        .frame(width: width)
        .foregroundStyle(.primary)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .opacity(locked ? 0.55 : 1)
        .overlay {
            if locked {
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.title)
                    Text(learnMoreWords(missing)).font(.rounded(.caption, weight: .bold)).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                .foregroundStyle(.white).shadow(radius: 6)
                .padding(8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Which lines of a story were translated. One peek is free; the next one costs the story's XP (the rule is in
/// the core).
@Observable
final class StoryTranslations {
    /// A replay pays no XP anyway.
    var replay = false
    /// The next tap on a line or reply shows its English.
    var armed = false
    private(set) var shown: Set<String> = []

    var cost: TranslationCost { replay ? .nothing : translationCost(translationsRevealed: UInt32(shown.count)) }

    func reveal(_ key: String) {
        shown.insert(key)
        armed = false
    }
}

/// While the EN button is armed, a tap anywhere on the line shows its English.
private struct Translatable: ViewModifier {
    let key: String
    let translations: StoryTranslations

    func body(content: Content) -> some View {
        content.overlay {
            if translations.armed && !translations.shown.contains(key) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.sky, lineWidth: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        SFX.shared.play(.tick)
                        withAnimation(Theme.spring) { translations.reveal(key) }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Show translation")
                    .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// Plays a story. Running out of hearts starts it over (a used peek stays used).
/// `onFinished` gets the number of lines that were translated.
struct StoryPlayer: View {
    let story: Story
    var onFinished: (Int) -> Void = { _ in }
    @State private var attempt = 0
    @State private var translations = StoryTranslations()

    var body: some View {
        StoryAttempt(story: story, translations: translations, onFinished: onFinished, onRetry: { attempt += 1 })
            .id(attempt)
    }
}

/// One try at a story, panel by panel: the picture, then the lines one at a time as chat bubbles
/// (read aloud, tap a word to look it up), then a question. Wrong answers cost hearts and are asked again.
private struct StoryAttempt: View {
    /// Reply choices are reshuffled every time a story opens (kept in @State so redraws don't reshuffle).
    @State private var story: Story
    let translations: StoryTranslations
    let onFinished: (Int) -> Void
    let onRetry: () -> Void

    init(story: Story, translations: StoryTranslations, onFinished: @escaping (Int) -> Void, onRetry: @escaping () -> Void) {
        _story = State(initialValue: shuffleStoryReplies(story: story, seed: UInt64.random(in: 0...UInt64.max)))
        self.translations = translations
        self.onFinished = onFinished
        self.onRetry = onRetry
    }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var panel = 0
    @State private var shown = 1                 // lines revealed in the current panel
    @State private var picked: Int?
    @State private var correct = 0
    @State private var finished = false
    @State private var hearts = Int(lessonHearts())
    @State private var failed = false
    /// Panels whose question was answered wrong: asked again after the last panel.
    @State private var again: [Int] = []
    @State private var retrying = false
    @State private var asks = 0
    @State private var askCost = false
    @State private var confetti = 0
    @State private var added = false
    @State private var zoomed: ImageRef?
    @State private var typing = false
    /// Read before: no XP this time.
    @State private var revisit = false
    /// Chat stories: messages added by your replies (and the reactions), per panel.
    @State private var sent: [Int: [StoryLine]] = [:]
    @State private var triedWrong: Set<Int> = []
    @State private var replyDone: Set<Int> = []
    /// Chat pictures stay hidden until tapped (the surprise).
    @State private var revealed: Set<String> = []

    private var isChat: Bool { story.style == "chat" }
    private var current: StoryPanel { story.panels[panel] }

    private struct ChatItem: Identifiable {
        let id: String
        let line: StoryLine
    }

    /// Chat stories keep the whole thread: all earlier panels plus what's revealed of this one.
    private var chatItems: [ChatItem] {
        var out: [ChatItem] = []
        for p in 0...panel {
            let lines = story.panels[p].lines
            let n = p < panel ? lines.count : min(shown, lines.count)
            for i in 0..<n { out.append(ChatItem(id: "\(p)-\(i)", line: lines[i])) }
            for (j, l) in (sent[p] ?? []).enumerated() { out.append(ChatItem(id: "\(p)-s\(j)", line: l)) }
        }
        return out
    }
    private var linesDone: Bool { shown >= current.lines.count }
    private var replyPending: Bool { linesDone && !current.reply.isEmpty && !replyDone.contains(panel) }
    private var dead: Bool { lessonFailed(hearts: UInt32(hearts)) }
    private var earned: Int {
        Int(storyXp(base: UInt32(20 + correct * 5), translationsRevealed: UInt32(translations.shown.count)))
    }
    /// The story's new words (marked by the core when it was opened).
    private var newWordIds: [String] {
        var ids: [String] = []
        for p in story.panels {
            ids += p.lines.flatMap { $0.tokens.newIds }
            for o in p.reply { ids += o.tokens.newIds + (o.reaction?.tokens.newIds ?? []) }
        }
        var have: Set<String> = []
        return ids.filter { have.insert($0).inserted }
    }
    private var questionPending: Bool { replyPending || (linesDone && current.question != nil && picked == nil) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if failed {
                OutOfHeartsView(onRetry: onRetry, onQuit: { dismiss() }).padding(20).transition(.opacity)
            } else if finished {
                results.transition(.scale(scale: 0.92).combined(with: .opacity))
            } else if retrying {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.bottom, 12)
                    ScrollView { retryQuestion.padding(.horizontal, 20).padding(.bottom, 20) }
                        .scrollIndicators(.hidden)
                    footer.padding(20)
                }
                .id(asks)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.bottom, 12)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: isChat ? 8 : 14) {
                                if isChat {
                                    ForEach(chatItems) { item in
                                        chatBubble(item.line, key: item.id)
                                            .id(item.id)
                                            .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity), removal: .opacity))
                                    }
                                    if typing { typingBubble.id("typing").transition(.opacity) }
                                } else {
                                    image
                                    ForEach(0..<min(shown, current.lines.count), id: \.self) { i in
                                        bubble(current.lines[i], key: "\(panel)-\(i)")
                                            .id(i)
                                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                    }
                                }
                                if linesDone && !replyPending, let q = current.question { question(q).id("q") }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .id(isChat ? 0 : panel)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: shown) { _, s in
                            withAnimation(Theme.spring) {
                                if isChat { proxy.scrollTo(chatItems.last?.id ?? "", anchor: .bottom) }
                                else { proxy.scrollTo(s - 1, anchor: .bottom) }
                            }
                        }
                        .onChange(of: typing) { _, t in if t { withAnimation(Theme.spring) { proxy.scrollTo("typing", anchor: .bottom) } } }
                        .onChange(of: chatItems.count) { _, _ in
                            if isChat { withAnimation(Theme.spring) { proxy.scrollTo(chatItems.last?.id ?? "", anchor: .bottom) } }
                        }
                        .onChange(of: linesDone) { _, d in if d { withAnimation(Theme.spring) { proxy.scrollTo("q", anchor: .bottom) } } }
                    }
                    footer.padding(20)
                }
            }
            ConfettiView(trigger: confetti)
        }
        .onAppear {
            revisit = StoryProgress.isRead(story.id)
            translations.replay = revisit
            ImagePrefetch.run(story)
            speakCurrentLine()
        }
        .fullScreenCover(item: $zoomed) { ref in FullScreenImage(image: ref.image) }
        .confirmationDialog("Show translation? You'll get no XP for this story.", isPresented: $askCost, titleVisibility: .visible) {
            Button("Show it, no XP", role: .destructive) {
                withAnimation(Theme.spring) { translations.armed = true }
            }
            Button("Keep reading", role: .cancel) {}
        }
        .onChange(of: replyPending) { _, pending in
            if pending { store.markSeen(current.reply.flatMap { $0.tokens.newIds }) }
        }
    }

    /// A question that was answered wrong, with its lines to read again.
    private var retryQuestion: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("one more time 再来一次").font(.rounded(.title2, weight: .heavy))
            ForEach(Array(current.lines.enumerated()), id: \.offset) { i, line in
                bubble(line, key: "\(panel)-\(i)")
            }
            if let q = current.question { question(q) }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(Theme.card, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .foregroundStyle(.primary)
                .accessibilityLabel("Close")
                ProgressView(value: min(progress, Double(story.panels.count)), total: Double(story.panels.count))
                    .tint(Theme.hot)
                    .animation(Theme.spring, value: shown)
                HeartsBar(hearts: hearts)
                translateButton
            }
            if translations.armed {
                Text("tap a line or a reply to see its English")
                    .font(.rounded(.footnote, weight: .bold)).foregroundStyle(Theme.sky)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var progress: Double {
        if retrying { return Double(story.panels.count) }
        return Double(panel) + (linesDone ? 1 : Double(shown) / Double(max(current.lines.count, 1)))
    }

    /// One free peek per story; after that it asks first, because the next one costs the XP.
    private var translateButton: some View {
        let armed = translations.armed
        let used = translations.cost != .free && !revisit
        return Button {
            if armed { withAnimation(Theme.spring) { translations.armed = false } }
            else if translations.cost == .xp { askCost = true }
            else { withAnimation(Theme.spring) { translations.armed = true } }
        } label: {
            Text(armed ? "EN ✓" : used ? "EN used" : "EN").font(.rounded(.caption, weight: .bold))
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(armed ? Theme.ink : Theme.card, in: Capsule())
                .foregroundStyle(armed ? Theme.background : used ? Color.secondary : Color.primary)
                .opacity(used && !armed ? 0.55 : 1)
        }
        .accessibilityLabel(armed ? "Cancel translation" : used ? "Translate another line, free peek used" : "Translate one line")
    }

    private var image: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoryImageView(image: current.image, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(8).background(.black.opacity(0.35), in: Circle()).padding(10)
                }
                .onTapGesture { if let img = current.image { zoomed = ImageRef(image: img) } }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Show picture full screen")
            if let img = current.image {
                Button {
                    if let u = URL(string: img.source) { openURL(u) }
                } label: {
                    Text("art: \(img.artist)").font(.rounded(.caption2)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bubble(_ line: StoryLine, key: String) -> some View {
        let narration = line.speaker.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if !narration {
                Text(line.speaker).font(.hanzi(13, weight: .bold)).foregroundStyle(Theme.hot)
            }
            HStack(alignment: .top) {
                TokenSentence(tokens: line.tokens, size: 22)
                Spacer(minLength: 6)
                SpeakButton(text: line.zh, size: 32, tint: Theme.sky)
            }
            if translations.shown.contains(key) {
                Text(line.en).font(.rounded(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(narration ? Color.clear : Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if narration {
                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .modifier(Translatable(key: key, translations: translations))
    }

    private func chatBubble(_ line: StoryLine, key: String) -> some View {
        let narration = line.speaker.isEmpty
        let mine = !narration && line.speaker == story.me
        return Group {
            if narration {
                VStack(spacing: 2) {
                    TokenSentence(tokens: line.tokens, size: 14, alignment: .center)
                    if translations.shown.contains(key) {
                        Text(line.en).font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .modifier(Translatable(key: key, translations: translations))
            } else {
                HStack(alignment: .bottom) {
                    if mine { Spacer(minLength: 50) }
                    VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                        if !mine {
                            Text(line.speaker).font(.hanzi(12, weight: .bold)).foregroundStyle(Theme.hot).padding(.leading, 6)
                        }
                        if let img = line.image {
                            let visible = revealed.contains(img.url)
                            StoryImageView(image: img, height: 170, fill: true)
                                .frame(width: 230)
                                .blur(radius: visible ? 0 : 22)
                                .overlay {
                                    if !visible {
                                        VStack(spacing: 4) {
                                            Image(systemName: "eye.slash.fill").font(.title2)
                                            Text("tap to see").font(.rounded(.caption, weight: .bold))
                                        }
                                        .foregroundStyle(.white)
                                        .shadow(radius: 4)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .onTapGesture {
                                    if visible { zoomed = ImageRef(image: img) }
                                    else {
                                        withAnimation(.easeOut(duration: 0.45)) { _ = revealed.insert(img.url) }
                                        SFX.shared.play(.coin)
                                    }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(visible ? "Sent picture, tap to enlarge" : "Hidden picture, tap to reveal")
                        }
                        if !line.zh.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    TokenSentence(tokens: line.tokens, size: 20)
                                    SpeakButton(text: line.zh, size: 28, tint: Theme.sky)
                                }
                                if translations.shown.contains(key) {
                                    Text(line.en).font(.rounded(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(mine ? Theme.sky.opacity(0.2) : Theme.card,
                                        in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 4,
                                                                   bottomTrailingRadius: mine ? 4 : 18, topTrailingRadius: 18,
                                                                   style: .continuous))
                            .modifier(Translatable(key: key, translations: translations))
                        }
                    }
                    if !mine { Spacer(minLength: 50) }
                }
            }
        }
    }

    private var typingBubble: some View {
        HStack {
            TypingDots()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.card, in: Capsule())
            Spacer()
        }
    }

    private func question(_ q: StoryQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(q.prompt).font(.rounded(.headline, weight: .bold))
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, text in
                Button {
                    guard picked == nil else { return }
                    withAnimation(Theme.spring) { picked = i }
                    if i == Int(q.answer) {
                        if !retrying { correct += 1 }
                        SFX.shared.play(.correct)
                    } else {
                        SFX.shared.play(.wrong)
                        hearts = Int(loseHeart(hearts: UInt32(hearts)))
                        again.append(panel)
                    }
                } label: {
                    HStack {
                        Text(text).font(.rounded(.body, weight: .semibold))
                        Spacer()
                        if picked != nil && i == Int(q.answer) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.jade) }
                        if picked == i && i != Int(q.answer) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(optionColor(i, q), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Theme.hot.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .haptic(.selection, trigger: picked)
    }

    private func optionColor(_ i: Int, _ q: StoryQuestion) -> Color {
        guard picked != nil else { return Theme.card }
        if i == Int(q.answer) { return Theme.jade.opacity(0.22) }
        if i == picked { return Theme.red.opacity(0.2) }
        return Theme.card
    }

    @ViewBuilder
    private var footer: some View {
        if dead && (picked != nil || !typing) {
            BigButton(title: "continue", systemImage: "arrow.right") {
                withAnimation(Theme.spring) { failed = true }
            }
        } else if replyPending {
            replyPicker
        } else {
            nextButton
        }
    }

    /// Chat stories: choose what you send. A reply that doesn't fit gets a reaction and you try again.
    private var replyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("your reply").font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
            ForEach(Array(current.reply.enumerated()), id: \.offset) { i, option in
                let tried = triedWrong.contains(i)
                let key = "\(panel)-r-\(option.zh)"
                Button { sendReply(i) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        option.tokens.markedText.font(.hanzi(18, weight: .medium))
                        Text(option.pinyin).font(.rounded(.caption)).foregroundStyle(.secondary)
                        if translations.shown.contains(key) { Text(option.en).font(.rounded(.caption)).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(tried ? Theme.red.opacity(0.12) : Theme.sky.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .strikethrough(tried)
                    .opacity(tried ? 0.5 : 1)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .foregroundStyle(.primary)
                .disabled(tried || typing || dead)
                .accessibilityLabel(option.tokens.spoken)
                .modifier(Translatable(key: key, translations: translations))
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func sendReply(_ i: Int) {
        let option = current.reply[i]
        let p = panel
        let mine = StoryLine(speaker: story.me, image: nil, zh: option.zh, pinyin: option.pinyin, en: option.en, tokens: option.tokens)
        withAnimation(Theme.bouncy) { sent[p, default: []].append(mine) }
        SFX.shared.play(.swoosh)
        Speaker.shared.say(option.zh)
        if option.correct {
            if triedWrong.isEmpty { correct += 1 }
        } else {
            triedWrong.insert(i)
            hearts = Int(loseHeart(hearts: UInt32(hearts)))
        }
        guard let reaction = option.reaction else {
            if option.correct { finishReply(p) }
            return
        }
        withAnimation(Theme.spring) { typing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(Theme.bouncy) {
                typing = false
                sent[p, default: []].append(reaction)
            }
            store.markSeen(reaction.tokens.newIds)
            SFX.shared.play(option.correct ? .correct : .wrong)
            if option.correct { finishReply(p) }
        }
    }

    private func finishReply(_ p: Int) {
        withAnimation(Theme.spring) {
            replyDone.insert(p)
            triedWrong = []
        }
    }

    private var nextButton: some View {
        BigButton(title: nextTitle, systemImage: "arrow.right", enabled: !questionPending) { advance() }
    }

    private var nextTitle: String {
        if !linesDone { return "continue" }
        if !retrying && panel + 1 < story.panels.count { return "next" }
        return again.isEmpty ? "finish" : "continue"
    }

    private func advance() {
        if !linesDone {
            if isChat {
                // "…" first, like a real chat
                guard !typing else { return }
                withAnimation(Theme.spring) { typing = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    withAnimation(Theme.bouncy) {
                        typing = false
                        shown += 1
                    }
                    SFX.shared.play(.tick)
                    speakCurrentLine()
                }
                return
            }
            withAnimation(Theme.bouncy) { shown += 1 }
            speakCurrentLine()
        } else if !retrying && panel + 1 < story.panels.count {
            withAnimation(Theme.spring) {
                panel += 1
                shown = 1
                picked = nil
            }
            SFX.shared.play(.swoosh)
            speakCurrentLine()
        } else if !again.isEmpty {
            // wrong questions come back until they're right
            withAnimation(Theme.spring) {
                panel = again.removeFirst()
                shown = current.lines.count
                picked = nil
                retrying = true
                asks += 1
            }
        } else {
            finish()
        }
    }

    private func finish() {
        if !revisit {
            StoryProgress.markRead(story.id)
            store.addXP(earned)
            store.count(.story)
        }
        store.markSeen(newWordIds, ding: false)
        onFinished(translations.shown.count)
        withAnimation(Theme.bouncy) { finished = true }
        confetti += 1
        SFX.shared.play(.win)
    }

    private func speakCurrentLine() {
        let i = shown - 1
        guard i >= 0, i < current.lines.count else { return }
        let text = current.lines[i].zh
        store.markSeen(current.lines[i].tokens.newIds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Speaker.shared.say(text) }
    }

    private var results: some View {
        let recap = newWordIds.compactMap(WordBank.word)
        let fresh = recap.filter { store.cards[$0.id] == nil }
        let questions = story.panels.filter { $0.question != nil }.count + story.panels.filter { !$0.reply.isEmpty }.count
        return VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 18) {
                    StoryImageView(image: story.cover, height: 180, fill: true)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .padding(.horizontal, 10)
                        .padding(.top, 20)
                    Text("故事读完了！").font(.hanzi(34, weight: .heavy))
                    Text("story finished · \(correct)/\(questions) questions right").font(.rounded(.subheadline)).foregroundStyle(.secondary)
                    Text(xpText).font(.rounded(.title2, weight: .heavy))
                        .foregroundStyle(revisit || earned == 0 ? Color.secondary : Theme.gold)
                    if !recap.isEmpty { NewWordsRecap(words: recap) }
                    if added || !fresh.isEmpty {
                        Button {
                            store.addToReview(fresh)
                            withAnimation(Theme.bouncy) { added = true }
                        } label: {
                            Label(added ? "added to review ✓" : "add \(fresh.count) new words to review",
                                  systemImage: added ? "checkmark" : "plus")
                                .font(.rounded(.headline, weight: .bold))
                                .padding(.horizontal, 20).padding(.vertical, 12)
                                .background(Theme.jade.opacity(0.16), in: Capsule())
                                .foregroundStyle(Theme.jade)
                        }
                        .disabled(added)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    private var xpText: String {
        if revisit { return "replay · no XP" }
        return earned == 0 ? "translated · no XP" : "+\(earned) XP"
    }
}

/// Today: the day's story (when there is a dated daily one), as a surprise card without its cover.
struct StoryOfTheDayCard: View {
    @Environment(AppStore.self) private var store
    @Environment(ContentSync.self) private var content
    @State private var open: StoryRef?
    @State private var refreshTick = 0

    var body: some View {
        let s = content.generation >= 0 && refreshTick >= 0 ? storyOfTheDay(dayKey: store.todayKey, knownWordIds: store.known) : nil
        if let s, s.date == store.todayKey {
            let read = StoryProgress.isRead(s.id)
            Button { ImagePrefetch.run(s); open = StoryRef(story: s) } label: {
                HStack(spacing: 16) {
                    Text(read ? "✅" : (s.style == "chat" ? "💬" : "🎁")).font(.system(size: 40))
                        .frame(width: 66, height: 66)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("today's story").font(.rounded(.caption, weight: .bold)).opacity(0.85)
                            Sparkle(size: 10, color: .white)
                        }
                        Text(read ? s.title : "open it to find out").font(.hanzi(20, weight: .heavy))
                        Text(read ? "read ✓ · tap to read again" : "a new one every day").font(.rounded(.caption)).opacity(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .streetBlock(Theme.pinkGradient, padding: 18)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .fullScreenCover(item: $open, onDismiss: { refreshTick += 1 }) { ref in
                StoryPlayer(story: ref.story).environment(store)
            }
        }
    }
}

/// Three bouncing dots ("is typing…").
struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .offset(y: on ? -3 : 3)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityLabel("typing")
    }
}
