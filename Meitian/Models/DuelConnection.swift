import Foundation
import MultipeerConnectivity
import Observation

/// One question sent over the wire (the host builds the list, so both phones see exactly the same thing).
struct WireQuestion: Codable, Hashable {
    var wordId: String
    var kind: Int // 0 = hanzi → meaning, 1 = meaning → hanzi
    var options: [String]

    var question: QuizQuestion? {
        guard let w = WordBank.word(wordId) else { return nil }
        let opts = options.compactMap(WordBank.word)
        guard opts.count == options.count else { return nil }
        return QuizQuestion(word: w, kind: kind == 0 ? .hanziToMeaning : .meaningToHanzi, options: opts)
    }

    /// Built by the shared Rust core.
    static func make(poolIds: [String], count: Int) -> [WireQuestion] {
        battleQuestions(poolIds: poolIds, count: UInt32(clamping: count)).map {
            WireQuestion(wordId: $0.wordId, kind: Int($0.kind), options: $0.optionIds)
        }
    }

    static func make(pool: [Word], count: Int) -> [WireQuestion] {
        make(poolIds: pool.map(\.id), count: count)
    }
}

enum DuelMessage: Codable {
    case hello(PlayerCard)
    case start(mode: DuelMode, questions: [WireQuestion])
    case round(index: Int)
    case answer(index: Int, correct: Bool, ms: Int)
    case result(index: Int, winner: String?, hp: [String: Int], damage: Int, ms: Int)
    case progress(score: Int, done: Bool)
    case finished(winner: String?)
    case backToLobby
    /// Host → guest after a reconnect: the full game state, so both phones agree again.
    case resume(MatchSnapshot)
    case ping
}

struct MatchSnapshot: Codable {
    var mode: DuelMode
    var questions: [WireQuestion]
    var index: Int
    var hp: [String: Int]
    var inGame: Bool
    var finished: Bool
    var winner: String?
}

/// QR payload (built and parsed by the Rust core so Android reads it too):
/// "meitian-duel:<player id>?os=ios&lan=<addresses>&port=<port>"
enum DuelQR {
    static let prefix = "meitian-duel:"
    static func payload(for id: String) -> String { prefix + id }
    static func info(from payload: String) -> DuelQrInfo? { parseDuelQr(code: payload) }
    static func playerId(from payload: String) -> String? { info(from: payload)?.playerId }
}

/// The battle protocol as plain JSON, identical to the Android app's messages. Used on the
/// iPhone ↔ Android Wi‑Fi link (iPhone ↔ iPhone keeps Multipeer with Swift's own encoding).
enum CanonicalWire {
    private static func modeName(_ m: DuelMode) -> String { m == .duel ? "Duel" : "Blitz" }
    private static func mode(_ s: Any?) -> DuelMode { (s as? String) == "Blitz" ? .blitz : .duel }

    private static func questions(_ q: [WireQuestion]) -> [[String: Any]] {
        q.map { ["w": $0.wordId, "k": $0.kind, "o": $0.options] }
    }

    private static func questions(_ any: Any?) -> [WireQuestion] {
        (any as? [[String: Any]] ?? []).compactMap { o in
            guard let w = o["w"] as? String, let k = o["k"] as? Int, let opts = o["o"] as? [String] else { return nil }
            return WireQuestion(wordId: w, kind: k, options: opts)
        }
    }

    private static func hp(_ any: Any?) -> [String: Int] {
        (any as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    private static func winner(_ any: Any?) -> String? {
        guard let s = any as? String, !s.isEmpty else { return nil }
        return s
    }

    static func encode(_ m: DuelMessage) -> String? {
        var o: [String: Any]
        switch m {
        case .hello(let card):
            guard let data = try? JSONEncoder().encode(card),
                  let c = try? JSONSerialization.jsonObject(with: data) else { return nil }
            o = ["t": "hello", "card": c]
        case .start(let mode, let q):
            o = ["t": "start", "mode": modeName(mode), "q": questions(q)]
        case .round(let i):
            o = ["t": "round", "i": i]
        case .answer(let i, let correct, let ms):
            o = ["t": "answer", "i": i, "ok": correct, "ms": ms]
        case .result(let i, let w, let hp, let damage, let ms):
            o = ["t": "result", "i": i, "w": w ?? "", "hp": hp, "d": damage, "ms": ms]
        case .progress(let score, let done):
            o = ["t": "progress", "s": score, "done": done]
        case .finished(let w):
            o = ["t": "finished", "w": w ?? ""]
        case .backToLobby:
            o = ["t": "lobby"]
        case .resume(let s):
            o = ["t": "resume", "mode": modeName(s.mode), "q": questions(s.questions), "i": s.index, "hp": s.hp,
                 "inGame": s.inGame, "finished": s.finished, "w": s.winner ?? ""]
        case .ping:
            o = ["t": "ping"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: o) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String) -> DuelMessage? {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = o["t"] as? String else { return nil }
        let int = { (k: String) -> Int in (o[k] as? NSNumber)?.intValue ?? 0 }
        let bool = { (k: String) -> Bool in (o[k] as? NSNumber)?.boolValue ?? false }
        switch t {
        case "hello":
            guard let c = o["card"], let d = try? JSONSerialization.data(withJSONObject: c),
                  let card = try? JSONDecoder().decode(PlayerCard.self, from: d) else { return nil }
            return .hello(card)
        case "start": return .start(mode: mode(o["mode"]), questions: questions(o["q"]))
        case "round": return .round(index: int("i"))
        case "answer": return .answer(index: int("i"), correct: bool("ok"), ms: int("ms"))
        case "result": return .result(index: int("i"), winner: winner(o["w"]), hp: hp(o["hp"]), damage: int("d"), ms: int("ms"))
        case "progress": return .progress(score: int("s"), done: bool("done"))
        case "finished": return .finished(winner: winner(o["w"]))
        case "lobby": return .backToLobby
        case "resume":
            return .resume(MatchSnapshot(mode: mode(o["mode"]), questions: questions(o["q"]), index: int("i"), hp: hp(o["hp"]),
                                         inGame: bool("inGame"), finished: bool("finished"), winner: winner(o["w"])))
        case "ping": return .ping
        default: return nil
        }
    }
}

/// Receives LAN events on Rust's threads and hands them to the main thread.
private final class LanBridge: LanListener, @unchecked Sendable {
    weak var owner: DuelConnection?
    func onState(state: LanState) { DispatchQueue.main.async { [weak self] in self?.owner?.lanState(state) } }
    func onMessage(json: String) { DispatchQueue.main.async { [weak self] in self?.owner?.lanMessage(json) } }
}

/// Offline, server-free link between two phones (Bluetooth / peer-to-peer Wi‑Fi).
///
/// Pairing: the phone that scanned the other's QR code sends the invitation, and it is only accepted
/// if it carries the scanned player's id, so strangers nearby can't join.
///
/// Staying connected: once paired, both phones remember each other. If the link drops (screen lock,
/// app switch, radio hiccup) they rebuild the session and the player with the smaller id re-invites
/// automatically, so a match can continue instead of ending.
@Observable
final class DuelConnection: NSObject {
    enum State: Equatable { case idle, searching, connecting(String), connected, reconnecting }

    static let serviceType = "meitian-duel"

    private(set) var state: State = .idle
    /// Seconds spent reconnecting (drives the "still trying" UI).
    private(set) var reconnectingSince: Date?
    @ObservationIgnored var onMessage: ((DuelMessage) -> Void)?
    @ObservationIgnored var onReconnected: (() -> Void)?
    @ObservationIgnored var onDropped: (() -> Void)?

    @ObservationIgnored private let myId: String
    @ObservationIgnored private let peer: MCPeerID
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    /// Who we want to be connected to (from a QR scan, or remembered after pairing).
    @ObservationIgnored private var targetId: String?
    /// Set once paired: from then on drops are reconnected automatically.
    @ObservationIgnored private(set) var partnerId: String?
    @ObservationIgnored private var found: [String: MCPeerID] = [:] // player id → peer
    @ObservationIgnored private var pendingInvite: String?
    @ObservationIgnored private var inviteSentAt = Date.distantPast
    @ObservationIgnored private var retryTimer: Timer?
    @ObservationIgnored private var pingTimer: Timer?

    // iPhone ↔ Android over Wi‑Fi / hotspot (shared Rust link)
    @ObservationIgnored private var lan: LanLink?
    @ObservationIgnored private let lanBridge = LanBridge()
    @ObservationIgnored private var lanPort: UInt16 = 0
    @ObservationIgnored private(set) var lanActive = false
    /// A scanned Android phone couldn't be reached over Wi‑Fi (UI shows a hint).
    private(set) var lanUnreachable = false

    /// The code to show: includes this phone's Wi‑Fi addresses so an Android phone can connect.
    var qrPayload: String {
        duelQrPayload(playerId: myId, os: "ios", addrs: lanAddresses(), port: lanPort)
    }

    init(myId: String, name: String) {
        self.myId = myId
        let display = String((name.isEmpty ? "Player" : name).prefix(20))
        peer = MCPeerID(displayName: display)
        super.init()
    }

    deinit {
        retryTimer?.invalidate()
        pingTimer?.invalidate()
    }

    // MARK: lifecycle

    func start() {
        stop()
        newSession()
        startDiscovery()
        state = .searching
        startRetryTimer()
        lanBridge.owner = self
        let link = LanLink(myId: myId, listener: lanBridge)
        lanPort = link.listen()
        lan = link
    }

    func stop() {
        retryTimer?.invalidate(); retryTimer = nil
        pingTimer?.invalidate(); pingTimer = nil
        stopDiscovery()
        session?.delegate = nil
        session?.disconnect()
        session = nil
        found = [:]
        pendingInvite = nil
        targetId = nil
        partnerId = nil
        reconnectingSince = nil
        lan?.stop()
        lan = nil
        lanActive = false
        lanUnreachable = false
        state = .idle
    }

    /// Called after scanning the opponent's QR code.
    func connect(to playerId: String) {
        guard playerId != myId else { return }
        targetId = playerId
        if state == .connected { return }
        state = .connecting(playerId)
        inviteIfNeeded()
    }

    /// After scanning an Android phone's code: connect over Wi‑Fi / hotspot.
    func connectLAN(_ info: DuelQrInfo) {
        guard info.playerId != myId, let lan else { return }
        targetId = info.playerId
        lanUnreachable = false
        if state == .connected { return }
        state = .connecting(info.playerId)
        lan.join(addrs: info.addrs, port: info.port, playerId: info.playerId)
    }

    func send(_ message: DuelMessage) {
        if lanActive {
            if let json = CanonicalWire.encode(message) { lan?.send(json: json) }
            return
        }
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    /// Remember who we're playing (from their hello), so reconnects know whom to look for.
    func setPartner(_ id: String) {
        guard id != myId else { return }
        partnerId = id
    }

    /// Call when the app comes back to the foreground: the radio may have been suspended.
    func wake() {
        guard !lanActive, partnerId != nil, state != .connected else { return } // the LAN link reconnects by itself
        dropped()
    }

    // MARK: LAN events (main thread)

    fileprivate func lanState(_ s: LanState) {
        switch s {
        case .connected:
            let wasReconnecting = state == .reconnecting
            lanActive = true
            lanUnreachable = false
            stopDiscovery()            // Multipeer isn't needed for this match
            retryTimer?.invalidate()
            state = .connected
            reconnectingSince = nil
            if wasReconnecting { onReconnected?() }
        case .reconnecting:
            guard lanActive else { return }
            if state == .connected { onDropped?() }
            state = .reconnecting
            if reconnectingSince == nil { reconnectingSince = .now }
        case .unreachable:
            if !lanActive { lanUnreachable = true }
        default:
            break
        }
    }

    fileprivate func lanMessage(_ json: String) {
        guard lanActive, let msg = CanonicalWire.decode(json) else { return }
        if case .ping = msg { return }
        onMessage?(msg)
    }

    // MARK: internals

    private func newSession() {
        session?.delegate = nil
        session?.disconnect()
        // No encryption: only game moves, names and avatar ids are sent, and encrypted
        // Multipeer sessions are known to drop randomly during the TLS handshake.
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .none)
        s.delegate = self
        session = s
        pendingInvite = nil
    }

    private func startDiscovery() {
        stopDiscovery()
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["id": myId], serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let br = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
    }

    private func stopDiscovery() {
        advertiser?.stopAdvertisingPeer(); advertiser?.delegate = nil; advertiser = nil
        browser?.stopBrowsingForPeers(); browser?.delegate = nil; browser = nil
    }

    /// Should this phone send the invitation? Before pairing: whoever scanned. After pairing: the smaller id,
    /// so both phones never invite each other at the same time.
    private var shouldInvite: Bool {
        if let partner = partnerId { return myId < partner }
        return targetId != nil
    }

    private func inviteIfNeeded() {
        guard let target = targetId ?? partnerId, shouldInvite,
              let p = found[target], let session, session.connectedPeers.isEmpty else { return }
        // don't spam: one invitation in flight at a time
        if pendingInvite == target && Date.now.timeIntervalSince(inviteSentAt) < 12 { return }
        pendingInvite = target
        inviteSentAt = .now
        browser?.invitePeer(p, to: session, withContext: Data(target.utf8), timeout: 10)
    }

    private func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.state != .connected else { return }
            self.inviteIfNeeded()
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        // tiny keep-alive so the radio link doesn't go idle between rounds
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.state == .connected else { return }
            self.send(.ping)
        }
    }

    private func dropped() {
        guard !lanActive else { return }
        if state == .connected { onDropped?() }
        pingTimer?.invalidate()
        state = .reconnecting
        if reconnectingSince == nil { reconnectingSince = .now }
        newSession()
        found = [:]
        startDiscovery() // fresh discovery so we see the partner again
        startRetryTimer()
    }

    private func didConnect(_ peerID: MCPeerID) {
        guard !lanActive else { return }
        lan?.stop() // iPhone ↔ iPhone: Multipeer carries the match
        lan = nil
        let wasReconnecting = state == .reconnecting
        if partnerId == nil, let id = targetId ?? found.first(where: { $0.value == peerID })?.key {
            partnerId = id
        }
        state = .connected
        reconnectingSince = nil
        pendingInvite = nil
        stopDiscovery()
        startPing()
        if wasReconnecting { onReconnected?() }
    }
}

extension DuelConnection: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard session === self.session else { return } // events from an old session
            switch state {
            case .connected:
                self.didConnect(peerID)
            case .notConnected:
                // A declined/expired duplicate invitation also reports .notConnected for the same peer.
                // Only treat it as a real drop if nobody is connected anymore.
                guard session.connectedPeers.isEmpty else { return }
                if self.state == .connected {
                    self.dropped()
                } else {
                    self.pendingInvite = nil
                    self.inviteIfNeeded()
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? JSONDecoder().decode(DuelMessage.self, from: data) else { return }
        if case .ping = msg { return }
        DispatchQueue.main.async { self.onMessage?(msg) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                 certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}

extension DuelConnection: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            // only someone who scanned *my* code (or my paired partner) can join
            guard let context, String(data: context, encoding: .utf8) == self.myId,
                  let session = self.session, session.connectedPeers.isEmpty else {
                invitationHandler(false, nil)
                return
            }
            let inviter = self.found.first(where: { $0.value == peerID })?.key
            if let partner = self.partnerId, let inviter, inviter != partner {
                invitationHandler(false, nil) // someone else
                return
            }
            // both scanned at once: keep only the invitation from the smaller id
            if self.partnerId == nil, let inviter, self.pendingInvite == inviter, inviter > self.myId {
                invitationHandler(false, nil)
                return
            }
            invitationHandler(true, session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

extension DuelConnection: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard let id = info?["id"] else { return }
            self.found[id] = peerID
            self.inviteIfNeeded()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let key = self.found.first(where: { $0.value == peerID })?.key { self.found[key] = nil }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}
