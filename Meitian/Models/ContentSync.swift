import CryptoKit
import Foundation
import Observation

/// Downloads learning content (HSK words, sentences, stories) from the meitian-content site,
/// caches it in Application Support and feeds it to the Rust core. Fully usable offline.
@MainActor
@Observable
final class ContentSync {
    enum Status: Equatable {
        case idle
        case checking
        case downloading(done: Int, total: Int)
        case ready
        case failed(String)
    }

    static let defaultURL = "https://asbestboi.github.io/meitian-content/"
    static let urlKey = "contentURL"
    static let allLevelsKey = "contentAllLevels"
    private static let checkedKey = "contentCheckedAt"

    private(set) var status: Status = .idle
    private(set) var stats = contentStats()
    private(set) var credits: [String] = []
    private(set) var version = ""
    /// Bumped after new content is loaded so views can refresh.
    private(set) var generation = 0

    private var loadedFiles: Set<String> = []
    private var running = false

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("content", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    var baseURL: String {
        let s = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        return s.isEmpty ? Self.defaultURL : s
    }

    var cacheBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Load the cache, then refresh from the network if the last check is over a day old.
    func start(level: Int) async {
        await loadCached()
        let last = UserDefaults.standard.double(forKey: Self.checkedKey)
        if Date.now.timeIntervalSince1970 - last > 24 * 3600 || stats.sentences == 0 {
            await refresh(level: level)
        } else {
            status = .ready
        }
    }

    /// Load every pack already on disk (as listed by the cached manifest).
    func loadCached() async {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? parseManifest(json: String(decoding: data, as: UTF8.self)) else { return }
        credits = manifest.credits
        version = manifest.version
        let present = manifest.packs.filter { FileManager.default.fileExists(atPath: file(for: $0).path) }
        await load(present)
    }

    /// Fetch the manifest and download missing or changed packs for this level (or all levels).
    func refresh(level: Int, force: Bool = false) async {
        guard !running else { return }
        running = true
        defer { running = false }
        status = .checking
        do {
            guard let base = URL(string: baseURL.hasSuffix("/") ? baseURL : baseURL + "/") else {
                throw URLError(.badURL)
            }
            let manifestData = try await fetch(base.appendingPathComponent("manifest.json"))
            let manifest = try parseManifest(json: String(decoding: manifestData, as: UTF8.self))
            let all = UserDefaults.standard.bool(forKey: Self.allLevelsKey)
            let wanted = packsForLevel(manifest: manifest, level: UInt8(clamping: max(level, 1)), all: all)
            let missing = wanted.filter { force || !isCurrent($0) }
            var done = 0
            for pack in missing {
                status = .downloading(done: done, total: missing.count)
                guard let url = URL(string: pack.url, relativeTo: base) else { continue }
                let data = try await fetch(url)
                if !pack.sha256.isEmpty && sha256(data) != pack.sha256 {
                    throw ContentSyncError.checksum(pack.id)
                }
                try data.write(to: file(for: pack), options: .atomic)
                loadedFiles.remove(pack.url)
                done += 1
            }
            try manifestData.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
            credits = manifest.credits
            version = manifest.version
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.checkedKey)
            await load(wanted)
            status = .ready
        } catch {
            status = stats.sentences > 0 ? .ready : .failed(Self.describe(error))
        }
    }

    /// Delete downloaded packs and go back to the bundled words.
    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: Self.checkedKey)
        contentClear()
        loadedFiles = []
        version = ""
        afterLoad()
        status = .idle
    }

    // MARK: helpers

    private func load(_ packs: [PackInfo]) async {
        let todo = packs.filter { !loadedFiles.contains($0.url) }
        guard !todo.isEmpty else { return }
        let files = todo.map { ($0.kind, $0.url, file(for: $0)) }
        // Parsing a few MB of JSON is quick but not free: keep it off the main thread.
        let ok: [String] = await Task.detached(priority: .userInitiated) {
            var ok: [String] = []
            // words before sentences/stories, so tokens resolve to word ids
            for (kind, url, path) in files.sorted(by: { ($0.0 == "words" ? 0 : 1) < ($1.0 == "words" ? 0 : 1) }) {
                guard let data = try? Data(contentsOf: path) else { continue }
                if (try? contentLoad(kind: kind, json: String(decoding: data, as: UTF8.self))) != nil { ok.append(url) }
            }
            return ok
        }.value
        loadedFiles.formUnion(ok)
        afterLoad()
    }

    private func afterLoad() {
        WordBank.store.reload()
        stats = contentStats()
        generation += 1
    }

    private func file(for pack: PackInfo) -> URL {
        dir.appendingPathComponent((pack.url as NSString).lastPathComponent)
    }

    private func isCurrent(_ pack: PackInfo) -> Bool {
        guard let data = try? Data(contentsOf: file(for: pack)) else { return false }
        return pack.sha256.isEmpty || sha256(data) == pack.sha256
    }

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentSyncError.http(http.statusCode)
        }
        return data
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? ContentSyncError { return e.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Using the built-in words." }
        return "Couldn't download lessons. Using the built-in words."
    }
}

enum ContentSyncError: Error {
    case http(Int)
    case checksum(String)

    var message: String {
        switch self {
        case .http(let code): return "The content site answered \(code). Using the built-in words."
        case .checksum(let id): return "Download of \(id) was damaged. Try again."
        }
    }
}
