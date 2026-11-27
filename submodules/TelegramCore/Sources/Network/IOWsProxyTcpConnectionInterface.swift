import Foundation
import Network
import Security
import MtProtoKit
import SwiftSignalKit

// Native Swift implementation of Flowseal/tg-ws-proxy transport:
// Direct Telegram WebSocket (wss://kws*.web.telegram.org/apiws + optional SNI fronting)
// on DC redirects / default DC IPs / DoH / DNS, with Cloudflare TLS (443) + plain WS (80)
// relays, Happy Eyeballs staggered racing, two-strike quarantine, and direct TCP fallback.

public struct IOWsProxyDiagnosticRouteResult: Equatable {
    public enum Status: Equatable {
        case ok
        case timeout(detail: String?)
        case httpError(code: Int)
        case tlsError(code: Int32, detail: String)
        case networkError(detail: String)
    }

    public let routeId: String
    public let label: String
    public let status: Status
    public let elapsedMs: Int

    public init(routeId: String, label: String, status: Status, elapsedMs: Int) {
        self.routeId = routeId
        self.label = label
        self.status = status
        self.elapsedMs = elapsedMs
    }
}

public enum IOWsProxyDiagnostics {
    /// Sequentially probes all DC2 candidates for diagnostics UI without triggering happy-eyeballs cancellation
    /// or mutating runtime quarantine timers, while logging every result to `Logger.shared.log("IOWsProxy", ...)`.
    public static func runDc2Diagnostics(
        progress: @escaping ([IOWsProxyDiagnosticRouteResult], Bool) -> Void
    ) -> Disposable {
        if #available(iOS 12.0, macOS 14.0, *) {
            return IOWsProxyTcpConnectionInterface.runDc2Diagnostics(progress: progress)
        } else {
            Queue.mainQueue().async {
                progress([], true)
            }
            return EmptyDisposable
        }
    }
}

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
    private var bestCfDomainForDc: [Int: String] = [:]
    private var consecutiveFailures: [String: Int] = [:]
    private var cooldownUntil: [String: TimeInterval] = [:]
    private var tryFrontingFirst = false
    private var cfTlsWins = 0
    private var cfPlainWins = 0
    private var settingsObserver: NSObjectProtocol?

    private init() {
        self.settingsObserver = NotificationCenter.default.addObserver(
            forName: IOCoreConfig.wsProxySettingsChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.resetRoutingState()
        }
    }

    deinit {
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func resetRoutingState() {
        self.lock.lock()
        self.bestRouteForKey.removeAll()
        self.bestCfDomainForDc.removeAll()
        self.consecutiveFailures.removeAll()
        self.cooldownUntil.removeAll()
        self.tryFrontingFirst = false
        self.cfTlsWins = 0
        self.cfPlainWins = 0
        self.lock.unlock()
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
        // Port of Flowseal/tg-ws-proxy Caesar shift for *.com -> *.co.uk
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

    func cfDomains(forWsDc wsDc: Int, limit: Int) -> (custom: Set<String>, ordered: [String]) {
        self.lock.lock()
        let fetched = self.fetchedDomains
        let preferredCfDomain = self.bestCfDomainForDc[wsDc]
        self.lock.unlock()

        let customList = self.customDomains()
        let customSet = Set(customList)
        var merged: [String] = []
        var seen = Set<String>()
        for d in customList {
            if seen.insert(d).inserted {
                merged.append(d)
            }
        }

        let pool = fetched.isEmpty ? Self.defaultCfDomains : fetched
        if let preferredCfDomain, pool.contains(preferredCfDomain), seen.insert(preferredCfDomain).inserted {
            merged.append(preferredCfDomain)
        }

        var remaining = pool.filter { !seen.contains($0) }
        remaining.shuffle()
        for d in remaining {
            if seen.insert(d).inserted {
                merged.append(d)
            }
        }

        let effectiveLimit = max(limit, customList.count)
        if merged.count > effectiveLimit {
            return (customSet, Array(merged.prefix(effectiveLimit)))
        }
        return (customSet, merged)
    }

    var shouldTryFrontingFirst: Bool {
        self.lock.lock()
        let value = self.tryFrontingFirst
        self.lock.unlock()
        return value
    }

    var cfPrefersTls: Bool {
        self.lock.lock()
        let prefers = self.cfTlsWins >= self.cfPlainWins
        self.lock.unlock()
        return prefers
    }

    func preferredRouteId(dc: Int, isMedia: Bool) -> String? {
        let key = "\(dc)_\(isMedia ? 1 : 0)"
        self.lock.lock()
        let val = self.bestRouteForKey[key]
        self.lock.unlock()
        return val
    }

    func markRouteSuccess(
        dc: Int,
        wsDc: Int,
        isMedia: Bool,
        routeId: String,
        usedFronting: Bool?,
        usedCfTls: Bool?,
        cfBaseDomain: String?
    ) {
        let key = "\(dc)_\(isMedia ? 1 : 0)"
        self.lock.lock()
        self.bestRouteForKey[key] = routeId
        self.consecutiveFailures.removeValue(forKey: routeId)
        self.cooldownUntil.removeValue(forKey: routeId)
        if let usedFronting {
            self.tryFrontingFirst = usedFronting
        }
        if let usedCfTls {
            if usedCfTls {
                self.cfTlsWins += 1
            } else {
                self.cfPlainWins += 1
            }
        }
        if let cfBaseDomain {
            self.bestCfDomainForDc[wsDc] = cfBaseDomain
        }
        self.lock.unlock()
    }

    func markRouteFailed(routeId: String, dohHost: String? = nil) {
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        if self.consecutiveFailures.count > 256 {
            self.consecutiveFailures = self.consecutiveFailures.filter { key, _ in
                (self.cooldownUntil[key] ?? 0.0) > now
            }
        }
        let nextFailures = (self.consecutiveFailures[routeId] ?? 0) + 1
        self.consecutiveFailures[routeId] = nextFailures

        // Quarantine only after 2 consecutive failures
        if nextFailures >= 2 {
            if self.cooldownUntil.count > 128 {
                self.cooldownUntil = self.cooldownUntil.filter { $0.value > now }
            }
            self.cooldownUntil[routeId] = now + 30.0
            self.bestRouteForKey = self.bestRouteForKey.filter { $0.value != routeId }
            if let dohHost {
                self.dohCache.removeValue(forKey: dohHost)
            }
        }
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

    private enum RouteCategory {
        case directWs(fronted: Bool, dohHost: String?)
        case cloudflare(useTLS: Bool, baseDomain: String, dohHost: String?)
        case directTcp
    }

    private enum RouteKind {
        case webSocket(connectHost: String, port: UInt16, httpHost: String, sni: String?, path: String, useTLS: Bool, trustAnyCert: Bool, timeout: Double)
        case directTcp(host: String, port: UInt16, timeout: Double)
    }

    private struct CandidateRoute {
        let id: String
        let label: String
        let category: RouteCategory
        let kind: RouteKind

        var timeout: Double {
            switch self.kind {
            case let .webSocket(_, _, _, _, _, _, _, timeout),
                 let .directTcp(_, _, timeout):
                return timeout
            }
        }
    }

    private struct SeenRouteKey: Hashable {
        let isTcp: Bool
        let connectHost: String
        let port: UInt16
        let httpHost: String
        let sni: String
        let useTLS: Bool
        let path: String
    }

    private static let dcRedirectIp = "149.154.167.220"
    private static let dcDefaultIps: [Int: String] = [
        1: "149.154.175.50",
        2: "149.154.167.51",
        3: "149.154.175.100",
        4: "149.154.167.91",
        5: "149.154.171.5",
        203: "91.105.192.100"
    ]
    private static let dcTestIps: [Int: String] = [
        1: "149.154.175.10",
        2: "149.154.167.40",
        3: "149.154.175.117"
    ]
    private static let cfConnectTimeouts: [Double] = [3.0, 3.0, 5.0, 5.0, 10.0]
    private static let frontingSni = "sprinthost.ru"
    private static let happyEyeballsStagger: Double = 0.35
    private static let tcpFallbackTailDelay: Double = 0.35

    private static func buildCandidates(
        dc: Int,
        isMedia: Bool,
        isTestDc: Bool,
        fallbackHost: String,
        fallbackPort: UInt16,
        mode: Int32,
        applyCooldownFilter: Bool,
        logPrefix: String
    ) -> [CandidateRoute] {
        let balancer = IOWsProxyBalancer.shared
        let wsDc = (dc == 203) ? 2 : dc
        let path = isTestDc ? "/apiws_test" : "/apiws"
        let directWsHosts = isMedia
            ? ["kws\(wsDc)-1.web.telegram.org", "kws\(wsDc).web.telegram.org"]
            : ["kws\(wsDc).web.telegram.org"]

        let frontingModes: [Bool] = balancer.shouldTryFrontingFirst ? [true, false] : [false, true]
        let tlsFirst = balancer.cfPrefersTls

        var list: [CandidateRoute] = []
        var seen = Set<SeenRouteKey>()

        func appendCandidate(_ candidate: CandidateRoute) {
            let key: SeenRouteKey
            switch candidate.kind {
            case let .webSocket(connectHost, port, httpHost, sni, routePath, useTLS, _, _):
                key = SeenRouteKey(
                    isTcp: false,
                    connectHost: connectHost,
                    port: port,
                    httpHost: httpHost,
                    sni: sni ?? "",
                    useTLS: useTLS,
                    path: routePath
                )
            case let .directTcp(host, port, _):
                key = SeenRouteKey(
                    isTcp: true,
                    connectHost: host,
                    port: port,
                    httpHost: "",
                    sni: "",
                    useTLS: false,
                    path: ""
                )
            }
            if seen.insert(key).inserted {
                list.append(candidate)
            }
        }

        if mode != 2 {
            // Direct WebSocket candidates:
            // 1) Static DC redirect IPs (DC2/DC4 -> 149.154.167.220) + DC_DEFAULT_IPS / DC_TEST_IPS with fronting & plain SNI
            // 2) DoH (1.1.1.1) or system DNS fallback (if distinct IP)
            var directIps: [String] = []
            var seenIps = Set<String>()
            if isTestDc {
                if let testIp = Self.dcTestIps[wsDc], seenIps.insert(testIp).inserted {
                    directIps.append(testIp)
                }
            } else {
                if (wsDc == 2 || wsDc == 4), seenIps.insert(Self.dcRedirectIp).inserted {
                    directIps.append(Self.dcRedirectIp)
                }
                if let dcIp = Self.dcDefaultIps[dc], seenIps.insert(dcIp).inserted {
                    directIps.append(dcIp)
                }
                if dc == 203, let dc2Ip = Self.dcDefaultIps[2], seenIps.insert(dc2Ip).inserted {
                    directIps.append(dc2Ip)
                }
            }

            for host in directWsHosts {
                for ip in directIps {
                    for fronted in frontingModes {
                        let sni = fronted ? Self.frontingSni : host
                        let timeout = fronted ? 7.0 : 8.0
                        let routeId = fronted ? "ws-ip-front:\(ip):\(host)" : "ws-ip:\(ip):\(host)"
                        let label = fronted ? "ws-ip \(ip) (\(host), front)" : "ws-ip \(ip) (\(host))"
                        appendCandidate(CandidateRoute(
                            id: routeId,
                            label: label,
                            category: .directWs(fronted: fronted, dohHost: nil),
                            kind: .webSocket(
                                connectHost: ip,
                                port: 443,
                                httpHost: host,
                                sni: sni,
                                path: path,
                                useTLS: true,
                                trustAnyCert: true,
                                timeout: timeout
                            )
                        ))
                    }
                }

                if let dohIp = balancer.cachedDoHIp(for: host) {
                    for fronted in frontingModes {
                        let sni = fronted ? Self.frontingSni : host
                        let timeout = fronted ? 7.0 : 8.0
                        let routeId = fronted ? "ws-doh-front:\(dohIp):\(host)" : "ws-doh:\(dohIp):\(host)"
                        let label = fronted ? "ws-doh \(dohIp) (\(host), front)" : "ws-doh \(dohIp) (\(host))"
                        appendCandidate(CandidateRoute(
                            id: routeId,
                            label: label,
                            category: .directWs(fronted: fronted, dohHost: host),
                            kind: .webSocket(
                                connectHost: dohIp,
                                port: 443,
                                httpHost: host,
                                sni: sni,
                                path: path,
                                useTLS: true,
                                trustAnyCert: true,
                                timeout: timeout
                            )
                        ))
                    }
                } else {
                    for fronted in frontingModes {
                        let sni = fronted ? Self.frontingSni : host
                        let timeout = fronted ? 7.0 : 8.0
                        let routeId = fronted ? "ws-dns-front:\(host)" : "ws-dns:\(host)"
                        let label = fronted ? "ws-dns \(host) (front)" : "ws-dns \(host)"
                        appendCandidate(CandidateRoute(
                            id: routeId,
                            label: label,
                            category: .directWs(fronted: fronted, dohHost: nil),
                            kind: .webSocket(
                                connectHost: host,
                                port: 443,
                                httpHost: host,
                                sni: sni,
                                path: path,
                                useTLS: true,
                                trustAnyCert: true,
                                timeout: timeout
                            )
                        ))
                    }
                }
            }
        }

        if !isTestDc {
            let cfLimit = (mode == 2) ? 4 : 3
            let (customSet, cfDomains) = balancer.cfDomains(forWsDc: wsDc, limit: cfLimit)

            // Order CF attempts:
            // - Custom user domains test both primary and secondary transport (443/80) back-to-back first.
            // - Pool domains alternate TLS (443) and plain ws:// (80) across domains on pass 1,
            //   then cover the opposite transport per domain on pass 2.
            var cfPlan: [(domain: String, useTLS: Bool)] = []
            var poolDomains: [String] = []
            for domain in cfDomains {
                if customSet.contains(domain) {
                    cfPlan.append((domain, tlsFirst))
                    cfPlan.append((domain, !tlsFirst))
                } else {
                    poolDomains.append(domain)
                }
            }
            for (idx, domain) in poolDomains.enumerated() {
                let useTLS = (idx % 2 == 0) ? tlsFirst : !tlsFirst
                cfPlan.append((domain, useTLS))
            }
            for (idx, domain) in poolDomains.enumerated() {
                let useTLS = (idx % 2 == 0) ? !tlsFirst : tlsFirst
                cfPlan.append((domain, useTLS))
            }

            var cfAttemptIdx = 0
            for (domain, useTLS) in cfPlan {
                let cfHost = "kws\(wsDc).\(domain)"
                let dohIp = balancer.cachedDoHIp(for: cfHost)
                let connectHost = dohIp ?? cfHost
                let port: UInt16 = useTLS ? 443 : 80
                let sni: String? = useTLS ? cfHost : nil
                let timeout = Self.cfConnectTimeouts[min(cfAttemptIdx, Self.cfConnectTimeouts.count - 1)]
                cfAttemptIdx += 1

                let prefix = useTLS
                    ? (dohIp != nil ? "cf-doh-tls" : "cf-tls")
                    : (dohIp != nil ? "cf-doh-ws" : "cf-ws")
                let baseLabel = useTLS ? "cf-tls \(cfHost)" : "cf-ws \(cfHost):80"
                let routeId: String
                let label: String
                if let dohIp {
                    routeId = "\(prefix):\(dohIp):\(cfHost)"
                    label = "\(baseLabel) [\(dohIp)]"
                } else {
                    routeId = "\(prefix):\(cfHost)"
                    label = baseLabel
                }

                appendCandidate(CandidateRoute(
                    id: routeId,
                    label: label,
                    category: .cloudflare(useTLS: useTLS, baseDomain: domain, dohHost: dohIp != nil ? cfHost : nil),
                    kind: .webSocket(
                        connectHost: connectHost,
                        port: port,
                        httpHost: cfHost,
                        sni: sni,
                        path: path,
                        useTLS: useTLS,
                        trustAnyCert: useTLS,
                        timeout: timeout
                    )
                ))
            }
        }

        if !fallbackHost.isEmpty {
            appendCandidate(CandidateRoute(
                id: "tcp:\(fallbackHost):\(fallbackPort)",
                label: "tcp \(fallbackHost):\(fallbackPort)",
                category: .directTcp,
                kind: .directTcp(host: fallbackHost, port: fallbackPort, timeout: 10.0)
            ))
        }

        guard applyCooldownFilter else {
            return list
        }

        let nonTcp = list.filter {
            if case .directTcp = $0.category { return false }
            return true
        }
        let tcpOnly = list.filter {
            if case .directTcp = $0.category { return true }
            return false
        }

        let preferredId = balancer.preferredRouteId(dc: dc, isMedia: isMedia)
        var healthyNonTcp: [CandidateRoute] = []
        for route in nonTcp where !balancer.isInCooldown(routeId: route.id) {
            if route.id == preferredId {
                healthyNonTcp.insert(route, at: 0)
            } else {
                healthyNonTcp.append(route)
            }
        }

        // If all WS/CF candidates are quarantined so only TCP would remain, retry WS/CF again anyway.
        if healthyNonTcp.isEmpty && !nonTcp.isEmpty {
            Logger.shared.log("IOWsProxy", "\(logPrefix) all WS/CF routes in cooldown for DC\(dc)\(isMedia ? "m" : ""); retrying WS/CF routes")
            healthyNonTcp = nonTcp
        }

        return healthyNonTcp + tcpOnly
    }

    private static func makeNWParameters(for kind: RouteKind, tlsVerifyQueue: DispatchQueue) -> (host: String, port: UInt16, timeout: Double, isWebSocket: Bool, parameters: NWParameters) {
        switch kind {
        case let .webSocket(connectHost, port, _, sni, _, useTLS, trustAnyCert, attemptTimeout):
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 10
            tcpOptions.keepaliveCount = 2
            tcpOptions.keepaliveInterval = 5

            let parameters: NWParameters
            if useTLS {
                let tlsOptions = NWProtocolTLS.Options()
                let sec = tlsOptions.securityProtocolOptions
                if let sni {
                    sec_protocol_options_set_tls_server_name(sec, sni)
                }
                sec_protocol_options_add_tls_application_protocol(sec, "http/1.1")
                if trustAnyCert {
                    sec_protocol_options_set_verify_block(sec, { _, _, complete in
                        complete(true)
                    }, tlsVerifyQueue)
                }
                parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            } else {
                parameters = NWParameters(tls: nil, tcp: tcpOptions)
            }
            parameters.preferNoProxies = true
            return (connectHost, port, attemptTimeout, true, parameters)

        case let .directTcp(host, port, attemptTimeout):
            let tcpOptions = NWProtocolTCP.Options()
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 5
            tcpOptions.keepaliveCount = 2
            tcpOptions.keepaliveInterval = 5
            tcpOptions.enableFastOpen = true
            let parameters = NWParameters(tls: nil, tcp: tcpOptions)
            parameters.preferNoProxies = true
            return (host, port, attemptTimeout, false, parameters)
        }
    }

    private static func buildWsUpgradeRequest(httpHost: String, path: String) -> Data {
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
        return Data(req.utf8)
    }

    private static func describeNWError(_ error: NWError) -> (isTls: Bool, tlsCode: Int32, summary: String) {
        switch error {
        case let .posix(code):
            let desc = NSError(domain: NSPOSIXErrorDomain, code: Int(code.rawValue), userInfo: nil).localizedDescription
            return (false, 0, "POSIX \(code.rawValue) (\(desc))")
        case let .dns(type):
            return (false, 0, "DNS \(type)")
        case let .tls(status):
            let desc = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            return (true, Int32(status), "TLS \(status) (\(desc))")
        default:
            return (false, 0, "\(error)")
        }
    }

    private final class DiagnosticsRunner {
        private let queue: Queue
        private let candidates: [CandidateRoute]
        private let progress: ([IOWsProxyDiagnosticRouteResult], Bool) -> Void

        private var index = 0
        private var results: [IOWsProxyDiagnosticRouteResult] = []
        private var activeConnection: NWConnection?
        private var probeTimer: SwiftSignalKit.Timer?
        private var activeBuffer = Data()
        private var activeStartedAt: CFAbsoluteTime = 0.0
        private var activeWaitingError: NWError?
        private var probeFinished = false
        private var cancelled = false

        init(
            queue: Queue,
            candidates: [CandidateRoute],
            progress: @escaping ([IOWsProxyDiagnosticRouteResult], Bool) -> Void
        ) {
            self.queue = queue
            self.candidates = candidates
            self.progress = progress
        }

        func start() {
            self.queue.async { [weak self] in
                guard let self, !self.cancelled else { return }
                Logger.shared.log("IOWsProxy", "[Diagnostics] starting sequential DC2 check (\(self.candidates.count) routes)")
                self.runNext()
            }
        }

        func cancel() {
            self.queue.async { [weak self] in
                guard let self, !self.cancelled else { return }
                self.cancelled = true
                self.cleanupActiveProbe()
                Logger.shared.log("IOWsProxy", "[Diagnostics] cancelled")
            }
        }

        private func cleanupActiveProbe() {
            self.probeTimer?.invalidate()
            self.probeTimer = nil
            if let conn = self.activeConnection {
                self.activeConnection = nil
                conn.stateUpdateHandler = nil
                conn.cancel()
            }
            self.activeBuffer.removeAll(keepingCapacity: false)
            self.activeWaitingError = nil
        }

        private func runNext() {
            guard !self.cancelled else { return }
            self.cleanupActiveProbe()

            guard self.index < self.candidates.count else {
                let finalResults = self.results
                Logger.shared.log("IOWsProxy", "[Diagnostics] finished \(finalResults.count) probes")
                Queue.mainQueue().async {
                    self.progress(finalResults, true)
                }
                return
            }

            let candidate = self.candidates[self.index]
            self.index += 1
            self.probeFinished = false
            self.activeStartedAt = CFAbsoluteTimeGetCurrent()
            self.activeWaitingError = nil
            self.activeBuffer.removeAll(keepingCapacity: true)

            let setup = IOWsProxyTcpConnectionInterface.makeNWParameters(for: candidate.kind, tlsVerifyQueue: self.queue.queue)
            let probeTimeout = setup.timeout

            guard let nwPort = NWEndpoint.Port(rawValue: setup.port) else {
                self.completeProbe(candidate: candidate, status: .networkError(detail: "invalid port \(setup.port)"))
                return
            }

            let connection = NWConnection(host: NWEndpoint.Host(setup.host), port: nwPort, using: setup.parameters)
            self.activeConnection = connection

            let queue = self.queue
            connection.stateUpdateHandler = { [weak self] state in
                queue.async {
                    guard let self, !self.cancelled, !self.probeFinished, self.activeConnection === connection else { return }
                    switch state {
                    case .ready:
                        if case let .webSocket(_, _, httpHost, _, path, _, _, _) = candidate.kind {
                            let reqData = IOWsProxyTcpConnectionInterface.buildWsUpgradeRequest(httpHost: httpHost, path: path)
                            connection.send(content: reqData, completion: .contentProcessed({ [weak self] error in
                                guard let self, let error else { return }
                                self.queue.async {
                                    guard !self.cancelled, !self.probeFinished, self.activeConnection === connection else { return }
                                    self.completeProbe(candidate: candidate, status: .networkError(detail: error.localizedDescription))
                                }
                            }))
                            self.receiveWsUpgrade(connection: connection, candidate: candidate)
                        } else {
                            self.completeProbe(candidate: candidate, status: .ok)
                        }
                    case let .waiting(error):
                        self.activeWaitingError = error
                    case let .failed(error):
                        let info = IOWsProxyTcpConnectionInterface.describeNWError(error)
                        if info.isTls {
                            self.completeProbe(candidate: candidate, status: .tlsError(code: info.tlsCode, detail: info.summary))
                        } else {
                            self.completeProbe(candidate: candidate, status: .networkError(detail: info.summary))
                        }
                    default:
                        break
                    }
                }
            }

            let timer = SwiftSignalKit.Timer(timeout: probeTimeout, repeat: false, completion: { [weak self] in
                guard let self, !self.cancelled, !self.probeFinished, self.activeConnection === connection else { return }
                if let waitingError = self.activeWaitingError {
                    let info = IOWsProxyTcpConnectionInterface.describeNWError(waitingError)
                    if info.isTls {
                        self.completeProbe(candidate: candidate, status: .tlsError(code: info.tlsCode, detail: info.summary))
                    } else {
                        self.completeProbe(candidate: candidate, status: .timeout(detail: info.summary))
                    }
                } else {
                    self.completeProbe(candidate: candidate, status: .timeout(detail: nil))
                }
            }, queue: self.queue)
            self.probeTimer = timer
            timer.start()

            connection.start(queue: self.queue.queue)
        }

        private func receiveWsUpgrade(connection: NWConnection, candidate: CandidateRoute) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, context, isComplete, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.cancelled, !self.probeFinished, self.activeConnection === connection else { return }

                    if let data, !data.isEmpty {
                        self.activeBuffer.append(data)
                        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
                        if let range = self.activeBuffer.range(of: separator) {
                            let headerData = self.activeBuffer[..<range.lowerBound]
                            let headerString = String(data: headerData, encoding: .utf8) ?? ""
                            let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
                            let parts = firstLine.split(separator: " ")
                            let statusCode = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
                            if statusCode == 101 {
                                self.completeProbe(candidate: candidate, status: .ok)
                            } else {
                                self.completeProbe(candidate: candidate, status: .httpError(code: statusCode))
                            }
                            return
                        } else if self.activeBuffer.count > 16384 {
                            self.completeProbe(candidate: candidate, status: .httpError(code: 0))
                            return
                        }
                    }

                    if let error {
                        let info = IOWsProxyTcpConnectionInterface.describeNWError(error)
                        if info.isTls {
                            self.completeProbe(candidate: candidate, status: .tlsError(code: info.tlsCode, detail: info.summary))
                        } else {
                            self.completeProbe(candidate: candidate, status: .networkError(detail: info.summary))
                        }
                        return
                    }

                    let isReadClosed = isComplete && (context?.isFinal ?? true)
                    if isReadClosed {
                        self.completeProbe(candidate: candidate, status: .networkError(detail: "EOF"))
                        return
                    }

                    self.receiveWsUpgrade(connection: connection, candidate: candidate)
                }
            }
        }

        private func completeProbe(candidate: CandidateRoute, status: IOWsProxyDiagnosticRouteResult.Status) {
            guard !self.cancelled, !self.probeFinished else { return }
            self.probeFinished = true
            let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - self.activeStartedAt) * 1000.0).rounded()))
            self.cleanupActiveProbe()

            let entry = IOWsProxyDiagnosticRouteResult(
                routeId: candidate.id,
                label: candidate.label,
                status: status,
                elapsedMs: elapsedMs
            )
            self.results.append(entry)

            let logStatus: String
            switch status {
            case .ok:
                logStatus = "ok"
            case let .timeout(detail):
                logStatus = detail != nil ? "timeout(\(detail!))" : "timeout"
            case let .httpError(code):
                logStatus = "HTTP \(code)"
            case let .tlsError(code, detail):
                logStatus = "TLS \(code) (\(detail))"
            case let .networkError(detail):
                logStatus = "error(\(detail))"
            }
            Logger.shared.log("IOWsProxy", "[Diagnostics] \(candidate.id) -> \(logStatus) in \(elapsedMs)ms")

            let snapshot = self.results
            Queue.mainQueue().async {
                self.progress(snapshot, false)
            }
            self.runNext()
        }
    }

    static func runDc2Diagnostics(
        progress: @escaping ([IOWsProxyDiagnosticRouteResult], Bool) -> Void
    ) -> Disposable {
        let mode = IOCoreConfig.current.wsProxyMode == 2 ? Int32(2) : Int32(1)
        let balancer = IOWsProxyBalancer.shared
        balancer.refreshRemoteDomainsIfNeeded()
        _ = balancer.cachedDoHIp(for: "kws2.web.telegram.org")

        let candidates = Self.buildCandidates(
            dc: 2,
            isMedia: false,
            isTestDc: false,
            fallbackHost: "149.154.167.51",
            fallbackPort: 443,
            mode: mode,
            applyCooldownFilter: false,
            logPrefix: "[Diagnostics]"
        )

        let runner = DiagnosticsRunner(queue: Self.sharedQueue, candidates: candidates, progress: progress)
        runner.start()
        return ActionDisposable {
            runner.cancel()
        }
    }

    private final class ActiveAttempt {
        let candidate: CandidateRoute
        let isWebSocket: Bool
        let startedAt: CFAbsoluteTime
        var connection: NWConnection?
        var attemptTimer: SwiftSignalKit.Timer?
        var wsHttpHandshakeDone = false
        var wsHttpBuffer = Data()
        var lastWaitingError: NWError?
        var finished = false

        init(candidate: CandidateRoute, isWebSocket: Bool, startedAt: CFAbsoluteTime) {
            self.candidate = candidate
            self.isWebSocket = isWebSocket
            self.startedAt = startedAt
        }
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
        private var nextCandidateIndex = 0
        private var activeAttempts: [ActiveAttempt] = []
        private var staggerTimer: SwiftSignalKit.Timer?
        private var tcpFallbackTimer: SwiftSignalKit.Timer?
        private var winningConnection: NWConnection?

        private var isWebSocketMode = true
        private var upstreamReady = false
        private var sentInitFrame = false
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
            self.staggerTimer?.invalidate()
            self.staggerTimer = nil
            self.tcpFallbackTimer?.invalidate()
            self.tcpFallbackTimer = nil
            for attempt in self.activeAttempts {
                attempt.finished = true
                attempt.attemptTimer?.invalidate()
                attempt.attemptTimer = nil
                if let conn = attempt.connection {
                    attempt.connection = nil
                    conn.cancel()
                }
            }
            self.activeAttempts.removeAll()
            if let connection = self.winningConnection {
                self.winningConnection = nil
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

            // Report connect readiness immediately so MTTcpConnection emits the 64-byte obfs2 header,
            // allowing exact DC ID, media flag, and test DC routing before dialing WS/CF upstream.
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
                self.startRace(initBytes: initBytes)
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

        private func startRace(initBytes: Data) {
            let parsed = self.parseObfs2Header(initBytes)
            let mode = IOCoreConfig.current.wsProxyMode

            let ordered = IOWsProxyTcpConnectionInterface.buildCandidates(
                dc: parsed.dc,
                isMedia: parsed.isMedia,
                isTestDc: parsed.isTestDc,
                fallbackHost: self.fallbackHost,
                fallbackPort: self.fallbackPort,
                mode: mode,
                applyCooldownFilter: true,
                logPrefix: self.logId
            )

            self.candidates = ordered
            self.nextCandidateIndex = 0
            Logger.shared.log("IOWsProxy", "\(self.logId) race dc=\(parsed.dc)\(parsed.isMedia ? "m" : "")\(parsed.isTestDc ? "t" : "") mode=\(mode) candidates=[\(ordered.map { $0.id }.joined(separator: ", "))]")

            guard !self.candidates.isEmpty else {
                self.failAll(error: nil, reason: "no WS/CF/TCP candidates")
                return
            }

            self.launchNextCandidate()
        }

        private func launchNextCandidate() {
            guard !self.reportedDisconnection, !self.upstreamReady else { return }
            self.staggerTimer?.invalidate()
            self.staggerTimer = nil

            guard self.nextCandidateIndex < self.candidates.count else {
                return
            }

            let candidate = self.candidates[self.nextCandidateIndex]
            self.nextCandidateIndex += 1

            self.startAttempt(candidate)

            guard !self.reportedDisconnection, !self.upstreamReady else { return }

            if self.nextCandidateIndex < self.candidates.count {
                let upcoming = self.candidates[self.nextCandidateIndex]
                if case .directTcp = upcoming.category {
                    // Direct TCP is strictly last; wait a short tail window after the final non-TCP attempt starts
                    // so healthy TLS+HTTP101 routes aren't beaten by a fast TCP SYN-ACK on DPI blackholes,
                    // or start TCP immediately once all non-TCP attempts have failed.
                    if self.activeAttempts.isEmpty {
                        self.startTcpFallbackIfNeeded()
                    } else {
                        let timer = SwiftSignalKit.Timer(timeout: IOWsProxyTcpConnectionInterface.tcpFallbackTailDelay, repeat: false, completion: { [weak self] in
                            self?.startTcpFallbackIfNeeded()
                        }, queue: self.queue)
                        self.tcpFallbackTimer?.invalidate()
                        self.tcpFallbackTimer = timer
                        timer.start()
                    }
                } else {
                    let timer = SwiftSignalKit.Timer(timeout: IOWsProxyTcpConnectionInterface.happyEyeballsStagger, repeat: false, completion: { [weak self] in
                        self?.launchNextCandidate()
                    }, queue: self.queue)
                    self.staggerTimer = timer
                    timer.start()
                }
            }
        }

        private func startTcpFallbackIfNeeded() {
            guard !self.reportedDisconnection, !self.upstreamReady else { return }
            self.tcpFallbackTimer?.invalidate()
            self.tcpFallbackTimer = nil

            guard self.nextCandidateIndex < self.candidates.count,
                  case .directTcp = self.candidates[self.nextCandidateIndex].category else {
                return
            }

            let tcpCandidate = self.candidates[self.nextCandidateIndex]
            self.nextCandidateIndex += 1
            self.startAttempt(tcpCandidate)
        }

        private func startAttempt(_ candidate: CandidateRoute) {
            let setup = IOWsProxyTcpConnectionInterface.makeNWParameters(for: candidate.kind, tlsVerifyQueue: self.queue.queue)

            guard let nwPort = NWEndpoint.Port(rawValue: setup.port) else {
                Logger.shared.log("IOWsProxy", "\(self.logId) invalid port for \(candidate.id)")
                if self.activeAttempts.isEmpty {
                    self.advanceAfterAllAttemptsFailedOrAdvance()
                }
                return
            }

            let attempt = ActiveAttempt(
                candidate: candidate,
                isWebSocket: setup.isWebSocket,
                startedAt: CFAbsoluteTimeGetCurrent()
            )
            let connection = NWConnection(host: NWEndpoint.Host(setup.host), port: nwPort, using: setup.parameters)
            attempt.connection = connection
            self.activeAttempts.append(attempt)

            let queue = self.queue
            connection.pathUpdateHandler = { [weak self, weak attempt] path in
                queue.async {
                    guard let self, !self.reportedDisconnection else { return }
                    if self.upstreamReady {
                        if self.winningConnection === connection {
                            self.currentInterfaceIsWifi = !path.usesInterfaceType(.cellular)
                        }
                    } else if let attempt, !attempt.finished, attempt.connection === connection {
                        self.currentInterfaceIsWifi = !path.usesInterfaceType(.cellular)
                    }
                }
            }

            connection.stateUpdateHandler = { [weak self, weak attempt] state in
                queue.async {
                    guard let self, !self.reportedDisconnection else { return }
                    if self.upstreamReady {
                        if self.winningConnection === connection, case let .failed(error) = state {
                            self.failAll(error: error, reason: "upstream failed")
                        }
                        return
                    }
                    guard let attempt, !attempt.finished, attempt.connection === connection else { return }
                    self.handleAttemptState(attempt: attempt, connection: connection, state: state)
                }
            }

            let timer = SwiftSignalKit.Timer(timeout: setup.timeout, repeat: false, completion: { [weak self, weak attempt] in
                guard let self, let attempt, !self.reportedDisconnection, !self.upstreamReady, !attempt.finished else { return }
                let detail = attempt.lastWaitingError.map { " (\(IOWsProxyTcpConnectionInterface.describeNWError($0).summary))" } ?? ""
                self.failAttempt(attempt, reason: "timed out after \(setup.timeout)s\(detail)", countFailure: true)
            }, queue: self.queue)
            attempt.attemptTimer = timer
            timer.start()

            connection.start(queue: self.queue.queue)
        }

        private func handleAttemptState(attempt: ActiveAttempt, connection: NWConnection, state: NWConnection.State) {
            switch state {
            case .ready:
                if case let .webSocket(_, _, httpHost, _, path, _, _, _) = attempt.candidate.kind {
                    let reqData = IOWsProxyTcpConnectionInterface.buildWsUpgradeRequest(httpHost: httpHost, path: path)
                    connection.send(content: reqData, completion: .contentProcessed({ [weak self, weak attempt] error in
                        guard let self, let error else { return }
                        self.queue.async {
                            guard !self.reportedDisconnection, !self.upstreamReady, let attempt, !attempt.finished, attempt.connection === connection else { return }
                            self.failAttempt(attempt, reason: "ws upgrade send failed: \(error.localizedDescription)", countFailure: true)
                        }
                    }))
                    self.receiveLoop(connection: connection, attempt: attempt)
                } else {
                    self.promoteWinner(attempt: attempt, connection: connection, trailingWsBytes: Data())
                    self.receiveLoop(connection: connection, attempt: nil)
                }
            case let .waiting(error):
                attempt.lastWaitingError = error
            case let .failed(error):
                let desc = IOWsProxyTcpConnectionInterface.describeNWError(error).summary
                self.failAttempt(attempt, reason: desc, countFailure: true)
            default:
                break
            }
        }

        private func failAttempt(_ attempt: ActiveAttempt, reason: String, countFailure: Bool) {
            guard !self.reportedDisconnection, !self.upstreamReady, !attempt.finished else { return }
            attempt.finished = true
            attempt.attemptTimer?.invalidate()
            attempt.attemptTimer = nil
            if let conn = attempt.connection {
                attempt.connection = nil
                conn.stateUpdateHandler = nil
                conn.pathUpdateHandler = nil
                conn.cancel()
            }
            self.activeAttempts.removeAll { $0 === attempt }

            let elapsedMs = Int(((CFAbsoluteTimeGetCurrent() - attempt.startedAt) * 1000.0).rounded())
            Logger.shared.log("IOWsProxy", "\(self.logId) candidate \(attempt.candidate.id) failed (\(elapsedMs)ms): \(reason)")

            if countFailure {
                let dohHost: String?
                switch attempt.candidate.category {
                case let .directWs(_, host),
                     let .cloudflare(_, _, host):
                    dohHost = host
                case .directTcp:
                    dohHost = nil
                }
                IOWsProxyBalancer.shared.markRouteFailed(routeId: attempt.candidate.id, dohHost: dohHost)
            }

            self.advanceAfterAllAttemptsFailedOrAdvance()
        }

        private func advanceAfterAllAttemptsFailedOrAdvance() {
            guard !self.reportedDisconnection, !self.upstreamReady else { return }

            if self.nextCandidateIndex < self.candidates.count {
                let upcoming = self.candidates[self.nextCandidateIndex]
                if case .directTcp = upcoming.category {
                    if self.activeAttempts.isEmpty {
                        self.startTcpFallbackIfNeeded()
                    }
                } else if self.activeAttempts.isEmpty {
                    self.launchNextCandidate()
                }
                return
            }

            if self.activeAttempts.isEmpty {
                self.failAll(error: nil, reason: "all WS/CF/TCP routes failed")
            }
        }

        private func promoteWinner(attempt: ActiveAttempt, connection: NWConnection, trailingWsBytes: Data) {
            guard !self.reportedDisconnection, !self.upstreamReady, !attempt.finished else { return }
            attempt.finished = true
            attempt.attemptTimer?.invalidate()
            attempt.attemptTimer = nil

            self.staggerTimer?.invalidate()
            self.staggerTimer = nil
            self.tcpFallbackTimer?.invalidate()
            self.tcpFallbackTimer = nil

            self.upstreamReady = true
            self.isWebSocketMode = attempt.isWebSocket
            self.winningConnection = connection
            self.wsFrameBuffer.removeAll(keepingCapacity: true)
            self.wsFragmentBuffer.removeAll(keepingCapacity: true)
            self.wsClosed = false

            for other in self.activeAttempts where other !== attempt {
                other.finished = true
                other.attemptTimer?.invalidate()
                other.attemptTimer = nil
                if let conn = other.connection {
                    other.connection = nil
                    conn.stateUpdateHandler = nil
                    conn.pathUpdateHandler = nil
                    conn.cancel()
                }
            }
            self.activeAttempts.removeAll()
            attempt.connection = nil

            let parsed = self.parseObfs2Header(self.header64)
            let wsDc = (parsed.dc == 203) ? 2 : parsed.dc
            let usedFronting: Bool?
            let usedCfTls: Bool?
            let cfBaseDomain: String?
            switch attempt.candidate.category {
            case let .directWs(fronted, _):
                usedFronting = fronted
                usedCfTls = nil
                cfBaseDomain = nil
            case let .cloudflare(useTLS, baseDomain, _):
                usedFronting = nil
                usedCfTls = useTLS
                cfBaseDomain = baseDomain
            case .directTcp:
                usedFronting = nil
                usedCfTls = nil
                cfBaseDomain = nil
            }

            IOWsProxyBalancer.shared.markRouteSuccess(
                dc: parsed.dc,
                wsDc: wsDc,
                isMedia: parsed.isMedia,
                routeId: attempt.candidate.id,
                usedFronting: usedFronting,
                usedCfTls: usedCfTls,
                cfBaseDomain: cfBaseDomain
            )

            let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - attempt.startedAt) * 1000.0).rounded()))
            Logger.shared.log("IOWsProxy", "\(self.logId) connected via \(attempt.candidate.id) (\(elapsedMs)ms)")

            self.flushQueuedWrites()

            if !trailingWsBytes.isEmpty {
                self.wsFrameBuffer.append(trailingWsBytes)
                self.processWsFrames(connection: connection)
            }
        }

        private func flushQueuedWrites() {
            guard self.upstreamReady, let connection = self.winningConnection else { return }
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
            guard !data.isEmpty, let connection = self.winningConnection, self.upstreamReady else { return }
            self.rawSendUpstream(connection: connection, payload: data, isWebSocket: self.isWebSocketMode)
        }

        private func rawSendUpstream(connection: NWConnection, payload: Data, isWebSocket: Bool) {
            let wireData = isWebSocket ? Self.buildWsFrame(opcode: 0x2, payload: payload) : payload
            self.networkUsageManager?.addOutgoingBytes(UInt(payload.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
            connection.send(content: wireData, completion: .contentProcessed({ [weak self] error in
                guard let self, let error else { return }
                self.queue.async {
                    guard self.winningConnection === connection else { return }
                    self.failAll(error: error, reason: "send failed")
                }
            }))
        }

        private func receiveLoop(connection: NWConnection, attempt: ActiveAttempt?) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self, weak attempt] data, context, isComplete, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.reportedDisconnection else { return }

                    if self.upstreamReady {
                        guard self.winningConnection === connection else { return }
                        if let data, !data.isEmpty {
                            if self.isWebSocketMode {
                                self.wsFrameBuffer.append(data)
                                self.processWsFrames(connection: connection)
                            } else {
                                self.networkUsageManager?.addIncomingBytes(UInt(data.count), interface: self.currentInterfaceIsWifi ? MTNetworkUsageManagerInterfaceOther : MTNetworkUsageManagerInterfaceWWAN)
                                self.incomingBuffer.append(data)
                                self.drainReadRequests()
                            }
                        }
                        if let error {
                            self.failAll(error: error, reason: "receive failed")
                            return
                        }
                        let isReadClosed = isComplete && (context?.isFinal ?? true)
                        if isReadClosed || self.wsClosed {
                            self.failAll(error: nil, reason: "remote closed connection")
                            return
                        }
                        self.receiveLoop(connection: connection, attempt: nil)
                        return
                    }

                    guard let attempt, !attempt.finished, attempt.connection === connection else { return }

                    if let data, !data.isEmpty {
                        self.handleAttemptWsBytes(data, connection: connection, attempt: attempt)
                        if self.upstreamReady && self.winningConnection === connection {
                            if let error {
                                self.failAll(error: error, reason: "receive failed")
                                return
                            }
                            let isReadClosed = isComplete && (context?.isFinal ?? true)
                            if isReadClosed || self.wsClosed {
                                self.failAll(error: nil, reason: "remote closed connection")
                                return
                            }
                            self.receiveLoop(connection: connection, attempt: nil)
                            return
                        }
                        if attempt.finished {
                            return
                        }
                    }

                    if let error {
                        let desc = IOWsProxyTcpConnectionInterface.describeNWError(error).summary
                        self.failAttempt(attempt, reason: "receive: \(desc)", countFailure: true)
                        return
                    }

                    let isReadClosed = isComplete && (context?.isFinal ?? true)
                    if isReadClosed {
                        self.failAttempt(attempt, reason: "remote closed before HTTP 101", countFailure: true)
                        return
                    }

                    self.receiveLoop(connection: connection, attempt: attempt)
                }
            }
        }

        private func handleAttemptWsBytes(_ data: Data, connection: NWConnection, attempt: ActiveAttempt) {
            attempt.wsHttpBuffer.append(data)
            let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
            if let range = attempt.wsHttpBuffer.range(of: separator) {
                let headerData = attempt.wsHttpBuffer[..<range.lowerBound]
                let remainder = Data(attempt.wsHttpBuffer[range.upperBound...])
                attempt.wsHttpBuffer.removeAll(keepingCapacity: false)

                let headerString = String(data: headerData, encoding: .utf8) ?? ""
                let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                let statusCode = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
                guard statusCode == 101 else {
                    self.failAttempt(attempt, reason: "HTTP \(statusCode) != 101", countFailure: true)
                    return
                }

                attempt.wsHttpHandshakeDone = true
                self.promoteWinner(attempt: attempt, connection: connection, trailingWsBytes: remainder)
            } else if attempt.wsHttpBuffer.count > 16384 {
                self.failAttempt(attempt, reason: "HTTP upgrade response too large", countFailure: true)
            }
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
            self.staggerTimer?.invalidate()
            self.staggerTimer = nil
            self.tcpFallbackTimer?.invalidate()
            self.tcpFallbackTimer = nil
            for attempt in self.activeAttempts {
                attempt.finished = true
                attempt.attemptTimer?.invalidate()
                attempt.attemptTimer = nil
                if let conn = attempt.connection {
                    attempt.connection = nil
                    conn.stateUpdateHandler = nil
                    conn.pathUpdateHandler = nil
                    conn.cancel()
                }
            }
            self.activeAttempts.removeAll()
            if let connection = self.winningConnection {
                self.winningConnection = nil
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
