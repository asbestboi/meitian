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
        for key in [readKey, legacyKey, pickKey(true), pickKey(false)] { d.removeObject(forKey: key) }
    }

    /// The surprise waiting for this learner: stays the same until it's read (so reopening doesn't reroll),
    /// then a new random unread one. nil when everything has been read.
    static func next(chat: Bool, dayKey: String, level: Int) -> Story? {
        let d = UserDefaults.standard
        let readIds = read()
        if let id = d.string(forKey: pickKey(chat)), !readIds.contains(id), let s = storyById(id: id),
           (s.style == "chat") == chat, s.date.isEmpty || s.date <= dayKey,
           storyFitsLevel(story: s, maxLevel: UInt8(clamping: level)) {
            return s
        }
        guard let s = nextStory(chat: chat, dayKey: dayKey, maxLevel: UInt8(clamping: level), read: readIds,
                                seed: UInt64.random(in: 0...UInt64.max)) else {
            d.removeObject(forKey: pickKey(chat))
            return nil
        }
        d.set(s.id, forKey: pickKey(chat))
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

/// Practice tab: a mystery "next story" (no cover, no title: a surprise, like Duolingo), plus the
/// history of stories already read, which can be revisited (no XP the second time).
struct StoryHub: View {
    /// true: SMS chats; false: picture stories.
    var chats = false
    @Environment(AppStore.self) private var store
    @Environment(ContentSync.self) private var content
    @State private var open: StoryRef?
    @State private var next: Story?
    @State private var history: [Story] = []
    @State private var total = 0
    /// Stories waiting at higher HSK levels (locked until the learner gets there).
    @State private var above = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(chats ? "chats 💬" : "stories").font(.rounded(.title3, weight: .bold))
                Sparkle(size: 12, color: chats ? Theme.sky : Theme.hot)
                Spacer()
                if total > 0 {
                    Text("\(history.filter { Int($0.level) <= max(store.currentLevel, 1) }.count) / \(total) read").font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            mysteryCard
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
        .task(id: "\(content.generation)-\(store.todayKey)-\(store.currentLevel)") { refresh() }
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
        } else if total > 0 || above > 0 {
            Text(above > 0
                 ? "You've read every HSK \(max(store.currentLevel, 1)) \(chats ? "chat" : "story") ✦ \(above) more unlock at higher HSK levels."
                 : (chats ? "You've read every chat ✦ new ones arrive soon." : "You've read every story ✦ new ones arrive soon."))
                .font(.rounded(.subheadline, weight: .semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(padding: 16)
        }
    }

    private func refresh() {
        let all = shelfStories(dayKey: store.todayKey).filter { ($0.style == "chat") == chats }
        let fits = storyAvailability(chat: chats, dayKey: store.todayKey, maxLevel: UInt8(clamping: store.currentLevel))
        total = Int(fits.atLevel)
        above = Int(fits.aboveLevel)
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        history = StoryProgress.read().reversed().compactMap { byId[$0] }   // most recent first
        next = StoryProgress.next(chat: chats, dayKey: store.todayKey, level: store.currentLevel)
    }
}

struct StoryRef: Identifiable {
    let story: Story
    var id: String { story.id }
}

struct StoryCard: View {
    let story: Story
    var locked = false
    var width: CGFloat = 200

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
                    Text("HSK \(Int(story.level) - 1) first").font(.rounded(.caption, weight: .bold))
                }
                .foregroundStyle(.white).shadow(radius: 6)
            }
        }
    }
}

/// Plays a story panel by panel: the picture, then the lines one at a time as chat bubbles
/// (read aloud, tap a word to look it up), then a question.
struct StoryPlayer: View {
    let story: Story
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var panel = 0
    @State private var shown = 1                 // lines revealed in the current panel
    @State private var picked: Int?
    @State private var correct = 0
    @State private var finished = false
    @State private var showEnglish = false
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
    private var questionPending: Bool { replyPending || (linesDone && current.question != nil && picked == nil) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if finished {
                results.transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.bottom, 12)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: isChat ? 8 : 14) {
                                if isChat {
                                    ForEach(chatItems) { item in
                                        chatBubble(item.line)
                                            .id(item.id)
                                            .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity), removal: .opacity))
                                    }
                                    if typing { typingBubble.id("typing").transition(.opacity) }
                                } else {
                                    image
                                    ForEach(0..<min(shown, current.lines.count), id: \.self) { i in
                                        bubble(current.lines[i])
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
            ImagePrefetch.run(story)
            speakCurrentLine()
        }
        .fullScreenCover(item: $zoomed) { ref in FullScreenImage(image: ref.image) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .foregroundStyle(.primary)
            .accessibilityLabel("Close")
            ProgressView(value: Double(panel) + (linesDone ? 1 : Double(shown) / Double(max(current.lines.count, 1))),
                         total: Double(story.panels.count))
                .tint(Theme.hot)
                .animation(Theme.spring, value: shown)
            Button { withAnimation(Theme.spring) { showEnglish.toggle() } } label: {
                Text(showEnglish ? "EN ✓" : "EN").font(.rounded(.caption, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(showEnglish ? Theme.ink : Theme.card, in: Capsule())
                    .foregroundStyle(showEnglish ? Theme.background : .primary)
            }
            .accessibilityLabel(showEnglish ? "Hide translations" : "Show translations")
        }
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

    private func bubble(_ line: StoryLine) -> some View {
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
            if showEnglish {
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
    }

    private func chatBubble(_ line: StoryLine) -> some View {
        let narration = line.speaker.isEmpty
        let mine = !narration && line.speaker == story.me
        return Group {
            if narration {
                Text(showEnglish ? "\(line.zh) · \(line.en)" : line.zh)
                    .font(.rounded(.caption, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
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
                                if showEnglish {
                                    Text(line.en).font(.rounded(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(mine ? Theme.sky.opacity(0.2) : Theme.card,
                                        in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 4,
                                                                   bottomTrailingRadius: mine ? 4 : 18, topTrailingRadius: 18,
                                                                   style: .continuous))
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
                        correct += 1
                        SFX.shared.play(.correct)
                    } else {
                        SFX.shared.play(.wrong)
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
        .sensoryFeedback(.selection, trigger: picked)
    }

    private func optionColor(_ i: Int, _ q: StoryQuestion) -> Color {
        guard picked != nil else { return Theme.card }
        if i == Int(q.answer) { return Theme.jade.opacity(0.22) }
        if i == picked { return Theme.red.opacity(0.2) }
        return Theme.card
    }

    @ViewBuilder
    private var footer: some View {
        if replyPending {
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
                Button { sendReply(i) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.zh).font(.hanzi(18, weight: .medium))
                        Text(option.pinyin).font(.rounded(.caption)).foregroundStyle(.secondary)
                        if showEnglish { Text(option.en).font(.rounded(.caption)).foregroundStyle(.secondary) }
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
                .disabled(tried || typing)
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
        BigButton(title: linesDone ? (panel + 1 < story.panels.count ? "next" : "finish") : "continue",
                  systemImage: "arrow.right", enabled: !questionPending) { advance() }
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
        } else if panel + 1 < story.panels.count {
            withAnimation(Theme.spring) {
                panel += 1
                shown = 1
                picked = nil
            }
            SFX.shared.play(.swoosh)
            speakCurrentLine()
        } else {
            if !revisit {
                StoryProgress.markRead(story.id)
                store.addXP(20 + correct * 5)
                store.count(.story)
            }
            withAnimation(Theme.bouncy) { finished = true }
            confetti += 1
            SFX.shared.play(.win)
        }
    }

    private func speakCurrentLine() {
        let i = shown - 1
        guard i >= 0, i < current.lines.count else { return }
        let text = current.lines[i].zh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Speaker.shared.say(text) }
    }

    private var results: some View {
        let ids = storyWordIds(story: story)
        let fresh = ids.compactMap(WordBank.word).filter { store.cards[$0.id] == nil && !$0.isSwear }
        let questions = story.panels.filter { $0.question != nil }.count + story.panels.filter { !$0.reply.isEmpty }.count
        return VStack(spacing: 18) {
            Spacer()
            StoryImageView(image: story.cover, height: 180, fill: true)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .padding(.horizontal, 30)
            Text("故事读完了！").font(.hanzi(34, weight: .heavy))
            Text("story finished · \(correct)/\(questions) questions right").font(.rounded(.subheadline)).foregroundStyle(.secondary)
            Text(revisit ? "replay · no XP" : "+\(20 + correct * 5) XP")
                .font(.rounded(.title2, weight: .heavy)).foregroundStyle(revisit ? Color.secondary : Theme.gold)
            if !fresh.isEmpty {
                Button {
                    store.addToReview(fresh)
                    withAnimation(Theme.bouncy) { added = true }
                } label: {
                    Label(added ? "added \(fresh.count) words ✓" : "add \(fresh.count) new words to review",
                          systemImage: added ? "checkmark" : "plus")
                        .font(.rounded(.headline, weight: .bold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Theme.jade.opacity(0.16), in: Capsule())
                        .foregroundStyle(Theme.jade)
                }
                .disabled(added)
            }
            Spacer()
            BigButton(title: "Done", systemImage: "checkmark") { dismiss() }
                .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
}

/// Today: the day's story (when there is a dated daily one), as a surprise card without its cover.
struct StoryOfTheDayCard: View {
    @Environment(AppStore.self) private var store
    @Environment(ContentSync.self) private var content
    @State private var open: StoryRef?
    @State private var refreshTick = 0

    var body: some View {
        let s = content.generation >= 0 && refreshTick >= 0 ? storyOfTheDay(dayKey: store.todayKey, maxLevel: UInt8(clamping: store.currentLevel)) : nil
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
