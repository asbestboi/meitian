import PhotosUI
import SwiftUI

/// Online play: quick match against anyone, friends by code, leaderboards, your public profile.
struct OnlineHub: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @Environment(\.dismiss) private var dismiss
    @State private var online = OnlineService.shared
    @State private var stage: Stage = .hub

    enum Stage: Equatable {
        case hub
        case searching(DuelMode)
        case playing(room: String, mode: DuelMode, opponent: OnlineProfile?)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch stage {
            case .hub:
                if online.signedIn {
                    OnlineTabs(close: { dismiss() },
                               play: { stage = .searching($0) },
                               join: { stage = .playing(room: $0, mode: $1, opponent: $2) })
                } else {
                    OnlineSetup(close: { dismiss() })
                }
            case .searching(let mode):
                QuickMatchSearch(mode: mode, cancel: { stage = .hub }) { room, opponent in
                    stage = .playing(room: room, mode: mode, opponent: opponent)
                }
            case .playing(let room, let mode, let opponent):
                OnlineMatchView(room: room, mode: mode, opponentProfile: opponent) { stage = .hub }
            }
        }
        .animation(Theme.spring, value: stage)
        .task {
            try? await online.refreshMe()
            await online.sync(store: store, arena: arena, force: true)
        }
    }
}

// MARK: - sign up

private struct OnlineSetup: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    let close: () -> Void
    @State private var name = ""
    @State private var code = ""
    @State private var recovering = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("go online", close: close)
                VStack(alignment: .leading, spacing: 8) {
                    Text("🌍").font(.system(size: 44))
                    Text("battle anyone, anywhere").font(.rounded(.title2, weight: .heavy))
                    Text("Quick matches against iPhone and Android players, friends by code, weekly leaderboards. No email or password: just a nickname.")
                        .font(.rounded(.subheadline)).opacity(0.92)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .streetBlock(Theme.skyGradient)

                if !recovering {
                    TextField("nickname", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.rounded(.title3, weight: .semibold))
                        .cardSurface(padding: 16)
                        .onChange(of: name) { _, v in if v.count > 16 { name = String(v.prefix(16)) } }
                    Text("2–16 letters or numbers. Everyone can see it.").font(.rounded(.footnote)).foregroundStyle(.secondary)
                    BigButton(title: busy ? "…" : "create my profile", gradient: Theme.skyGradient, enabled: !busy && nicknameOk(name: name)) {
                        run { try await OnlineService.shared.register(nickname: name) }
                    }
                    Button("I already have a profile (recovery code)") { recovering = true; error = nil }
                        .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.red)
                } else {
                    TextField("recovery code", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.rounded(.body, weight: .semibold))
                        .cardSurface(padding: 16)
                    Text("Find it on your old phone: online → me → recovery code.").font(.rounded(.footnote)).foregroundStyle(.secondary)
                    BigButton(title: busy ? "…" : "sign in", enabled: !busy && code.contains(".")) {
                        run { try await OnlineService.shared.recover(code: code) }
                    }
                    Button("back") { recovering = false }.font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
                }
                if let error { Text(error).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.red) }
            }
            .padding(20)
        }
        .onAppear { if name.isEmpty { name = String(store.profile.name.trimmingCharacters(in: .whitespaces).prefix(16)) } }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = nil
        Task {
            do {
                try await work()
                await OnlineService.shared.sync(store: store, arena: arena, force: true)
            } catch {
                self.error = OnlineService.describe(error)
            }
            busy = false
        }
    }
}

private func header(_ title: String, close: @escaping () -> Void) -> some View {
    HStack {
        Button(action: close) {
            Image(systemName: "xmark").font(.headline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .foregroundStyle(.primary)
        .accessibilityLabel("Close")
        Spacer()
        Text(title).font(.rounded(.title3, weight: .heavy))
        Spacer()
        Color.clear.frame(width: 40, height: 40)
    }
}

// MARK: - tabs

private struct OnlineTabs: View {
    let close: () -> Void
    let play: (DuelMode) -> Void
    let join: (String, DuelMode, OnlineProfile?) -> Void
    @State private var tab = 0
    private var online: OnlineService { .shared }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                header("online", close: close)
                if let me = online.profile { ProfileRow(profile: me, trailing: "\(me.rating)") }
                HStack(spacing: 8) {
                    let requests = Int(online.inbox?.requests ?? 0)
                    ForEach(Array(["play", requests > 0 ? "friends (\(requests))" : "friends", "ranks", "me"].enumerated()), id: \.offset) { i, t in
                        Button { withAnimation(Theme.spring) { tab = i } } label: {
                            Text(t).font(.rounded(.footnote, weight: .bold)).lineLimit(1)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .foregroundStyle(tab == i ? Theme.background : .primary)
                                .background(tab == i ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card), in: Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            Group {
                switch tab {
                case 0: PlayTab(play: play, join: join)
                case 1: FriendsTab(join: join)
                case 2: RanksTab()
                default: MeTab()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task {
            // incoming challenges and friend requests while this screen is open
            while !Task.isCancelled {
                await OnlineService.shared.refreshInbox()
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }
}

struct OnlineAvatar: View {
    let profile: OnlineProfile?
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(Theme.chrome)
            if let url = OnlineService.shared.avatarURL(profile) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { ProgressView() }
            } else {
                Text(Catalog.item(profile?.cosmeticAvatar ?? "")?.symbol ?? "🐣").font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct ProfileRow: View {
    let profile: OnlineProfile
    var trailing: String? = nil
    var rank: Int? = nil
    var highlight = false

    var body: some View {
        HStack(spacing: 12) {
            if let rank { Text("\(rank)").font(.rounded(.headline, weight: .heavy)).foregroundStyle(.secondary).frame(minWidth: 26) }
            OnlineAvatar(profile: profile)
                .overlay(alignment: .bottomTrailing) {
                    if profile.online { Circle().fill(Theme.jade).frame(width: 12, height: 12) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(profile.nickname) #\(profile.tag)").font(.rounded(.headline, weight: .bold)).lineLimit(1)
                Text("HSK \(profile.level) · 🔥 \(profile.streak) · \(profile.wins)–\(profile.losses)")
                    .font(.rounded(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(.rounded(.headline, weight: .heavy)) }
        }
        .padding(10)
        .background(highlight ? AnyShapeStyle(Theme.gold.opacity(0.18)) : AnyShapeStyle(Theme.card),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ModePicker: View {
    @Binding var mode: DuelMode
    var body: some View {
        HStack(spacing: 6) {
            ForEach(DuelMode.allCases) { m in
                Button { withAnimation(Theme.spring) { mode = m } } label: {
                    VStack(spacing: 2) {
                        Text(m.emoji).font(.title3)
                        Text(m.wireName.lowercased()).font(.rounded(.caption2, weight: .bold)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(mode == m ? Theme.background : .primary)
                    .background(mode == m ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
        }
    }
}

private struct PlayTab: View {
    let play: (DuelMode) -> Void
    let join: (String, DuelMode, OnlineProfile?) -> Void
    @State private var mode: DuelMode = .duel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(OnlineService.shared.inbox?.challenges ?? [], id: \.room) { c in
                    ChallengeCard(challenge: c, join: join)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("quick match").font(.rounded(.title2, weight: .heavy))
                    Text("Battle a random player near your rating, on iPhone or Android.").font(.rounded(.subheadline)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .streetBlock(Theme.warmGradient)
                ModePicker(mode: $mode)
                Text(mode.blurb).font(.rounded(.footnote)).foregroundStyle(.secondary)
                BigButton(title: "find an opponent", gradient: Theme.warmGradient) { play(mode) }
                Text("Wins and losses move your rating. Both phones have to agree on the result for it to count.")
                    .font(.rounded(.caption)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
    }
}

private struct ChallengeCard: View {
    let challenge: OnlineChallenge
    let join: (String, DuelMode, OnlineProfile?) -> Void

    var body: some View {
        let mode = DuelMode(wireName: challenge.mode)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OnlineAvatar(profile: challenge.from)
                Text("\(challenge.from.nickname) challenges you to \(mode.title.lowercased()) \(mode.emoji)")
                    .font(.rounded(.headline, weight: .bold))
            }
            HStack(spacing: 10) {
                BigButton(title: "accept", gradient: Theme.jadeGradient) { join(challenge.room, mode, challenge.from) }
                BigButton(title: "no thanks") {
                    Task {
                        try? await OnlineService.shared.decline(challenge.room)
                        await OnlineService.shared.refreshInbox()
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .streetBlock(Theme.pinkGradient, padding: 16)
    }
}

private struct FriendsTab: View {
    let join: (String, DuelMode, OnlineProfile?) -> Void
    @State private var data: OnlineFriends?
    @State private var code = ""
    @State private var note: String?
    @State private var mode: DuelMode = .duel
    @State private var viewing: OnlineProfile?
    private var online: OnlineService { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let myCode = online.profile?.friendCode ?? ""
                VStack(alignment: .leading, spacing: 10) {
                    Text("your friend code").font(.rounded(.footnote, weight: .bold)).foregroundStyle(.secondary)
                    HStack {
                        Text(myCode).font(.system(size: 30, weight: .heavy, design: .rounded)).textSelection(.enabled)
                        Spacer()
                        ShareLink(item: "Add me on Měitiān: \(myCode)") { Pill(text: "share", color: Theme.red, systemImage: "square.and.arrow.up") }
                    }
                    HStack {
                        TextField("friend's code", text: $code)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.rounded(.headline, weight: .semibold))
                            .padding(12)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button {
                            Task {
                                do { note = try await online.addFriend(code: code) ? "You're friends now 🎉" : "Request sent. They'll see it under friends." }
                                catch { note = OnlineService.describe(error) }
                                code = ""
                                await reload()
                            }
                        } label: { Pill(text: "add", color: Theme.jade, systemImage: "person.badge.plus") }
                        .disabled(code.count < 4)
                    }
                }
                .cardSurface(padding: 14)
                if let note { Text(note).font(.rounded(.subheadline, weight: .bold)) }

                ForEach(data?.incoming ?? [], id: \.id) { p in
                    HStack {
                        ProfileRow(profile: p, highlight: true)
                        Button {
                            Task { try? await online.accept(p.id); await reload(); await online.refreshInbox() }
                        } label: { Pill(text: "accept", color: Theme.jade) }
                    }
                }
                let friends = data?.friends ?? []
                if !friends.isEmpty {
                    Text("challenge mode").font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6)
                    ModePicker(mode: $mode)
                }
                ForEach(friends, id: \.id) { p in
                    HStack {
                        Button { viewing = p } label: { ProfileRow(profile: p) }.buttonStyle(.plain)
                        Button {
                            Task {
                                do { join(try await online.challenge(p.id, mode: mode), mode, p) }
                                catch { note = OnlineService.describe(error) }
                            }
                        } label: { Pill(text: "battle", color: Theme.red, systemImage: "bolt.fill") }
                    }
                }
                ForEach(data?.outgoing ?? [], id: \.id) { p in ProfileRow(profile: p, trailing: "⏳") }
                if let data, data.friends.isEmpty, data.incoming.isEmpty {
                    Text("No friends yet. Share your code, or type a friend's code above.")
                        .font(.rounded(.subheadline)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(20)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .sheet(item: $viewing) { p in
            ProfileSheet(profile: p, onRemove: {
                Task { try? await online.unfriend(p.id); viewing = nil; await reload() }
            })
            .presentationDetents([.medium])
        }
    }

    private func reload() async {
        do { data = try await online.friends() } catch { note = OnlineService.describe(error) }
    }
}

extension OnlineProfile: Identifiable {}

private struct ProfileSheet: View {
    let profile: OnlineProfile
    var onRemove: (() -> Void)? = nil
    @State private var reported = false

    var body: some View {
        VStack(spacing: 12) {
            OnlineAvatar(profile: profile, size: 110)
            Text("\(profile.nickname) #\(profile.tag)").font(.rounded(.title2, weight: .heavy))
            HStack(spacing: 8) {
                stat("HSK \(profile.level)", "level"); stat("\(profile.streak)", "streak"); stat("\(profile.rating)", "rating")
            }
            HStack(spacing: 8) {
                stat("\(profile.wins)", "wins"); stat("\(profile.losses)", "losses"); stat("\(profile.xpWeek)", "xp this week")
            }
            let gear = [profile.cosmeticAura, profile.cosmeticFx].compactMap { Catalog.item($0) }.map { "\($0.symbol) \($0.name)" }
            if !gear.isEmpty { Text(gear.joined(separator: " · ")).font(.rounded(.footnote)).foregroundStyle(.secondary) }
            if let onRemove {
                Button("remove friend", action: onRemove).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.secondary)
            }
            Button(reported ? "reported, thanks" : "report picture or name") {
                Task { try? await OnlineService.shared.report(profile.id); reported = true }
            }
            .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.red).disabled(reported)
        }
        .padding(24)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.rounded(.headline, weight: .heavy))
            Text(l).font(.rounded(.caption2, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RanksTab: View {
    @State private var rating = false
    @State private var friends = false
    @State private var board: Leaderboard?
    @State private var error: String?
    @State private var viewing: OnlineProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button { rating.toggle() } label: { Pill(text: rating ? "battle rating" : "xp this week", color: Theme.red, systemImage: "arrow.left.arrow.right") }
                    Button { friends.toggle() } label: { Pill(text: friends ? "friends" : "everyone", color: Theme.jade, systemImage: "arrow.left.arrow.right") }
                }
                if let error { Text(error).font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.red) }
                if board == nil && error == nil { ProgressView().frame(maxWidth: .infinity).padding(30) }
                if let board {
                    let mine = board.me.profile.id
                    if !board.top.contains(where: { $0.profile.id == mine }) {
                        ProfileRow(profile: board.me.profile, trailing: value(board.me.profile), rank: Int(board.me.rank), highlight: true)
                    }
                    ForEach(board.top, id: \.profile.id) { e in
                        Button { viewing = e.profile } label: {
                            ProfileRow(profile: e.profile, trailing: value(e.profile), rank: Int(e.rank), highlight: e.profile.id == mine)
                        }
                        .buttonStyle(.plain)
                    }
                    if board.top.isEmpty {
                        Text("Nobody here yet this week. Learn something and you're first!").font(.rounded(.subheadline)).foregroundStyle(.secondary)
                    }
                    Text("The weekly board starts again every Monday.").font(.rounded(.caption)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .task(id: "\(rating)-\(friends)") {
            board = nil
            error = nil
            do { board = try await OnlineService.shared.leaderboard(rating: rating, friends: friends) }
            catch { self.error = OnlineService.describe(error) }
        }
        .sheet(item: $viewing) { ProfileSheet(profile: $0).presentationDetents([.medium]) }
    }

    private func value(_ p: OnlineProfile) -> String { rating ? "\(p.rating)" : "\(p.xpWeek) xp" }
}

private struct MeTab: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    @State private var name = ""
    @State private var note: String?
    @State private var showCode = false
    @State private var confirmDelete = false
    @State private var photo: PhotosPickerItem?
    private var online: OnlineService { .shared }

    var body: some View {
        ScrollView {
            if let me = online.profile {
                VStack(spacing: 14) {
                    PhotosPicker(selection: $photo, matching: .images) { OnlineAvatar(profile: me, size: 120) }
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $photo, matching: .images) { Pill(text: "change picture", color: Theme.red, systemImage: "photo") }
                        if !me.avatar.isEmpty {
                            Button {
                                Task {
                                    do { try await online.removeAvatar(); note = "Picture deleted." } catch { note = OnlineService.describe(error) }
                                }
                            } label: { Pill(text: "remove", color: .secondary) }
                        }
                    }
                    HStack {
                        TextField("nickname", text: $name)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.rounded(.headline, weight: .semibold))
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button {
                            Task {
                                do { try await online.rename(name); note = "Saved." } catch { note = OnlineService.describe(error) }
                            }
                        } label: { Pill(text: "save", color: Theme.jade) }
                        .disabled(!nicknameOk(name: name) || name == me.nickname)
                    }
                    if let note { Text(note).font(.rounded(.subheadline, weight: .bold)) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("recovery code").font(.rounded(.headline, weight: .bold))
                        Text("Your profile has no password. This code signs you in on a new phone. Keep it secret.")
                            .font(.rounded(.caption)).foregroundStyle(.secondary)
                        if showCode {
                            Text(online.token ?? "").font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = online.token
                                note = "Copied."
                            } label: { Pill(text: "copy", color: Theme.red, systemImage: "doc.on.doc") }
                        } else {
                            Button { showCode = true } label: { Pill(text: "show", color: Theme.red, systemImage: "eye") }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(padding: 14)
                    Button(confirmDelete ? "tap again to delete your online profile for good" : "delete online profile") {
                        if !confirmDelete { confirmDelete = true; return }
                        Task {
                            do { try await online.deleteAccount() } catch { note = OnlineService.describe(error) }
                        }
                    }
                    .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(Theme.red)
                    Text("Your lessons and coins stay on this phone either way.").font(.rounded(.caption)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
                .onAppear { if name.isEmpty { name = me.nickname } }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        note = "Couldn't read that picture."
                        return
                    }
                    try await online.uploadAvatar(image)
                    note = "New picture saved (the old one is deleted)."
                } catch {
                    note = OnlineService.describe(error)
                }
                photo = nil
            }
        }
        .task { await online.sync(store: store, arena: arena) }
    }
}

// MARK: - quick match

private struct QuickMatchSearch: View {
    let mode: DuelMode
    let cancel: () -> Void
    let found: (String, OnlineProfile) -> Void
    @State private var problem: String?
    @State private var started = Date.now
    @State private var attempt = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(mode.emoji).font(.system(size: 64))
                .frame(width: 150, height: 150)
                .background(mode.gradient, in: Circle())
                .scaleEffect(pulse ? 1.12 : 0.88)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Text(problem ?? "looking for an opponent…").font(.rounded(.title2, weight: .heavy)).multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                Text(problem != nil ? "Check your internet and try again."
                     : "\(mode.title) · \(Int(tl.date.timeIntervalSince(started)))s. The search widens the longer you wait.")
                    .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            if problem != nil { BigButton(title: "try again") { problem = nil; attempt += 1 } }
            BigButton(title: "cancel", action: cancel)
        }
        .padding(24)
        .onAppear { pulse = true }
        .task(id: attempt) { await search() }
    }

    private func search() async {
        started = .now
        let task = OnlineService.socket(path: "/v1/queue?mode=\(mode.wireName)&swears=\(Prefs.swearsOn ? 1 : 0)")
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        while !Task.isCancelled {
            do {
                guard case .string(let text) = try await task.receive() else { continue }
                if case .matched(let room, _, let opponent) = onlineEvent(json: text) {
                    found(room, opponent)
                    return
                }
            } catch {
                if !Task.isCancelled { problem = "Lost the connection to the server." }
                return
            }
        }
    }
}

// MARK: - an online battle

private struct OnlineMatchView: View {
    @Environment(AppStore.self) private var store
    @Environment(ArenaStore.self) private var arena
    let room: String
    let mode: DuelMode
    let opponentProfile: OnlineProfile?
    let close: () -> Void
    @State private var connection: DuelConnection?
    @State private var match: DuelMatch?
    @State private var confetti = 0

    var body: some View {
        ZStack {
            if let match, let connection, match.opponent != nil {
                MatchScreen(match: match, confetti: $confetti, close: leave)
                    .disabled(connection.state != .connected && match.winner == nil)
                    .blur(radius: connection.state == .connected || match.winner != nil ? 0 : 6)
                if let r = connection.rating {
                    Text(r.counted ? "rating \(r.rating) (\(r.delta >= 0 ? "+" : "")\(r.delta))" : "the phones disagreed: no rating change")
                        .font(.rounded(.subheadline, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.ink, in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if connection.state != .connected && match.winner == nil {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Waiting for \(match.opponent?.name ?? "them") to reconnect…").font(.rounded(.headline, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("If they're gone for 30 seconds, you win.").font(.rounded(.subheadline)).foregroundStyle(.secondary)
                        Button("Leave match", role: .destructive, action: leave).font(.rounded(.headline, weight: .bold))
                    }
                    .padding(24)
                    .frame(maxWidth: 340)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    OnlineAvatar(profile: opponentProfile, size: 110)
                    Text(opponentProfile.map { "\($0.nickname) #\($0.tag)" } ?? "opponent").font(.rounded(.title2, weight: .heavy))
                    Text(connection?.onlineGone == true ? "This battle isn't available any more (declined or expired)."
                         : connection?.peerWaiting == true ? "Waiting for them to join… \(mode.emoji) \(mode.title)" : "Connecting…")
                        .font(.rounded(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if connection?.onlineGone != true { ProgressView() }
                    Spacer()
                    BigButton(title: "leave", action: leave)
                }
                .padding(24)
            }
            ConfettiView(trigger: confetti)
        }
        .animation(Theme.spring, value: match?.opponent)
        .animation(Theme.spring, value: connection?.rating)
        .onAppear {
            setUp()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            connection?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            Task { await OnlineService.shared.sync(store: store, arena: arena, force: true) }
        }
        .onChange(of: connection?.state) { _, s in
            if s == .connected { match?.sayHello() }
        }
    }

    private func setUp() {
        guard connection == nil else { return }
        let card = arena.card(name: store.profile.name, level: store.currentLevel, wordsLearned: store.cards.count)
        let c = DuelConnection(myId: arena.playerId, name: store.profile.name)
        let m = DuelMatch(connection: c, me: card)
        m.autoMode = mode
        m.onFinish = { [arena, weak m] outcome, bonus, damage, fastest in
            guard let m, let opp = m.opponent else { return 0 }
            return arena.record(outcome, mode: m.mode, against: opp, bonus: bonus, damage: damage, fastest: fastest)
        }
        c.connectOnline(room: room)
        connection = c
        match = m
    }

    private func leave() {
        connection?.stop()
        close()
    }
}
