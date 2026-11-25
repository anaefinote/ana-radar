import Foundation
import Network

/// CHATNOTE over Wi-Fi and the Internet (as Android's ChatNet.java). Port 47474 while ANA is open. A message is one
/// line: the signed message in base64, then a new line; the answer is "OK" or "NO <why>". On the same Wi-Fi, ANAs
/// announce themselves as "_anachat._tcp" and find each other; over the Internet (Tailscale), you type the other
/// phone's address. The signature, not the network, says who sent it.
final class ChatNet {
    static let shared = ChatNet()
    static let port: UInt16 = 47474
    private var listener: NWListener?
    private let q = DispatchQueue(label: "ana.chatnet")

    struct Peer { let name: String; let endpoint: NWEndpoint }

    private var tag: String { String(Chat.shared.myKeyId().prefix(8)) }

    /// FILE PUSH (hybrid): a desktop/peer can push a whole .pngmesh here, framed, no 8 KB chat cap. Set by the app;
    /// returns nil if ANA took the file, else why not. The chat line path is untouched — this is a separate branch.
    var onFile: ((Data) -> String?)?
    static let fileMarker = "ANAFILE1"
    private static let maxFile = 8 * 1024 * 1024    // 8 MB ceiling, so a push can't run the phone out of memory

    // ------------------------------------------------------------------ listening
    func start() {
        if let l = listener, l.state != .cancelled, !isFailed(l.state) { return }
        guard let p = NWEndpoint.Port(rawValue: ChatNet.port), let l = try? NWListener(using: .tcp, on: p) else { return }
        l.service = NWListener.Service(name: String((tag + " " + Chat.shared.myName()).prefix(60)), type: "_anachat._tcp")
        l.newConnectionHandler = { [weak self] c in self?.take(c) }
        l.stateUpdateHandler = { [weak self] s in if case .failed = s { self?.listener?.cancel(); self?.listener = nil } }
        listener = l
        l.start(queue: q)
    }

    func stop() { listener?.cancel(); listener = nil }

    private func isFailed(_ s: NWListener.State) -> Bool { if case .failed = s { return true }; return false }

    private func take(_ c: NWConnection) {
        c.start(queue: q)
        readHead(c, Data()) { line, rest in
            // FILE PUSH branch: a framed .pngmesh, not a chat line. A real chat message is base64 of a signed
            // BillCore file and never equals this marker, so the chat path below is left exactly as it was.
            if let l = line, l.trimmingCharacters(in: .whitespacesAndNewlines) == ChatNet.fileMarker {
                self.takeFile(c, rest); return
            }
            var reply = "NO unreadable"
            if let l = line, l.count < 8000, let f = Data(base64Encoded: l.trimmingCharacters(in: .whitespacesAndNewlines)) {
                var route = "Wi-Fi"
                if case let .hostPort(h, _) = c.endpoint, ChatNet.isTailnet("\(h)") { route = "Internet" }
                let g = DispatchGroup()
                g.enter()
                DispatchQueue.main.async {
                    let why = Chat.shared.receive(f, route: route)
                    reply = why == nil ? "OK" : "NO " + why!
                    g.leave()
                }
                g.wait()
            }
            c.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private func readLine(_ c: NWConnection, _ got: Data, _ done: @escaping (String?) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 9000) { [weak self] d, _, end, err in
            var all = got
            if let d = d { all.append(d) }
            if let nl = all.firstIndex(of: 10) { done(String(data: all[all.startIndex..<nl], encoding: .utf8)); return }
            if end || err != nil || all.count > 9000 { done(all.isEmpty ? nil : String(data: all, encoding: .utf8)); return }
            self?.readLine(c, all, done)
        }
    }

    /// Like readLine, but also returns the bytes already read PAST the newline — the framed file push needs them,
    /// because its length prefix can ride in the same TCP segment as the marker line.
    private func readHead(_ c: NWConnection, _ got: Data, _ done: @escaping (String?, Data) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 9000) { [weak self] d, _, end, err in
            var all = got
            if let d = d { all.append(d) }
            if let nl = all.firstIndex(of: 10) {
                let line = String(data: all[all.startIndex..<nl], encoding: .utf8)
                done(line, Data(all[all.index(after: nl)...]))
                return
            }
            if end || err != nil || all.count > 9000 { done(all.isEmpty ? nil : String(data: all, encoding: .utf8), Data()); return }
            self?.readHead(c, all, done)
        }
    }

    // ------------------------------------------------------------------ receiving a framed file push
    /// After the "ANAFILE1" marker: 8 bytes big-endian length, then that many bytes = a whole .pngmesh.
    private func takeFile(_ c: NWConnection, _ pre: Data) {
        readN(c, 8, pre) { head in
            guard let head = head, head.count == 8 else {
                c.send(content: Data("NO bad header\n".utf8), completion: .contentProcessed { _ in c.cancel() }); return
            }
            var n = 0
            for i in 0..<8 { n = (n << 8) | Int(head[head.startIndex + i]) }       // big-endian int64 (fits Int)
            if n <= 0 || n > ChatNet.maxFile {
                c.send(content: Data("NO bad size\n".utf8), completion: .contentProcessed { _ in c.cancel() }); return
            }
            self.readN(c, n, Data()) { body in
                var reply = "NO truncated"
                if let body = body, body.count == n {
                    let g = DispatchGroup()
                    g.enter()
                    DispatchQueue.main.async {
                        let why: String? = self.onFile != nil ? self.onFile!(body) : "no file handler"
                        reply = (why == nil) ? "OK" : "NO " + why!
                        g.leave()
                    }
                    g.wait()
                }
                c.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in c.cancel() })
            }
        }
    }

    /// Read exactly `need` bytes (starting from whatever `got` already holds), or nil if the stream ends first.
    private func readN(_ c: NWConnection, _ need: Int, _ got: Data, _ done: @escaping (Data?) -> Void) {
        if got.count >= need { done(got.prefix(need)); return }
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] d, _, end, err in
            var all = got
            if let d = d { all.append(d) }
            if all.count >= need { done(all.prefix(need)); return }
            if end || err != nil { done(nil); return }
            self?.readN(c, need, all, done)
        }
    }

    /// Tailscale addresses are 100.64.0.0/10
    static func isTailnet(_ h: String) -> Bool {
        let p = h.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && p[1] >= 64 && p[1] <= 127
    }

    // ------------------------------------------------------------------ finding ANAs on this Wi-Fi (3 seconds)
    func find(_ done: @escaping ([Peer]) -> Void) {
        let b = NWBrowser(for: .bonjour(type: "_anachat._tcp", domain: nil), using: .tcp)
        let me = tag
        b.start(queue: q)
        q.asyncAfter(deadline: .now() + 3) {
            var peers = [Peer]()
            for r in b.browseResults {
                if case let .service(name, _, _, _) = r.endpoint {
                    if name.hasPrefix(me + " ") { continue }                   // this phone
                    let n = name.split(separator: " ", maxSplits: 1)
                    peers.append(Peer(name: n.count > 1 ? String(n[1]) : name, endpoint: r.endpoint))
                }
            }
            b.cancel()
            DispatchQueue.main.async { done(peers) }
        }
    }

    // ------------------------------------------------------------------ MESH presence: a live list of ANAs on this
    // Wi-Fi, kept current by a standing browser. The radar shows these as "reachable" dots (not "near" — no RSSI).
    private var meshBrowser: NWBrowser?
    private var lanCache: [String] = []        // "tag~name" per discovered ANA (never this phone)

    func startMesh() {
        if meshBrowser != nil { return }
        let b = NWBrowser(for: .bonjour(type: "_anachat._tcp", domain: nil), using: .tcp)
        let me = tag
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var out = [String]()
            for r in results {
                if case let .service(name, _, _, _) = r.endpoint {
                    if name.hasPrefix(me + " ") { continue }           // skip this phone's own announcement
                    let parts = name.split(separator: " ", maxSplits: 1)
                    let t = String(parts.first ?? "")
                    let n = parts.count > 1 ? String(parts[1]) : name
                    if !t.isEmpty { out.append(t + "~" + n) }
                }
            }
            self?.lanCache = out
        }
        b.stateUpdateHandler = { [weak self] s in if case .failed = s { self?.meshBrowser?.cancel(); self?.meshBrowser = nil } }
        b.start(queue: q)
        meshBrowser = b
    }
    func stopMesh() { meshBrowser?.cancel(); meshBrowser = nil; lanCache = [] }
    func lanList() -> String { lanCache.joined(separator: ";") }

    // ------------------------------------------------------------------ sending
    /// done(nil) when the other ANA took it, else why not (on the main queue)
    func send(_ f: Data, to e: NWEndpoint, _ done: @escaping (String?) -> Void) {
        let c = NWConnection(to: e, using: .tcp)
        var finished = false
        func finish(_ r: String?) {
            q.async {
                if finished { return }
                finished = true
                c.cancel()
                DispatchQueue.main.async { done(r) }
            }
        }
        c.stateUpdateHandler = { s in
            switch s {
            case .ready:
                c.send(content: Data((f.base64EncodedString() + "\n").utf8), completion: .contentProcessed { err in
                    if err != nil { finish("Couldn't send"); return }
                    self.readLine(c, Data()) { r in
                        guard let r = r?.trimmingCharacters(in: .whitespacesAndNewlines) else { finish("No answer"); return }
                        finish(r == "OK" ? nil : r.hasPrefix("NO ") ? String(r.dropFirst(3)) : r)
                    }
                })
            case .failed(let e): finish("Couldn't reach it (\(e))")
            case .waiting(let e): finish("Couldn't reach it (\(e))")
            default: break
            }
        }
        c.start(queue: q)
        q.asyncAfter(deadline: .now() + 10) { finish("No answer in 10 seconds") }
    }

    func send(_ f: Data, host: String, _ done: @escaping (String?) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: ChatNet.port) else { done("bad port"); return }
        send(f, to: .hostPort(host: NWEndpoint.Host(host), port: p), done)
    }

    /// MESH reachability: does an ANA answer at host:47474? A TCP .ready = something is listening there.
    /// Used to light up a tailnet (Tailscale) peer on the radar as "reachable", never "near".
    func ping(host: String, _ done: @escaping (Bool) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: ChatNet.port) else { done(false); return }
        let c = NWConnection(to: .hostPort(host: NWEndpoint.Host(host), port: p), using: .tcp)
        var fin = false
        func f(_ ok: Bool) { q.async { if fin { return }; fin = true; c.cancel(); DispatchQueue.main.async { done(ok) } } }
        c.stateUpdateHandler = { s in
            switch s {
            case .ready: f(true)
            case .failed: f(false)
            default: break               // .waiting is transient; let the 4s timeout decide
            }
        }
        c.start(queue: q)
        q.asyncAfter(deadline: .now() + 4) { f(false) }
    }
}
