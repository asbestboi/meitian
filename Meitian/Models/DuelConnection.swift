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
/// Both phones advertise and browse. The phone that scanned the other's QR code sends the invitation,
/// and it only gets accepted if it carries the scanned player's id, so strangers nearby can't join.
@Observable
final class DuelConnection: NSObject {
    enum State: Equatable { case idle, searching, connecting(String), connected, lost }

    static let serviceType = "meitian-duel"

    private(set) var state: State = .idle
    var onMessage: ((DuelMessage) -> Void)?

    private let myId: String
    private let peer: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var targetId: String?
    private var found: [String: MCPeerID] = [:] // player id → peer
    private var invited: Set<String> = []
    private var connectedPeer: MCPeerID?

    init(myId: String, name: String) {
        self.myId = myId
        let display = String((name.isEmpty ? "Player" : name).prefix(20))
        peer = MCPeerID(displayName: display)
        super.init()
    }

    func start() {
        stop()
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["id": myId], serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        let br = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
        state = .searching
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        found = [:]
        invited = []
        connectedPeer = nil
        targetId = nil
        state = .idle
    }

    /// Called after scanning the opponent's QR code.
    func connect(to playerId: String) {
        guard playerId != myId else { return }
        targetId = playerId
        if case .connected = state { return }
        state = .connecting(playerId)
        inviteIfFound()
    }

    func send(_ message: DuelMessage) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func inviteIfFound() {
        guard let target = targetId, let p = found[target], let session, !invited.contains(target) else { return }
        invited.insert(target)
        browser?.invitePeer(p, to: session, withContext: Data(target.utf8), timeout: 20)
    }
}

extension DuelConnection: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            guard session === self.session else { return }
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.state = .connected
                // stay discoverable no longer
                self.advertiser?.stopAdvertisingPeer()
                self.browser?.stopBrowsingForPeers()
            case .notConnected:
                if peerID == self.connectedPeer {
                    self.connectedPeer = nil
                    self.state = .lost
                } else if case .connecting = self.state {
                    // invitation failed: allow another try
                    if let t = self.targetId { self.invited.remove(t) }
                    self.inviteIfFound()
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
        DispatchQueue.main.async { self.onMessage?(msg) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension DuelConnection: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            // only someone who scanned *my* code can join
            guard let context, String(data: context, encoding: .utf8) == self.myId,
                  let session = self.session, session.connectedPeers.isEmpty else {
                invitationHandler(false, nil)
                return
            }
            // both scanned at once: the invitation from the smaller id wins
            if let inviter = self.found.first(where: { $0.value == peerID })?.key,
               self.invited.contains(inviter), inviter > self.myId {
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
            self.inviteIfFound()
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let key = self.found.first(where: { $0.value == peerID })?.key { self.found[key] = nil }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}
