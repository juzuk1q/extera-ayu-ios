import Foundation
import Postbox
import SwiftSignalKit

public struct IOCCoreConfig: Equatable {
    public var saveDeletedMessages: Bool
    public var saveMessagesHistory: Bool
    public var saveForBots: Bool
    public var ghostDontSendOnline: Bool
    public var ghostDontSendTyping: Bool
    public var disableAds: Bool
    public var hideReactionsInPrivateChats: Bool
    public var hideReactionsInChannels: Bool
    public var hideReactionsInGroups: Bool

    public static let defaultConfig = IOCCoreConfig(
        saveDeletedMessages: true,
        saveMessagesHistory: true,
        saveForBots: false,
        ghostDontSendOnline: false,
        ghostDontSendTyping: false,
        disableAds: true,
        hideReactionsInPrivateChats: false,
        hideReactionsInChannels: false,
        hideReactionsInGroups: false
    )

    public init(
        saveDeletedMessages: Bool,
        saveMessagesHistory: Bool,
        saveForBots: Bool,
        ghostDontSendOnline: Bool,
        ghostDontSendTyping: Bool,
        disableAds: Bool,
        hideReactionsInPrivateChats: Bool = false,
        hideReactionsInChannels: Bool = false,
        hideReactionsInGroups: Bool = false
    ) {
        self.saveDeletedMessages = saveDeletedMessages
        self.saveMessagesHistory = saveMessagesHistory
        self.saveForBots = saveForBots
        self.ghostDontSendOnline = ghostDontSendOnline
        self.ghostDontSendTyping = ghostDontSendTyping
        self.disableAds = disableAds
        self.hideReactionsInPrivateChats = hideReactionsInPrivateChats
        self.hideReactionsInChannels = hideReactionsInChannels
        self.hideReactionsInGroups = hideReactionsInGroups
    }

    private static let currentValue = Atomic<IOCCoreConfig>(value: .defaultConfig)

    public static var current: IOCCoreConfig {
        return self.currentValue.with { $0 }
    }

    public static func setCurrent(_ config: IOCCoreConfig) {
        let _ = self.currentValue.swap(config)
    }
}

public final class IOCDeletedMessageAttribute: MessageAttribute, Equatable {
    public let deletedTimestamp: Int32
    public let associatedPeerIds: [PeerId] = []
    public let associatedMediaIds: [MediaId] = []

    public init(deletedTimestamp: Int32) {
        self.deletedTimestamp = deletedTimestamp
    }

    public required init(decoder: PostboxDecoder) {
        self.deletedTimestamp = decoder.decodeInt32ForKey("dt", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedTimestamp, forKey: "dt")
    }

    public static func ==(lhs: IOCDeletedMessageAttribute, rhs: IOCDeletedMessageAttribute) -> Bool {
        return lhs.deletedTimestamp == rhs.deletedTimestamp
    }
}

public final class IOCMessageEditRevision: PostboxCoding, Equatable {
    public let text: String
    public let timestamp: Int32
    public let hasMedia: Bool

    public init(text: String, timestamp: Int32, hasMedia: Bool) {
        self.text = text
        self.timestamp = timestamp
        self.hasMedia = hasMedia
    }

    public required init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("t", orElse: "")
        self.timestamp = decoder.decodeInt32ForKey("ts", orElse: 0)
        self.hasMedia = decoder.decodeInt32ForKey("hm", orElse: 0) != 0
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "t")
        encoder.encodeInt32(self.timestamp, forKey: "ts")
        encoder.encodeInt32(self.hasMedia ? 1 : 0, forKey: "hm")
    }

    public static func ==(lhs: IOCMessageEditRevision, rhs: IOCMessageEditRevision) -> Bool {
        return lhs.text == rhs.text && lhs.timestamp == rhs.timestamp && lhs.hasMedia == rhs.hasMedia
    }
}

public final class IOCEditHistoryMessageAttribute: MessageAttribute, Equatable {
    public let revisions: [IOCMessageEditRevision]
    public let associatedPeerIds: [PeerId] = []
    public let associatedMediaIds: [MediaId] = []

    public init(revisions: [IOCMessageEditRevision]) {
        self.revisions = revisions
    }

    public required init(decoder: PostboxDecoder) {
        self.revisions = decoder.decodeObjectArrayWithDecoderForKey("r")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.revisions, forKey: "r")
    }

    public static func ==(lhs: IOCEditHistoryMessageAttribute, rhs: IOCEditHistoryMessageAttribute) -> Bool {
        return lhs.revisions == rhs.revisions
    }
}

private struct IOCStoredMessageId: Codable, Hashable {
    var peerId: Int64
    var namespace: Int32
    var id: Int32

    init(_ messageId: MessageId) {
        self.peerId = messageId.peerId.toInt64()
        self.namespace = messageId.namespace
        self.id = messageId.id
    }

    var messageId: MessageId {
        return MessageId(peerId: PeerId(self.peerId), namespace: self.namespace, id: self.id)
    }
}

private struct IOCDeletedMessageIndex: Codable, Equatable {
    var items: [IOCStoredMessageId]
}

private let iocDeletedIndexKey = ValueBoxKey("ioc.deletedIndex")

private func appendToDeletedIndex(transaction: Transaction, messageIds: [MessageId]) {
    guard !messageIds.isEmpty else {
        return
    }
    var index = transaction.getPreferencesEntry(key: iocDeletedIndexKey)?.get(IOCDeletedMessageIndex.self) ?? IOCDeletedMessageIndex(items: [])
    var existing = Set(index.items)
    for id in messageIds {
        let stored = IOCStoredMessageId(id)
        if existing.insert(stored).inserted {
            index.items.append(stored)
        }
    }
    if let entry = PreferencesEntry(index) {
        transaction.setPreferencesEntry(key: iocDeletedIndexKey, value: entry)
    }
}

private func removeFromDeletedIndex(transaction: Transaction, messageIds: [MessageId]) {
    guard !messageIds.isEmpty else {
        return
    }
    guard var index = transaction.getPreferencesEntry(key: iocDeletedIndexKey)?.get(IOCDeletedMessageIndex.self) else {
        return
    }
    let removeSet = Set(messageIds.map(IOCStoredMessageId.init))
    index.items.removeAll(where: { removeSet.contains($0) })
    if let entry = PreferencesEntry(index) {
        transaction.setPreferencesEntry(key: iocDeletedIndexKey, value: entry)
    }
}

func iocShouldPreserveDeletedMessage(transaction: Transaction, messageId: MessageId) -> Bool {
    guard IOCCoreConfig.current.saveDeletedMessages else {
        return false
    }
    guard let message = transaction.getMessage(messageId) else {
        return false
    }
    if !IOCCoreConfig.current.saveForBots {
        if let user = transaction.getPeer(messageId.peerId) as? TelegramUser, user.botInfo != nil {
            return false
        }
        if let author = message.author as? TelegramUser, author.botInfo != nil, messageId.peerId.namespace == Namespaces.Peer.CloudUser {
            return false
        }
    }
    return true
}

@discardableResult
func iocMarkMessagesDeletedOrPurge(
    transaction: Transaction,
    mediaBox: MediaBox,
    ids: [MessageId],
    manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil
) -> [MessageId] {
    var preservedIds: [MessageId] = []
    var purgeIds: [MessageId] = []

    for id in ids {
        if iocShouldPreserveDeletedMessage(transaction: transaction, messageId: id) {
            preservedIds.append(id)
        } else {
            purgeIds.append(id)
        }
    }

    if !preservedIds.isEmpty {
        let now = Int32(Date().timeIntervalSince1970)
        for id in preservedIds {
            transaction.updateMessage(id, update: { currentMessage in
                if currentMessage.attributes.contains(where: { $0 is IOCDeletedMessageAttribute }) {
                    return .skip
                }
                var attributes = currentMessage.attributes
                attributes.append(IOCDeletedMessageAttribute(deletedTimestamp: now))
                return .update(StoreMessage(updating: currentMessage, attributes: attributes, tags: currentMessage.tags))
            })
        }
        appendToDeletedIndex(transaction: transaction, messageIds: preservedIds)
    }

    if !purgeIds.isEmpty {
        _internal_deleteMessages(
            transaction: transaction,
            mediaBox: mediaBox,
            ids: purgeIds,
            manualAddMessageThreadStatsDifference: manualAddMessageThreadStatsDifference
        )
    }

    return purgeIds
}

func iocApplyEditHistory(previousMessage: Message, updatedMessage: StoreMessage) -> StoreMessage {
    var attributes = updatedMessage.attributes

    if let deletedAttribute = previousMessage.attributes.first(where: { $0 is IOCDeletedMessageAttribute }) as? IOCDeletedMessageAttribute {
        if !attributes.contains(where: { $0 is IOCDeletedMessageAttribute }) {
            attributes.append(deletedAttribute)
        }
    }

    guard IOCCoreConfig.current.saveMessagesHistory else {
        return updatedMessage.withUpdatedAttributes(attributes)
    }

    var revisions = (previousMessage.attributes.first(where: { $0 is IOCEditHistoryMessageAttribute }) as? IOCEditHistoryMessageAttribute)?.revisions ?? []

    let textChanged = previousMessage.text != updatedMessage.text
    let mediaChanged = previousMessage.media.count != updatedMessage.media.count
    if textChanged || mediaChanged {
        let previousTimestamp = previousMessage.editedTime ?? previousMessage.timestamp
        let previousHasMedia = !previousMessage.media.isEmpty
        if revisions.last?.text != previousMessage.text || revisions.last?.hasMedia != previousHasMedia {
            revisions.append(IOCMessageEditRevision(
                text: previousMessage.text,
                timestamp: previousTimestamp,
                hasMedia: previousHasMedia
            ))
        }
    }

    if !revisions.isEmpty {
        attributes.removeAll(where: { $0 is IOCEditHistoryMessageAttribute })
        attributes.append(IOCEditHistoryMessageAttribute(revisions: revisions))
    }

    return updatedMessage.withUpdatedAttributes(attributes)
}

public func iocPurgeSavedDeletedMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        removeFromDeletedIndex(transaction: transaction, messageIds: [messageId])
        _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: [messageId])
    }
}

public func iocClearAllSavedDeletedMessages(account: Account) -> Signal<Int, NoError> {
    return account.postbox.transaction { transaction -> Int in
        guard let index = transaction.getPreferencesEntry(key: iocDeletedIndexKey)?.get(IOCDeletedMessageIndex.self), !index.items.isEmpty else {
            return 0
        }
        let ids = index.items.map(\.messageId)
        let count = ids.count
        _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: ids)
        if let entry = PreferencesEntry(IOCDeletedMessageIndex(items: [])) {
            transaction.setPreferencesEntry(key: iocDeletedIndexKey, value: entry)
        }
        return count
    }
}

public func iocMarkPeerRead(account: Account, peerId: PeerId) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        if let index = transaction.getTopPeerMessageIndex(peerId: peerId) {
            _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: account.stateManager, index: index)
        }
    }
}
