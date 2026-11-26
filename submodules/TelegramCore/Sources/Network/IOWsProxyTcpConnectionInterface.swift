import Foundation
import Network
import Security
import MtProtoKit
import SwiftSignalKit

// Native Swift implementation of Flowseal/tg-ws-proxy transport:
// Direct Telegram WebSocket (wss://kws*.web.telegram.org/apiws + domain fronting)
// with automatic fallback to Cloudflare WebSocket relay domains and direct TCP.

private final class IOWsProxyBalancer {
    static let shared = IOWsProxyBalancer()

    private static let defaultCfDomains: [String] = [
        "pclead.co.uk",
        "offshor.co.uk",
        "cakeisalie.co.uk",
        "noskomnadzor.co.uk",
        "lovetrue.co.uk",
        "sorokdva.co.uk",
        "pyatdesyatdva.co.uk",
        "kartoshka.co.uk",
        "sorokodin.co.uk",
        "pyatdesyatodin.co.uk",
        "notelega.co.uk",
        "ebally.co.uk",
        "nebally.co.uk",
        "havegreatday.co.uk",
        "pomogite.co.uk",
        "fixtelega.co.uk",
        "sadnews.co.uk",
        "onedaychamp.co.uk",
        "stopblocking.co.uk",
        "nothingthere.co.uk"
    ]

    private static let remoteDomainsUrl = URL(string: "https://raw.githubusercontent.com/Flowseal/tg-ws-proxy/main/.github/cfproxy-domains.txt")!

    private let lock = NSLock()
    private var fetchedDomains: [String] = []
    private var dohCache: [String: (ip: String, expiresAt: TimeInterval)] = [:]
    private var dohInFlight: Set<String> = []
    private var lastFetchAttempt: TimeInterval = 0
    private var isFetching = false
    private var bestRouteForKey: [String: String] = [:]
    private var cooldownUntil: [String: TimeInterval] = [:]

    private init() {
    }

    func refreshRemoteDomainsIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        if self.isFetching || (now - self.lastFetchAttempt) < 900.0 {
            self.lock.unlock()
            return
        }
        self.isFetching = true
        self.lastFetchAttempt = now
        self.lock.unlock()

        var request = URLRequest(url: Self.remoteDomainsUrl)
        request.timeoutInterval = 6.0
        request.setValue("tg-ws-proxy", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.isFetching = false
                self.lock.unlock()
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode),
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            let parsed = Self.parseDomainList(text, decodeEncryptedCf: true)
            guard parsed.count >= 3 else {
                return
            }
            self.lock.lock()
            self.fetchedDomains = parsed
            self.lock.unlock()
        }
        task.resume()
    }

    private static func decodeCfDomain(_ s: String) -> String {
        // Port of Flowseal/tg-ws-proxy / amurcanov/tg-ws-proxy-android Caesar shift for *.com -> *.co.uk
        guard s.hasSuffix(".com") else {
            return s
        }
        let prefix = String(s.dropLast(4))
        var letterCount = 0
        for scalar in prefix.unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 65 && scalar.value <= 90) {
                letterCount += 1
            }
        }
        let shift = letterCount % 26
        var decoded = String.UnicodeScalarView()
        for scalar in prefix.unicodeScalars {
            if scalar.value >= 97 && scalar.value <= 122 {
                let v = ((Int(scalar.value) - 97 - shift + 26) % 26) + 97
                decoded.append(Unicode.Scalar(v)!)
            } else if scalar.value >= 65 && scalar.value <= 90 {
                let v = ((Int(scalar.value) - 65 - shift + 26) % 26) + 65
                decoded.append(Unicode.Scalar(v)!)
            } else {
                decoded.append(scalar)
            }
        }
        return String(decoded) + ".co.uk"
    }

    private static func parseDomainList(_ raw: String, decodeEncryptedCf: Bool) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\r\n \t")
        let tokens = raw.components(separatedBy: separators)
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens {
            var domain = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if domain.isEmpty || domain.hasPrefix("#") {
                continue
            }
            if domain.hasPrefix("https://") {
                domain = String(domain.dropFirst(8))
            } else if domain.hasPrefix("http://") {
                domain = String(domain.dropFirst(7))
            }
            if let slashIdx = domain.firstIndex(of: "/") {
                domain = String(domain[..<slashIdx])
            }
            if domain.hasPrefix("*.") {
                domain = String(domain.dropFirst(2))
            }
            if decodeEncryptedCf {
                domain = Self.decodeCfDomain(domain)
            }
            while domain.hasSuffix(".") {
                domain.removeLast()
            }
            guard !domain.isEmpty, domain.contains(".") else {
                continue
            }
            if seen.insert(domain).inserted {
                result.append(domain)
            }
        }
        return result
    }

    func cachedDoHIp(for host: String) -> String? {
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        let entry = self.dohCache[host]
        let shouldResolve = (entry == nil || entry!.expiresAt <= now) && !self.dohInFlight.contains(host)
        if shouldResolve {
            self.dohInFlight.insert(host)
        }
        self.lock.unlock()

        if shouldResolve {
            self.resolveViaDoH(host: host)
        }
        if let entry, entry.expiresAt > now {
            return entry.ip
        }
        return nil
    }

    private func resolveViaDoH(host: String) {
        guard let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://1.1.1.1/dns-query?name=\(encoded)&type=A") else {
            self.lock.lock()
            self.dohInFlight.remove(host)
            self.lock.unlock()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.5
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.dohInFlight.remove(host)
                self.lock.unlock()
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = json["Answer"] as? [[String: Any]] else {
                return
            }
            for ans in answers {
                if let type = ans["type"] as? Int, type == 1,
                   let ip = ans["data"] as? String, !ip.isEmpty {
                    let ttl = TimeInterval(ans["TTL"] as? Int ?? 300)
                    let clampedTtl = max(60.0, min(ttl, 600.0))
                    self.lock.lock()
                    self.dohCache[host] = (ip, CFAbsoluteTimeGetCurrent() + clampedTtl)
                    self.lock.unlock()
                    break
                }
            }
        }
        task.resume()
    }

    func customDomains() -> [String] {
        return Self.parseDomainList(IOCoreConfig.current.wsProxyCustomDomains, decodeEncryptedCf: false)
    }

    func cfDomains(limit: Int = 6) -> [String] {
        self.lock.lock()
        let fetched = self.fetchedDomains
        self.lock.unlock()

        let custom = self.customDomains()
        var merged: [String] = []
        var seen = Set<String>()
        for d in custom {
            if seen.insert(d).inserted {
                merged.append(d)
            }
        }
        var pool = fetched.isEmpty ? Self.defaultCfDomains : fetched
        pool.shuffle()
        for d in pool {
            if seen.insert(d).inserted {
                merged.append(d)
            }
        }
        if merged.count > limit {
            return Array(merged.prefix(limit))
        }
        return merged
    }

    func preferredRouteId(dc: Int, isMedia: Bool) -> String? {
        let key = "\(dc)_\(isMedia ? 1 : 0)"
        self.lock.lock()
        let val = self.bestRouteForKey[key]
        self.lock.unlock()
        return val
    }

    func markRouteSuccess(dc: Int, isMedia: Bool, routeId: String) {
        let key = "\(dc)_\(isMedia ? 1 : 0)"
        self.lock.lock()
        self.bestRouteForKey[key] = routeId
        self.cooldownUntil.removeValue(forKey: routeId)
        self.lock.unlock()
    }

    func markRouteFailed(routeId: String) {
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        if self.cooldownUntil.count > 128 {
            self.cooldownUntil = self.cooldownUntil.filter { $0.value > now }
        }
        self.cooldownUntil[routeId] = now + 30.0
        self.lock.unlock()
    }

    func isInCooldown(routeId: String) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        let until = self.cooldownUntil[routeId] ?? 0.0
        self.lock.unlock()
        return now < until
    }
}

@available(iOS 12.0, macOS 14.0, *)
final class IOWsProxyTcpConnectionInterface: NSObject, MTTcpConnectionInterface {
    private struct ReadRequest {
        let length: Int
        let tag: Int
    }

    private enum RouteKind {
        case webSocket(connectHost: String, port: UInt16, httpHost: String, sni: String?, path: String, useTLS: Bool, trustAnyCert: Bool, timeout: Double)
        case directTcp(host: String, port: UInt16, timeout: Double)
    }

    private struct CandidateRoute {
        let id: String
        let kind: RouteKind
    }

    private final class Impl {
        private let queue: Queue
        private weak var delegate: MTTcpConnectionInterfaceDelegate?
        private let delegateQueue: DispatchQueue

        private var fallbackHost: String = ""
        private var fallbackPort: UInt16 = 443
        private var connectTimeout: Double = 12.0

        private var usageCalculationInfo: MTNetworkUsageCalculationInfo?
        private var networkUsageManager: MTNetworkUsageManager?
        private var getLogPrefix: (() -> String)?
        private var instanceId: String
        private var logId: String

        private var reportedConnect = false
        private var reportedDisconnection = false
        private var parsedHandshake = false
        private var currentInterfaceIsWifi = true

        private var header64 = Data()
        private var pendingWrites: [Data] = []
        private var readRequests: [ReadRequest] = []
        private var incomingBuffer = Data()

        private var candidates: [CandidateRoute] = []
        private var candidateIndex = 0
        private var activeConnection: NWConnection?
        private var activeRoute: CandidateRoute?
        private var attemptTimer: SwiftSignalKit.Timer?

        private var isWebSocketMode = true
        private var upstreamReady = false
        private var sentInitFrame = false
        private var wsHttpHandshakeDone = false
        private var wsHttpBuffer = Data()
        private var wsFrameBuffer = Data()
        private var wsFragmentBuffer = Data()
        private var wsClosed = false

        init(queue: Queue, delegate: MTTcpConnectionInterfaceDelegate, delegateQueue: DispatchQueue) {
            self.queue = queue
            self.delegate = delegate
            self.delegateQueue = delegateQueue
            self.instanceId = ""
            self.logId = ""
            self.instanceId = String(UInt(bitPattern: ObjectIdentifier(self)), radix: 16)
            self.logId = "[IOWsProxy#\(self.instanceId)]"
        }

        deinit {
            self.attemptTimer?.invalidate()
            self.attemptTimer = nil
            if let connection = self.activeConnection {
                self.activeConnection = nil
                connection.cancel()
            }
        }

        func setUsageCalculationInfo(_ usageCalculationInfo: MTNetworkUsageCalculationInfo?) {
            if self.usageCalculationInfo !== usageCalculationInfo {
                self.usageCalculationInfo = usageCalculationInfo
                if let usageCalculationInfo {
                    self.networkUsageManager = MTNetworkUsageManager(info: usageCalculationInfo)
                } else {
                    self.networkUsageManager = nil
                }
            }
        }

        func setGetLogPrefix(_ getLogPrefix: (() -> String)?) {
            self.getLogPrefix = getLogPrefix
        }

        func connect(host: String, port: UInt16, timeout: Double) {
            self.fallbackHost = host
            self.fallbackPort = port
            self.connectTimeout = timeout
            if let logPrefix = self.getLogPrefix?(), !logPrefix.isEmpty {
                self.logId = "[IOWsProxy#\(self.instanceId) \(logPrefix) \(host):\(port)]"
            } else {
                self.logId = "[IOWsProxy#\(self.instanceId) \(host):\(port)]"
            }

            IOWsProxyBalancer.shared.refreshRemoteDomainsIfNeeded()

            // Handshake readiness is reported immediately so MTTcpConnection emits the 64-byte obfs2 header,
            // allowing exact DC ID, media flag, and test DC routing before dialing WebSocket/CF upstream.
            if !self.reportedConnect {
                self.reportedConnect = true
                let delegate = self.delegate
                self.delegateQueue.async { [weak delegate] in
                    delegate?.connectionInterfaceDidConnect()
                }
            }
        }

        func write(data: Data) {
            guard !self.reportedDisconnection else { return }

            if !self.parsedHandshake {
                self.header64.append(data)
                guard self.header64.count >= 64 else {
                    return
                }
                self.parsedHandshake = true
                let initBytes = Data(self.header64.prefix(64))
                let tailBytes = self.header64.count > 64 ? Data(self.header64.dropFirst(64)) : Data()
                self.header64 = initBytes
                if !tailBytes.isEmpty {
                    self.pendingWrites.append(tailBytes)
                }
                self.startCascade(initBytes: initBytes)
                return
            }

            if self.upstreamReady && self.sentInitFrame {
                self.sendPayload(data)
            } else {
                self.pendingWrites.append(data)
            }
        }

        func read(length: Int, timeout: Double, tag: Int) {
            guard !self.reportedDisconnection else { return }
            self.readRequests.append(ReadRequest(length: length, tag: tag))
            self.drainReadRequests()
        }

        func disconnect() {
            self.failAll(error: nil, reason: "disconnect requested")
        }

        func resetDelegate() {
            self.delegate = nil
        }

        private func parseObfs2Header(_ initBytes: Data) -> (dc: Int, isMedia: Bool, isTestDc: Bool) {
            let aesKey = initBytes.subdata(in: 8 ..< 40)
            let aesIv = initBytes.subdata(in: 40 ..< 56)
            if let decrypted = MTAesCtrDecrypt(initBytes, aesKey, aesIv), decrypted.count >= 64 {
                let rawDc: Int16 = decrypted.withUnsafeBytes { buf in
                    let lo = UInt16(buf[60])
                    let hi = UInt16(buf[61])
                    return Int16(bitPattern: lo | (hi << 8))
                }
                let isMedia = rawDc < 0
                let absDc = abs(Int(rawDc))
                let isTestDc = absDc >= 10000
                let normalizedDc = isTestDc ? (absDc - 10000) : absDc
                if normalizedDc >= 1 && normalizedDc <= 300 {
                    return (normalizedDc, isMedia, isTestDc)
                }
            }
            return (Self.inferDcFromHost(self.fallbackHost), false, false)
        }

        private static func inferDcFromHost(_ host: String) -> Int {
            if host.hasPrefix("149.154.175.5") || host.contains(":f001:") { return 1 }
            if host.hasPrefix("149.154.167.5") || host.hasPrefix("149.154.167.22") || host.hasPrefix("95.161.76.") || host.contains(":f002:") { return 2 }
            if host.hasPrefix("149.154.175.1") || host.contains(":f003:") { return 3 }
            if host.hasPrefix("149.154.167.9") || host.contains(":f004:") { return 4 }
            if host.hasPrefix("149.154.171.") || host.contains(":f005:") { return 5 }
            return 2
        }

        private func startCascade(initBytes: Data) {
            let parsed = self.parseObfs2Header(initBytes)
            let wsDc = parsed.dc == 203 ? 2 : parsed.dc
            let path = parsed.isTestDc ? "/apiws_test" : "/apiws"
            let mode = IOCoreConfig.current.wsProxyMode

            var list: [CandidateRoute] = []
            let directWsHosts = parsed.isMedia
                ? ["kws\(wsDc)-1.web.telegram.org", "kws\(wsDc).web.telegram.org"]
                : ["kws\(wsDc).web.telegram.org"]

            if mode != 2 {
                // Mode 1 (Auto): fast WS IP/DNS -> 2 CF relays -> guaranteed Direct TCP fallback
                if !parsed.isTestDc && (wsDc == 2 || wsDc == 4) {
                    let directIp = "149.154.167.220"
                    if let host = directWsHosts.first {
                        list.append(CandidateRoute(id: "ws-ip:\(directIp):\(host)", kind: .webSocket(connectHost: directIp, port: 443, httpHost: host, sni: host, path: path, useTLS: true, trustAnyCert: true, timeout: 1.5)))
                    }
                }
                if let host = directWsHosts.first {
                    if let dohIp = IOWsProxyBalancer.shared.cachedDoHIp(for: host) {
                        list.append(CandidateRoute(id: "ws-doh:\(dohIp):\(host)", kind: .webSocket(connectHost: dohIp, port: 443, httpHost: host, sni: host, path: path, useTLS: true, trustAnyCert: true, timeout: 1.5)))
                    } else {
                        list.append(CandidateRoute(id: "ws-dns:\(host)", kind: .webSocket(connectHost: host, port: 443, httpHost: host, sni: host, path: path, useTLS: true, trustAnyCert: true, timeout: 1.5)))
                    }
                }
            }

            if !parsed.isTestDc {
                let cfLimit = (mode == 2) ? 4 : 2
                let cfDomains = IOWsProxyBalancer.shared.cfDomains(limit: cfLimit)
                for domain in cfDomains {
                    let cfHost = "kws\(wsDc).\(domain)"
                    if let dohIp = IOWsProxyBalancer.shared.cachedDoHIp(for: cfHost) {
                        list.append(CandidateRoute(id: "cf-doh:\(dohIp):\(cfHost)", kind: .webSocket(connectHost: dohIp, port: 443, httpHost: cfHost, sni: cfHost, path: path, useTLS: true, trustAnyCert: true, timeout: 1.8)))
                    } else {
                        list.append(CandidateRoute(id: "cf-tls:\(cfHost)", kind: .webSocket(connectHost: cfHost, port: 443, httpHost: cfHost, sni: cfHost, path: path, useTLS: true, trustAnyCert: true, timeout: 1.8)))
                    }
                }
            }

            if !self.fallbackHost.isEmpty {
                list.append(CandidateRoute(id: "tcp:\(self.fallbackHost):\(self.fallbackPort)", kind: .directTcp(host: self.fallbackHost, port: self.fallbackPort, timeout: 3.5)))
            }

            // Reorder so cached working route for this (dc, isMedia) goes first and cooled-down routes are skipped/last
            let preferredId = IOWsProxyBalancer.shared.preferredRouteId(dc: parsed.dc, isMedia: parsed.isMedia)
            var healthy: [CandidateRoute] = []
            for route in list {
                if route.id == preferredId {
                    healthy.insert(route, at: 0)
                } else if !IOWsProxyBalancer.shared.isInCooldown(routeId: route.id) || route.id.hasPrefix("tcp:") {
                    healthy.append(route)
                }
            }
            if healthy.isEmpty {
                healthy = list
            }
            self.candidates = healthy
            self.candidateIndex = 0
            self.tryNextCandidate()
        }

        private func tryNextCandidate() {
            guard !self.reportedDisconnection else { return }

            self.attemptTimer?.invalidate()
            self.attemptTimer = nil
            if let old = self.activeConnection {
                self.activeConnection = nil
                old.stateUpdateHandler = nil
                old.pathUpdateHandler = nil
                old.cancel()
            }

            guard self.candidateIndex < self.candidates.count else {
                self.failAll(error: nil, reason: "all WS/CF/TCP routes failed")
                return
            }

            let candidate = self.candidates[self.candidateIndex]
            self.candidateIndex += 1
            self.activeRoute = candidate
            self.upstreamReady = false
            self.sentInitFrame = false
            self.wsHttpHandshakeDone = false
            self.wsHttpBuffer.removeAll(keepingCapacity: true)
            self.wsFrameBuffer.removeAll(keepingCapacity: true)
            self.wsFragmentBuffer.removeAll(keepingCapacity: true)
            self.wsClosed = false

            let targetHost: String
            let targetPort: UInt16
            let timeout: Double
            let parameters: NWParameters

            switch candidate.kind {
            case let .webSocket(connectHost, port, _, sni, _, useTLS, trustAnyCert, attemptTimeout):
                self.isWebSocketMode = true
                targetHost = connectHost
                targetPort = port
                timeout = attemptTimeout

                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.noDelay = true
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveIdle = 10
                tcpOptions.keepaliveCount = 2
                tcpOptions.keepaliveInterval = 5

                if useTLS {
                    let tlsOptions = NWProtocolTLS.Options()
                    let sec = tlsOptions.securityProtocolOptions
                    if let sni {
                        sec_protocol_options_set_tls_server_name(sec, sni)
                    }
                    sec_protocol_options_add_tls_application_protocol(sec, "http/1.1")
                    if trustAnyCert {
                        let q = self.queue.queue
                        sec_protocol_options_set_verify_block(sec, { _, _, complete in
                            complete(true)
                        }, q)
                    }
                    parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
                } else {
                    parameters = NWParameters(tls: nil, tcp: tcpOptions)
                }
                parameters.preferNoProxies = true

            case let .directTcp(host, port, attemptTimeout):
                self.isWebSocketMode = false
                targetHost = host
                targetPort = port
                timeout = attemptTimeout

                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.noDelay = true
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveIdle = 5
                tcpOptions.keepaliveCount = 2
                tcpOptions.keepaliveInterval = 5
                tcpOptions.enableFastOpen = true
                parameters = NWParameters(tls: nil, tcp: tcpOptions)
                parameters.preferNoProxies = true
            }

            guard let nwPort = NWEndpoint.Port(rawValue: targetPort) else {
                self.tryNextCandidate()
                return
            }

            let connection = NWConnection(host: NWEndpoint.Host(targetHost), port: nwPort, using: parameters)
            self.activeConnection = connection

            let queue = self.queue
            connection.pathUpdateHandler = { [weak self] path in
                queue.async {
                    guard let self, self.activeConnection === connection else { return }
                    self.currentInterfaceIsWifi = !path.usesInterfaceType(.cellular)
                }
            }
            connection.stateUpdateHandler = { [weak self] state in
                queue.async {
                    self?.handleConnectionState(connection: connection, candidate: candidate, state: state)
                }
            }

            let timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
                guard let self, self.activeConnection === connection, !self.upstreamReady else { return }
                Logger.shared.log("IOWsProxy", "\(self.logId) candidate \(candidate.id) timed out (\(timeout)s)")
                IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                self.tryNextCandidate()
            }, queue: self.queue)
            self.attemptTimer = timer
            timer.start()

            connection.start(queue: self.queue.queue)
        }

        private func handleConnectionState(connection: NWConnection, candidate: CandidateRoute, state: NWConnection.State) {
            guard self.activeConnection === connection, !self.reportedDisconnection else { return }

            switch state {
            case .ready:
                if case let .webSocket(_, _, httpHost, _, path, _, _, _) = candidate.kind {
                    self.sendWsUpgradeRequest(connection: connection, candidate: candidate, httpHost: httpHost, path: path)
                    self.receiveLoop(connection: connection, candidate: candidate)
                } else {
                    self.markCandidateEstablished(candidate: candidate)
                    self.flushQueuedWrites()
                    self.receiveLoop(connection: connection, candidate: candidate)
                }
            case let .failed(error):
                if self.upstreamReady {
                    self.failAll(error: error, reason: "upstream failed")
                } else {
                    Logger.shared.log("IOWsProxy", "\(self.logId) candidate \(candidate.id) failed: \(error)")
                    IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                    self.tryNextCandidate()
                }
            default:
                break
            }
        }

        private func markCandidateEstablished(candidate: CandidateRoute) {
            self.attemptTimer?.invalidate()
            self.attemptTimer = nil
            self.upstreamReady = true
            let parsed = self.parseObfs2Header(self.header64)
            IOWsProxyBalancer.shared.markRouteSuccess(dc: parsed.dc, isMedia: parsed.isMedia, routeId: candidate.id)
            Logger.shared.log("IOWsProxy", "\(self.logId) connected via \(candidate.id)")
        }

        private func sendWsUpgradeRequest(connection: NWConnection, candidate: CandidateRoute, httpHost: String, path: String) {
            var keyBytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
            let secKey = Data(keyBytes).base64EncodedString()

            let req = "GET \(path) HTTP/1.1\r\n"
                + "Host: \(httpHost)\r\n"
                + "Upgrade: websocket\r\n"
                + "Connection: Upgrade\r\n"
                + "Sec-WebSocket-Key: \(secKey)\r\n"
                + "Sec-WebSocket-Version: 13\r\n"
                + "Sec-WebSocket-Protocol: binary\r\n"
                + "\r\n"
            let reqData = Data(req.utf8)
            connection.send(content: reqData, completion: .contentProcessed({ [weak self] error in
                guard let self, self.activeConnection === connection, let error else { return }
                self.queue.async {
                    guard self.activeConnection === connection else { return }
                    if self.upstreamReady {
                        self.failAll(error: error, reason: "ws upgrade send failed")
                    } else {
                        IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                        self.tryNextCandidate()
                    }
                }
            }))
        }

        private func flushQueuedWrites() {
            guard self.upstreamReady, let connection = self.activeConnection else { return }
            if !self.sentInitFrame {
                self.sentInitFrame = true
                self.rawSendUpstream(connection: connection, payload: self.header64, isWebSocket: self.isWebSocketMode)
            }
            if !self.pendingWrites.isEmpty {
                let queued = self.pendingWrites
                self.pendingWrites.removeAll(keepingCapacity: true)
                for chunk in queued where !chunk.isEmpty {
                    self.rawSendUpstream(connection: connection, payload: chunk, isWebSocket: self.isWebSocketMode)
                }
            }
        }

        private func sendPayload(_ data: Data) {
            guard !data.isEmpty, let connection = self.activeConnection, self.upstreamReady else { return }
            self.rawSendUpstream(connection: connection, payload: data, isWebSocket: self.isWebSocketMode)
        }

        private func rawSendUpstream(connection: NWConnection, payload: Data, isWebSocket: Bool) {
            let wireData = isWebSocket ? Self.buildWsFrame(opcode: 0x2, payload: payload) : payload
            self.networkUsageManager?.addOutgoingBytes(UInt(payload.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
            connection.send(content: wireData, completion: .contentProcessed({ [weak self] error in
                guard let self, let error else { return }
                self.queue.async {
                    guard self.activeConnection === connection else { return }
                    self.failAll(error: error, reason: "send failed")
                }
            }))
        }

        private func receiveLoop(connection: NWConnection, candidate: CandidateRoute) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, context, isComplete, error in
                guard let self else { return }
                self.queue.async {
                    guard self.activeConnection === connection, !self.reportedDisconnection else { return }
                    let isReadClosed = isComplete && (context?.isFinal ?? true)

                    if let data, !data.isEmpty {
                        if self.isWebSocketMode {
                            self.handleIncomingWsBytes(data, connection: connection, candidate: candidate)
                        } else {
                            self.networkUsageManager?.addIncomingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                            self.incomingBuffer.append(data)
                            self.drainReadRequests()
                        }
                    }

                    if let error {
                        if self.upstreamReady {
                            self.failAll(error: error, reason: "receive failed")
                        } else {
                            IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                            self.tryNextCandidate()
                        }
                        return
                    }

                    if isReadClosed || self.wsClosed {
                        if self.upstreamReady {
                            self.failAll(error: nil, reason: "remote closed connection")
                        } else {
                            IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                            self.tryNextCandidate()
                        }
                        return
                    }

                    self.receiveLoop(connection: connection, candidate: candidate)
                }
            }
        }

        private func handleIncomingWsBytes(_ data: Data, connection: NWConnection, candidate: CandidateRoute) {
            if !self.wsHttpHandshakeDone {
                self.wsHttpBuffer.append(data)
                let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
                if let range = self.wsHttpBuffer.range(of: separator) {
                    let headerData = self.wsHttpBuffer[..<range.lowerBound]
                    let remainder = self.wsHttpBuffer[range.upperBound...]
                    self.wsHttpBuffer.removeAll(keepingCapacity: false)

                    let headerString = String(data: headerData, encoding: .utf8) ?? ""
                    let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
                    let parts = firstLine.split(separator: " ")
                    let statusCode = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
                    guard statusCode == 101 else {
                        Logger.shared.log("IOWsProxy", "\(self.logId) candidate \(candidate.id) HTTP \(statusCode) != 101")
                        IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                        self.tryNextCandidate()
                        return
                    }

                    self.wsHttpHandshakeDone = true
                    self.markCandidateEstablished(candidate: candidate)
                    self.flushQueuedWrites()

                    if !remainder.isEmpty {
                        self.wsFrameBuffer.append(remainder)
                        self.processWsFrames(connection: connection)
                    }
                } else if self.wsHttpBuffer.count > 16384 {
                    IOWsProxyBalancer.shared.markRouteFailed(routeId: candidate.id)
                    self.tryNextCandidate()
                }
                return
            }

            self.wsFrameBuffer.append(data)
            self.processWsFrames(connection: connection)
        }

        private func processWsFrames(connection: NWConnection) {
            while self.wsFrameBuffer.count >= 2 {
                let b0 = self.wsFrameBuffer[self.wsFrameBuffer.startIndex]
                let b1 = self.wsFrameBuffer[self.wsFrameBuffer.startIndex + 1]
                let fin = (b0 & 0x80) != 0
                let opcode = b0 & 0x0F
                let masked = (b1 & 0x80) != 0
                var payloadLen = UInt64(b1 & 0x7F)
                var headerLen = 2

                if payloadLen == 126 {
                    guard self.wsFrameBuffer.count >= 4 else { return }
                    let s = self.wsFrameBuffer.startIndex
                    payloadLen = (UInt64(self.wsFrameBuffer[s + 2]) << 8) | UInt64(self.wsFrameBuffer[s + 3])
                    headerLen = 4
                } else if payloadLen == 127 {
                    guard self.wsFrameBuffer.count >= 10 else { return }
                    let s = self.wsFrameBuffer.startIndex
                    var v: UInt64 = 0
                    for i in 0 ..< 8 {
                        v = (v << 8) | UInt64(self.wsFrameBuffer[s + 2 + i])
                    }
                    payloadLen = v
                    headerLen = 10
                }

                if payloadLen > 16 * 1024 * 1024 {
                    self.wsClosed = true
                    return
                }

                let maskLen = masked ? 4 : 0
                let totalLen = headerLen + maskLen + Int(payloadLen)
                guard self.wsFrameBuffer.count >= totalLen else {
                    return
                }

                let s = self.wsFrameBuffer.startIndex
                var payload = Data(self.wsFrameBuffer[(s + headerLen + maskLen) ..< (s + totalLen)])
                if masked {
                    let mask = Array(self.wsFrameBuffer[(s + headerLen) ..< (s + headerLen + 4)])
                    let payloadCount = payload.count
                    payload.withUnsafeMutableBytes { raw in
                        guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                        for i in 0 ..< payloadCount {
                            ptr[i] ^= mask[i & 3]
                        }
                    }
                }
                self.wsFrameBuffer.removeFirst(totalLen)

                switch opcode {
                case 0x8: // OP_CLOSE
                    self.wsClosed = true
                    let closeFrame = Self.buildWsFrame(opcode: 0x8, payload: payload.prefix(2))
                    connection.send(content: closeFrame, completion: .idempotent)
                    return
                case 0x9: // OP_PING
                    let pongFrame = Self.buildWsFrame(opcode: 0xA, payload: payload)
                    connection.send(content: pongFrame, completion: .idempotent)
                case 0xA: // OP_PONG
                    continue
                case 0x0, 0x1, 0x2: // OP_CONT, TEXT, BINARY
                    if fin && self.wsFragmentBuffer.isEmpty {
                        self.networkUsageManager?.addIncomingBytes(UInt(payload.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                        self.incomingBuffer.append(payload)
                        self.drainReadRequests()
                    } else {
                        self.wsFragmentBuffer.append(payload)
                        if fin {
                            let assembled = self.wsFragmentBuffer
                            self.wsFragmentBuffer.removeAll(keepingCapacity: true)
                            self.networkUsageManager?.addIncomingBytes(UInt(assembled.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                            self.incomingBuffer.append(assembled)
                            self.drainReadRequests()
                        }
                    }
                default:
                    continue
                }
            }
        }

        private func drainReadRequests() {
            while !self.readRequests.isEmpty, !self.incomingBuffer.isEmpty {
                let first = self.readRequests[0]
                if self.incomingBuffer.count >= first.length {
                    self.readRequests.removeFirst()
                    let chunk = Data(self.incomingBuffer.prefix(first.length))
                    self.incomingBuffer.removeFirst(first.length)
                    let delegate = self.delegate
                    let isWifi = self.currentInterfaceIsWifi
                    self.delegateQueue.async { [weak delegate] in
                        delegate?.connectionInterfaceDidRead(chunk, withTag: first.tag, networkType: isWifi ? 0 : 1)
                    }
                } else {
                    let partialLen = self.incomingBuffer.count
                    let delegate = self.delegate
                    let tag = first.tag
                    self.delegateQueue.async { [weak delegate] in
                        delegate?.connectionInterfaceDidReadPartialData(ofLength: UInt(partialLen), tag: tag)
                    }
                    break
                }
            }
        }

        private func failAll(error: Error?, reason: String) {
            self.attemptTimer?.invalidate()
            self.attemptTimer = nil
            if let connection = self.activeConnection {
                self.activeConnection = nil
                connection.stateUpdateHandler = nil
                connection.pathUpdateHandler = nil
                connection.cancel()
            }
            if !self.reportedDisconnection {
                self.reportedDisconnection = true
                Logger.shared.log("IOWsProxy", "\(self.logId) disconnected: \(reason)")
                let delegate = self.delegate
                self.delegateQueue.async { [weak delegate] in
                    delegate?.connectionInterfaceDidDisconnectWithError(error)
                }
            }
        }

        private static func buildWsFrame(opcode: UInt8, payload: Data) -> Data {
            var maskKey = [UInt8](repeating: 0, count: 4)
            _ = SecRandomCopyBytes(kSecRandomDefault, 4, &maskKey)

            let length = payload.count
            var frame = Data()
            frame.reserveCapacity(14 + length)
            frame.append(0x80 | opcode)
            if length < 126 {
                frame.append(0x80 | UInt8(length))
            } else if length < 65536 {
                frame.append(0x80 | 126)
                frame.append(UInt8((length >> 8) & 0xFF))
                frame.append(UInt8(length & 0xFF))
            } else {
                frame.append(0x80 | 127)
                let len64 = UInt64(length)
                for shift in stride(from: 56, through: 0, by: -8) {
                    frame.append(UInt8((len64 >> shift) & 0xFF))
                }
            }
            frame.append(contentsOf: maskKey)
            if !payload.isEmpty {
                var masked = payload
                masked.withUnsafeMutableBytes { raw in
                    guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    for i in 0 ..< length {
                        ptr[i] ^= maskKey[i & 3]
                    }
                }
                frame.append(masked)
            }
            return frame
        }
    }

    private static let sharedQueue = Queue(name: "org.iogram.IOWsProxyTcpConnectionInterface")

    private let impl: QueueLocalObject<Impl>

    init(delegate: MTTcpConnectionInterfaceDelegate, delegateQueue: DispatchQueue) {
        let queue = Self.sharedQueue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(queue: queue, delegate: delegate, delegateQueue: delegateQueue)
        })
    }

    func setGetLogPrefix(_ getLogPrefix: (() -> String)?) {
        self.impl.with { $0.setGetLogPrefix(getLogPrefix) }
    }

    func setUsageCalculationInfo(_ usageCalculationInfo: MTNetworkUsageCalculationInfo?) {
        self.impl.with { $0.setUsageCalculationInfo(usageCalculationInfo) }
    }

    func connect(toHost inHost: String, onPort port: UInt16, viaInterface inInterface: String?, withTimeout timeout: TimeInterval, error errPtr: NSErrorPointer) -> Bool {
        self.impl.with { $0.connect(host: inHost, port: port, timeout: timeout) }
        return true
    }

    func write(_ data: Data) {
        self.impl.with { $0.write(data: data) }
    }

    func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        self.impl.with { $0.read(length: Int(length), timeout: timeout, tag: tag) }
    }

    func disconnect() {
        self.impl.with { $0.disconnect() }
    }

    func resetDelegate() {
        self.impl.with { $0.resetDelegate() }
    }
}
