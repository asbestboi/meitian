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

    static func make(pool: [Word], count: Int) -> [WireQuestion] {
        var out: [WireQuestion] = []
        var bag: [Word] = []
        for i in 0..<count {
            if bag.isEmpty { bag = pool.shuffled() }
            let w = bag.removeLast()
            let q = QuizQuestion.make(for: w, kind: i % 2 == 0 ? .hanziToMeaning : .meaningToHanzi, pool: pool)
            out.append(WireQuestion(wordId: w.id, kind: i % 2, options: q.options.map(\.id)))
        }
        return out
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

/// QR payload: "meitian-duel:<player id>"
enum DuelQR {
    static let prefix = "meitian-duel:"
    static func payload(for id: String) -> String { prefix + id }
    static func playerId(from payload: String) -> String? {
        guard payload.hasPrefix(prefix) else { return nil }
        let id = String(payload.dropFirst(prefix.count))
        return UUID(uuidString: id) != nil ? id : nil
    }
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

    func send(_ message: DuelMessage) {
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
        guard partnerId != nil, state != .connected else { return }
        dropped()
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
