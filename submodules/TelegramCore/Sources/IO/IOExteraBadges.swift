import Foundation
import Postbox
import SwiftSignalKit

public enum IOExteraProfileStatus: String, Codable, Equatable, Sendable {
    case `default` = "DEFAULT"
    case developer = "DEVELOPER"
    case supporter = "SUPPORTER"
    case other = "OTHER"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? "DEFAULT"
        self = IOExteraProfileStatus(rawValue: rawValue.uppercased()) ?? .other
    }
}

public enum IOExteraProfileType: String, Codable, Equatable, Sendable {
    case user = "USER"
    case chat = "CHAT"
    case other = "OTHER"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? "USER"
        self = IOExteraProfileType(rawValue: rawValue.uppercased()) ?? .other
    }
}

public struct IOExteraBadge: Codable, Equatable, Sendable {
    public let documentId: Int64
    public let text: String?

    public init(documentId: Int64, text: String?) {
        self.documentId = documentId
        self.text = text
    }
}

public struct IOExteraBadgeProfile: Codable, Equatable, Sendable {
    public let id: Int64
    public let type: IOExteraProfileType
    public let status: IOExteraProfileStatus
    public let badge: IOExteraBadge?
    public let deleted: Bool?
    public let canChangeBadge: Bool?
    public let number: Int32?
}

public struct IOExteraBadgeResolved: Equatable, Sendable {
    public let documentId: Int64
    public let text: String?
    public let status: IOExteraProfileStatus
    public let number: Int32?
}

private struct IOExteraBadgeCacheKey: Hashable, Codable, Sendable {
    let id: Int64
    let isUser: Bool
}

private struct IOExteraBadgeCacheSnapshot: Codable {
    var profiles: [IOExteraBadgeProfile]
    var etag: String?
    var lastSyncTimestamp: String?
    var lastSyncTime: TimeInterval
}

public final class IOExteraBadges: @unchecked Sendable {
    public static let shared = IOExteraBadges()

    public static let devBadgeDocumentId: Int64 = 5359407509327085568
    public static let supporterBadgeDocumentId: Int64 = 5391059537102927631
    public static let trustedBadgeDocumentId: Int64 = 5452008215409629764
    private static let trustedChatIds: Set<Int64> = [2562664432]

    private static let baseUrl = "https://api.exteragram.app/api/v1"
    private static let syncInterval: TimeInterval = 10.0 * 60.0
    private static let failureBackoff: TimeInterval = 5.0 * 60.0

    private let lock = NSLock()
    private var profileMap: [IOExteraBadgeCacheKey: IOExteraBadgeProfile] = [:]
    private var cacheFileUrl: URL?
    private var etag: String?
    private var lastSyncTimestamp: String?
    private var lastSyncTime: TimeInterval = 0.0
    private var lastFailureTime: TimeInterval = 0.0
    private var isSyncing = false
    private var pendingCompletions: [@Sendable (Int, Bool) -> Void] = []

    private init() {
    }

    public var cachedProfileCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.profileMap.count
    }

    public func configureCache(basePath: String) {
        let url = URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent("io_extera_badges.json")
        self.lock.lock()
        let alreadyConfigured = (self.cacheFileUrl == url)
        self.cacheFileUrl = url
        self.lock.unlock()

        if !alreadyConfigured {
            self.loadCacheFromDisk(url: url)
        }
    }

    private func loadCacheFromDisk(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        guard let snapshot = try? JSONDecoder().decode(IOExteraBadgeCacheSnapshot.self, from: data) else {
            return
        }
        var map: [IOExteraBadgeCacheKey: IOExteraBadgeProfile] = [:]
        map.reserveCapacity(snapshot.profiles.count)
        for profile in snapshot.profiles where profile.deleted != true {
            let key = IOExteraBadgeCacheKey(id: profile.id, isUser: profile.type != .chat)
            map[key] = profile
        }
        self.lock.lock()
        self.profileMap = map
        self.etag = snapshot.etag
        self.lastSyncTimestamp = snapshot.lastSyncTimestamp
        self.lastSyncTime = snapshot.lastSyncTime
        self.lock.unlock()
    }

    private func persistCacheToDisk(url: URL?, snapshot: IOExteraBadgeCacheSnapshot) {
        guard let url else {
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func badgeDocumentId(forPeerId peerId: PeerId) -> Int64? {
        guard IOCoreConfig.current.showExteraBadges else {
            return nil
        }
        return self.resolveBadge(forPeerId: peerId)?.documentId
    }

    public func resolveBadge(forPeerId peerId: PeerId) -> IOExteraBadgeResolved? {
        guard IOCoreConfig.current.showExteraBadges else {
            return nil
        }
        let isUser: Bool
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            isUser = true
        case Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel:
            isUser = false
        default:
            return nil
        }

        let bareId = peerId.id._internalGetInt64Value()
        if !isUser && Self.trustedChatIds.contains(bareId) {
            return IOExteraBadgeResolved(
                documentId: Self.trustedBadgeDocumentId,
                text: "Trusted plugin source",
                status: .default,
                number: nil
            )
        }

        self.lock.lock()
        let profile = self.profileMap[IOExteraBadgeCacheKey(id: bareId, isUser: isUser)]
        self.lock.unlock()

        guard let profile, profile.deleted != true else {
            return nil
        }

        if let badge = profile.badge, badge.documentId != 0 {
            return IOExteraBadgeResolved(
                documentId: badge.documentId,
                text: badge.text,
                status: profile.status,
                number: profile.number
            )
        }

        switch profile.status {
        case .developer:
            return IOExteraBadgeResolved(
                documentId: Self.devBadgeDocumentId,
                text: nil,
                status: .developer,
                number: profile.number
            )
        case .supporter:
            return IOExteraBadgeResolved(
                documentId: Self.supporterBadgeDocumentId,
                text: nil,
                status: .supporter,
                number: profile.number
            )
        case .default, .other:
            return nil
        }
    }

    public func syncIfNeeded(force: Bool = false, completion: (@Sendable (Int, Bool) -> Void)? = nil) {
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        if let completion {
            self.pendingCompletions.append(completion)
        }
        if self.isSyncing {
            self.lock.unlock()
            return
        }
        if !force {
            if self.lastFailureTime > 0.0 && (now - self.lastFailureTime) < Self.failureBackoff {
                let completions = self.pendingCompletions
                let count = self.profileMap.count
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                for cb in completions {
                    cb(count, false)
                }
                return
            }
            if self.lastSyncTime > 0.0 && (now - self.lastSyncTime) < Self.syncInterval && !self.profileMap.isEmpty {
                let completions = self.pendingCompletions
                let count = self.profileMap.count
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                for cb in completions {
                    cb(count, true)
                }
                return
            }
        }

        let currentTimestamp = force ? nil : self.lastSyncTimestamp
        let currentEtag = force ? nil : self.etag
        self.isSyncing = true
        self.lock.unlock()

        var urlComponents = URLComponents(string: currentTimestamp == nil ? "\(Self.baseUrl)/profiles" : "\(Self.baseUrl)/profiles/updates")!
        if let currentTimestamp {
            urlComponents.queryItems = [URLQueryItem(name: "since", value: currentTimestamp)]
        }
        guard let url = urlComponents.url else {
            self.finishSync(success: false, profiles: nil, etag: nil, syncTimestamp: nil)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let currentEtag {
            request.setValue(currentEtag, forHTTPHeaderField: "If-None-Match")
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                return
            }
            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                self.finishSync(success: false, profiles: nil, etag: nil, syncTimestamp: nil)
                return
            }

            let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
            let responseSyncTimestamp = httpResponse.value(forHTTPHeaderField: "X-Sync-Timestamp")

            if httpResponse.statusCode == 304 {
                self.finishSync(success: true, profiles: [], etag: responseEtag ?? currentEtag, syncTimestamp: responseSyncTimestamp)
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode), let data else {
                self.finishSync(success: false, profiles: nil, etag: nil, syncTimestamp: nil)
                return
            }

            do {
                let profiles = try JSONDecoder().decode([IOExteraBadgeProfile].self, from: data)
                self.finishSync(success: true, profiles: profiles, etag: responseEtag, syncTimestamp: responseSyncTimestamp, fullReplace: currentTimestamp == nil)
            } catch {
                self.finishSync(success: false, profiles: nil, etag: nil, syncTimestamp: nil)
            }
        }
        task.resume()
    }

    private func finishSync(
        success: Bool,
        profiles: [IOExteraBadgeProfile]?,
        etag: String?,
        syncTimestamp: String?,
        fullReplace: Bool = false
    ) {
        let now = Date().timeIntervalSince1970
        var snapshotToSave: (URL?, IOExteraBadgeCacheSnapshot)?

        self.lock.lock()
        self.isSyncing = false
        if success, let profiles {
            if fullReplace {
                self.profileMap.removeAll(keepingCapacity: true)
            }
            for profile in profiles {
                let key = IOExteraBadgeCacheKey(id: profile.id, isUser: profile.type != .chat)
                if profile.deleted == true {
                    self.profileMap.removeValue(forKey: key)
                } else {
                    self.profileMap[key] = profile
                }
            }
            if let etag {
                self.etag = etag
            }
            if let syncTimestamp, !syncTimestamp.isEmpty {
                self.lastSyncTimestamp = syncTimestamp
            } else {
                self.lastSyncTimestamp = ISO8601DateFormatter().string(from: Date())
            }
            self.lastSyncTime = now
            self.lastFailureTime = 0.0

            if let cacheUrl = self.cacheFileUrl {
                let snapshot = IOExteraBadgeCacheSnapshot(
                    profiles: Array(self.profileMap.values),
                    etag: self.etag,
                    lastSyncTimestamp: self.lastSyncTimestamp,
                    lastSyncTime: self.lastSyncTime
                )
                snapshotToSave = (cacheUrl, snapshot)
            }
        } else {
            self.lastFailureTime = now
        }
        let count = self.profileMap.count
        let completions = self.pendingCompletions
        self.pendingCompletions.removeAll()
        self.lock.unlock()

        if let (url, snapshot) = snapshotToSave {
            self.persistCacheToDisk(url: url, snapshot: snapshot)
        }
        for cb in completions {
            cb(count, success)
        }
    }
}
