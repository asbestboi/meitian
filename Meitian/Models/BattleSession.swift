import Foundation
import Observation

extension BattlePlayer: Identifiable {
    /// Their player card, once their hello arrived.
    var playerCard: PlayerCard? { card.isEmpty ? nil : PlayerCard(json: card) }
    var picture: String { profile?.avatar ?? "" }
}

/// One battle over a server room: connects the WebSocket to the Rust core's battle engine (which referees, keeps
/// the state and decides everything) and exposes its view to SwiftUI. Reconnects by itself when the network drops.
/// Everything here runs on the main thread.
@Observable
final class BattleSession {
    struct Hit: Equatable {
        var tick: Int
        var attacker: String
        var targets: [String]
        var damage: Int
    }

    let me: PlayerCard
    private(set) var view: BattleView
    /// The last hit that landed (drives the effect animation).
    private(set) var hit: Hit?
    private(set) var coins = 0

    @ObservationIgnored private let engine: Battle
    @ObservationIgnored private let path: String
    /// Records the result and returns the coins it paid.
    @ObservationIgnored private let payOut: (BattleResult, BattlePlayer?) -> Int
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pings = 0
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var stopped = false

    init(path: String, me: PlayerCard, auto: BattleMode?, payOut: @escaping (BattleResult, BattlePlayer?) -> Int) {
        self.path = path
        self.me = me
        self.payOut = payOut
        engine = Battle(card: me.json, autoMode: auto)
        view = engine.view(nowMs: Self.now)
    }

    deinit { timer?.invalidate() }

    private static var now: UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }

    func open() {
        guard timer == nil, !stopped else { return }
        connect()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // keeps running while something scrolls
        timer = t
    }

    private func tick() {
        handle(engine.tick(nowMs: Self.now))
        pings += 1
        if pings % 200 == 0 { socket?.sendPing { _ in } }
    }

    // MARK: socket

    private func connect() {
        guard !stopped else { return }
        let task = OnlineService.socket(path: path)
        task.maximumMessageSize = 1 << 20
        socket = task
        receive(task)
        task.resume()
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, task === self.socket else { return }
                switch result {
                case .success(.string(let text)):
                    self.attempt = 0
                    self.handle(self.engine.onText(text: text, nowMs: Self.now))
                    self.receive(task)
                case .success:
                    self.receive(task)
                case .failure:
                    self.closed(task)
                }
            }
        }
    }

    private func closed(_ task: URLSessionWebSocketTask) {
        socket = nil
        guard !stopped, task.closeCode.rawValue != 4000 else { return } // left, or replaced by a newer connection
        if let http = task.response as? HTTPURLResponse, (400..<500).contains(http.statusCode) {
            stopped = true
            handle(engine.onRefused(status: UInt16(http.statusCode)))
            return
        }
        handle(engine.onClosed())
        let wait = min(8.0, 0.5 * pow(2.0, Double(min(attempt, 4))))
        attempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.connect() }
    }

    // MARK: engine

    private func handle(_ out: [BattleOut]) {
        for o in out {
            switch o {
            case .send(let json):
                socket?.send(.string(json)) { _ in }
            case .sound(let sound):
                SFX.shared.play(sound)
            case .hit(let attacker, let targets, let damage, _):
                hit = Hit(tick: (hit?.tick ?? 0) + 1, attacker: attacker, targets: targets, damage: Int(damage))
                let effect = view.players.first { $0.id == attacker }?.playerCard?.effect ?? "fx.boom"
                // lands with the projectile
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { SFX.shared.playHit(effect) }
            case .finished(let result):
                let players = engine.view(nowMs: Self.now).players
                coins = payOut(result, players.first { $0.id == result.rival })
                if coins > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { SFX.shared.play(.coin) }
                }
            }
        }
        let v = engine.view(nowMs: Self.now)
        if v != view { view = v }
    }

    func start(_ mode: BattleMode) { handle(engine.start(mode: mode, nowMs: Self.now)) }
    func answer(_ a: BattleAnswer) { handle(engine.answer(answer: a, nowMs: Self.now)) }
    func rematch() { handle(engine.rematch()) }

    /// Closes the battle for good.
    func leave() {
        timer?.invalidate()
        timer = nil
        guard !stopped else { return }
        stopped = true
        let task = socket
        socket = nil
        // the socket closes once the goodbye is out
        for o in engine.leave() {
            if case .send(let json) = o {
                task?.send(.string(json)) { _ in task?.cancel(with: .normalClosure, reason: nil) }
            }
        }
    }
}
