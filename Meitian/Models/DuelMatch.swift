import Foundation
import Observation

/// Networked match between two phones. The player with the smaller id is the host and referees
/// each round; answer speed is measured on each phone from when its question appeared.
@Observable
final class DuelMatch {
    enum Phase: Equatable { case lobby, countdown(Int), playing, roundResult, finished }

    static let maxHP = 100
    static let blitzSeconds = 45

    let connection: DuelConnection
    let me: PlayerCard
    private(set) var opponent: PlayerCard?

    var phase: Phase = .lobby
    var mode: DuelMode = .duel
    private(set) var questions: [QuizQuestion] = []
    @ObservationIgnored private var wire: [WireQuestion] = []
    private(set) var index = 0
    private(set) var hp: [String: Int] = [:]

    // round state (shown in the UI)
    var myPick: Word?
    var lockedOut = false
    var roundWinner: String?
    var lastDamage = 0
    var lastHitMs = 0
    var hitTick = 0 // bumps when someone is hit, drives animations

    // blitz
    var myScore = 0
    var opponentScore = 0
    var opponentDone = false
    var myDone = false
    var blitzEnds: Date?
    /// Survival: lives left.
    var lives = 0

    // result
    var winner: String?? = nil // nil = not finished, .some(nil) = draw
    /// Set when the two players' swear-word settings differ: they can't battle.
    var incompatible = false
    var coinsEarned = 0
    var fastestMs: Int?
    var damageDealt = 0

    @ObservationIgnored private var questionShownAt = Date.now
    @ObservationIgnored private var roundAnswers: [String: (correct: Bool, ms: Int)] = [:]
    @ObservationIgnored private var resolveScheduled = false
    @ObservationIgnored private var roundToken = 0
    @ObservationIgnored var onFinish: ((MatchOutcome, Int, Int, Int?) -> Int)? // outcome, bonus, damage, fastest -> coins

    var isHost: Bool { guard let o = opponent else { return false } ; return me.id < o.id }

    init(connection: DuelConnection, me: PlayerCard) {
        self.connection = connection
        self.me = me
        connection.onMessage = { [weak self] msg in self?.handle(msg) }
        connection.onDropped = { [weak self] in self?.dropped() }
        connection.onReconnected = { [weak self] in self?.reconnected() }
        connection.onForfeit = { [weak self] in
            guard let self, self.winner == nil, self.opponent != nil else { return }
            self.finish(winner: self.me.id)   // they left mid-game and didn't come back
        }
    }

    /// Online games start by themselves in the mode picked before matching.
    @ObservationIgnored var autoMode: DuelMode?

    // MARK: connection drops

    private var inGame: Bool {
        switch phase {
        case .countdown, .playing, .roundResult: return true
        default: return false
        }
    }

    /// Link dropped: freeze duel rounds so the host doesn't play on alone.
    private func dropped() {
        if mode.isRounds && inGame { roundToken += 1 }
    }

    /// Link is back: host re-sends the whole game state, then restarts the current round.
    private func reconnected() {
        sayHello()
        if mode.isRace && inGame {
            connection.send(.progress(score: myScore, done: myDone))
        }
        guard isHost else { return }
        let finished = phase == .finished
        connection.send(.resume(MatchSnapshot(mode: mode, questions: wire, index: index, hp: hp,
                                              inGame: inGame, finished: finished, winner: winner ?? nil)))
        if mode.isRounds && inGame, let opp = opponent, let dead = hp.first(where: { $0.value <= 0 })?.key {
            // the knockout landed right before the drop
            let w = dead == me.id ? opp.id : me.id
            connection.send(.finished(winner: w))
            finish(winner: w)
            return
        }
        if mode.isRounds && inGame {
            let token = roundToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, token == self.roundToken, self.connection.state == .connected else { return }
                self.hostNextRound(self.index)
            }
        }
    }

    private func applyResume(_ s: MatchSnapshot) {
        guard !isHost else { return }
        if s.finished {
            if mode != s.mode { mode = s.mode }
            finish(winner: s.winner)
            return
        }
        guard s.inGame else {
            if inGame { backToLobby(notify: false) }
            return
        }
        // Blitz runs independently on each phone (own timer and question position); scores are re-sent separately.
        guard s.mode.isRounds else { return }
        if wire != s.questions {
            wire = s.questions
            questions = s.questions.compactMap(\.question)
        }
        mode = s.mode
        hp = s.hp
        index = s.index
        roundToken += 1
        if mode.isRounds { phase = .roundResult } // host is about to restart the round
    }

    func sayHello() { connection.send(.hello(me)) }

    var currentQuestion: QuizQuestion? { questions.isEmpty ? nil : questions[index % questions.count] }
    func hp(of id: String?) -> Int { id.flatMap { hp[$0] } ?? DuelMatch.maxHP }

    // MARK: host actions

    func hostStart(mode: DuelMode) {
        guard isHost, !incompatible, let opponent else { return }
        // words up to the lower level; street words only when both have them on (rules in the Rust core)
        let pool = battlePool(levelA: UInt8(clamping: me.level), levelB: UInt8(clamping: opponent.level),
                              swearsA: me.swearsOn, swearsB: opponent.swearsOn)
        var list = WireQuestion.make(poolIds: pool, count: mode.isRounds ? 40 : 80)
        if mode == .listen {
            // listening: you hear the word and pick the characters
            list = list.map { WireQuestion(wordId: $0.wordId, kind: 2, options: $0.options) }
        }
        connection.send(.start(mode: mode, questions: list))
        begin(mode: mode, wire: list)
    }

    private func begin(mode: DuelMode, wire: [WireQuestion]) {
        connection.rating = nil
        self.mode = mode
        self.wire = wire
        questions = wire.compactMap(\.question)
        index = 0
        hp = [me.id: DuelMatch.maxHP]
        if let o = opponent { hp[o.id] = DuelMatch.maxHP }
        myScore = 0; opponentScore = 0; myDone = false; opponentDone = false
        lives = mode.lives
        winner = nil; coinsEarned = 0; fastestMs = nil; damageDealt = 0
        roundToken += 1
        countdown(from: 3)
    }

    private func countdown(from n: Int) {
        let token = roundToken
        phase = .countdown(n)
        SFX.shared.play(.tick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, token == self.roundToken else { return }
            if n > 1 { self.countdown(from: n - 1) }
            else if self.mode.isRounds {
                if self.isHost { self.hostNextRound(0) }
            } else {
                self.startBlitz()
            }
        }
    }

    private func hostNextRound(_ i: Int) {
        connection.send(.round(index: i))
        showRound(i)
        let token = roundToken
        // nobody got it in time: move on
        DispatchQueue.main.asyncAfter(deadline: .now() + mode.roundSeconds) { [weak self] in
            guard let self, token == self.roundToken, self.index == i, self.phase == .playing else { return }
            self.resolve(i)
        }
    }

    private func showRound(_ i: Int) {
        index = i
        myPick = nil
        lockedOut = false
        roundWinner = nil
        roundAnswers = [:]
        resolveScheduled = false
        roundToken += 1
        questionShownAt = .now
        phase = .playing
    }

    // MARK: answering

    func pick(_ option: Word) {
        guard phase == .playing, myPick == nil, !lockedOut, !myDone, let q = currentQuestion else { return }
        let correct = option.id == q.word.id
        let ms = Int(Date.now.timeIntervalSince(questionShownAt) * 1000)
        myPick = option
        SFX.shared.play(correct ? .correct : .wrong)
        if mode.isRace {
            blitzAnswer(correct: correct)
            return
        }
        if !correct { lockedOut = true }
        if correct { fastestMs = min(fastestMs ?? .max, ms) }
        if isHost { receive(id: me.id, index: index, correct: correct, ms: ms) }
        else { connection.send(.answer(index: index, correct: correct, ms: ms)) }
    }

    private func receive(id: String, index i: Int, correct: Bool, ms: Int) {
        guard isHost, i == index, phase == .playing, roundAnswers[id] == nil else { return }
        roundAnswers[id] = (correct, ms)
        if correct && !resolveScheduled {
            // short grace window so a faster answer still in flight can win
            resolveScheduled = true
            let token = roundToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, token == self.roundToken else { return }
                self.resolve(i)
            }
        } else if roundAnswers.count == 2 && !roundAnswers.values.contains(where: { $0.correct }) {
            resolve(i)
        }
    }

    private func resolve(_ i: Int) {
        guard isHost, phase == .playing, let opp = opponent else { return }
        let best = roundAnswers.filter { $0.value.correct }.min { $0.value.ms < $1.value.ms }
        var damage = 0
        var ms = 0
        if let best {
            ms = best.value.ms
            damage = mode.damage(reactionMs: ms) // duel: 12–22, faster hits harder; sudden death: 34
            let target = best.key == me.id ? opp.id : me.id
            hp[target] = max(0, hp(of: target) - damage)
        }
        connection.send(.result(index: i, winner: best?.key, hp: hp, damage: damage, ms: ms))
        applyResult(winner: best?.key, hp: hp, damage: damage, ms: ms)

        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, token == self.roundToken else { return }
            if let dead = self.hp.first(where: { $0.value <= 0 })?.key {
                let w = dead == self.me.id ? opp.id : self.me.id
                self.connection.send(.finished(winner: w))
                self.finish(winner: w)
            } else {
                self.hostNextRound(i + 1)
            }
        }
    }

    private func applyResult(winner w: String?, hp newHP: [String: Int], damage: Int, ms: Int) {
        hp = newHP
        roundWinner = w
        lastDamage = damage
        lastHitMs = ms
        if w == me.id { damageDealt += damage }
        if w != nil { hitTick += 1; SFX.shared.play(.hit) }
        phase = .roundResult
    }

    // MARK: blitz

    private func startBlitz() {
        showRound(0)
        blitzEnds = Date.now.addingTimeInterval(TimeInterval(mode.raceSeconds))
        let token = roundToken
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(mode.raceSeconds)) { [weak self] in
            guard let self, self.mode.isRace, !self.myDone, token == self.roundToken else { return }
            self.myDone = true
            self.connection.send(.progress(score: self.myScore, done: true))
            self.checkBlitzEnd()
        }
    }

    private func blitzAnswer(correct: Bool) {
        if correct {
            myScore += 1
            connection.send(.progress(score: myScore, done: false))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.blitzNext() }
        } else {
            lockedOut = true // 1 s penalty
            if mode == .survival {
                lives -= 1
                if lives <= 0 {
                    // out of lives: you're done, your score stands
                    myDone = true
                    connection.send(.progress(score: myScore, done: true))
                    checkBlitzEnd()
                    return
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.blitzNext() }
        }
    }

    private func blitzNext() {
        guard mode.isRace, !myDone, phase == .playing else { return }
        index += 1
        myPick = nil
        lockedOut = false
    }

    private func checkBlitzEnd() {
        guard mode.isRace, myDone, opponentDone, winner == nil, let opp = opponent else { return }
        let w: String? = myScore == opponentScore ? nil : (myScore > opponentScore ? me.id : opp.id)
        finish(winner: w)
    }

    // MARK: finishing

    private func finish(winner w: String?) {
        guard winner == nil else { return }
        roundToken += 1
        winner = .some(w)
        phase = .finished
        let outcome: MatchOutcome = w == nil ? .draw : (w == me.id ? .win : .loss)
        let bonus = mode.isRounds ? hp(of: me.id) / 5 : myScore
        coinsEarned = onFinish?(outcome, bonus, damageDealt, fastestMs) ?? 0
        if outcome == .loss { SFX.shared.play(.lose) }
        if connection.onlineActive { connection.reportOnline(won: outcome == .draw ? nil : outcome == .win) }
    }

    func backToLobby(notify: Bool = true) {
        roundToken += 1
        if notify { connection.send(.backToLobby) }
        phase = .lobby
        winner = nil
    }

    // MARK: incoming

    private func handle(_ msg: DuelMessage) {
        switch msg {
        case .hello(let card) where !canMatch(mySwears: me.swearsOn, theirSwears: card.swearsOn):
            // swears on and swears off don't mix: refuse the match on both phones
            if opponent == nil { sayHello() }
            opponent = card
            incompatible = true
        case .hello(let card):
            let first = opponent == nil
            opponent = card
            connection.setPartner(card.id)
            if first { sayHello() } // make sure they have mine too
            if let m = autoMode, isHost, phase == .lobby {
                autoMode = nil
                hostStart(mode: m)
            }
        case .start(let mode, let wire):
            begin(mode: mode, wire: wire)
        case .round(let i):
            if !isHost { showRound(i) }
        case .answer(let i, let correct, let ms):
            if let o = opponent { receive(id: o.id, index: i, correct: correct, ms: ms) }
        case .result(_, let w, let newHP, let damage, let ms):
            if !isHost { applyResult(winner: w, hp: newHP, damage: damage, ms: ms) }
        case .progress(let score, let done):
            opponentScore = score
            if done { opponentDone = true; checkBlitzEnd() }
        case .finished(let w):
            finish(winner: w)
        case .backToLobby:
            backToLobby(notify: false)
        case .resume(let snapshot):
            applyResume(snapshot)
        case .ping:
            break
        }
    }
}
