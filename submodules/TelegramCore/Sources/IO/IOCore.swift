import Foundation
import Postbox
import SwiftSignalKit

public struct IOCoreConfig: Equatable {
    public var saveDeletedMessages: Bool
    public var saveMessagesHistory: Bool
    public var saveForBots: Bool
    public var ghostDontSendOnline: Bool
    public var ghostDontSendTyping: Bool
    public var disableAds: Bool
    public var hideReactionsInPrivateChats: Bool
    public var hideReactionsInChannels: Bool
    public var hideReactionsInGroups: Bool
    public var showExteraBadges: Bool
    public var replaceEditedWithIcon: Bool
    public var saveDisappearingMedia: Bool
    public var disableScreenshotProtection: Bool
    public var showFlameOnSelfDestruct: Bool
    public var hideSideShareButton: Bool
    public var hidePhoneNumber: Bool
    public var downloadSpeedBoost: Int32
    public var uploadSpeedBoost: Bool
    public var avatarCornerRadiusPercent: Int32
    public var singleCornerRadius: Bool
    public var showForwardCount: Bool
    public var stickerSizePercent: Int32
    public var hideKeyboardOnScroll: Bool
    public var hideSendAsButton: Bool
    public var confirmSendingVoice: Bool
    public var confirmSendingRoundVideo: Bool
    public var alwaysSendInHD: Bool
    public var doubleTapSeekSeconds: Int32
    public var sendWithoutSoundMode: Int32
    public var wsProxyMode: Int32
    public var wsProxyCustomDomains: String
    public var customChatListTitle: String
    public var bypassCopyProtection: Bool
    public var ghostDontReadStories: Bool
    public var alwaysOnline: Bool
    public var disablePerChatWallpapers: Bool
    public var spoofDeviceModel: String
    public var spoofSystemVersion: String
    public var ghostAskBeforeReadingStories: Bool
    public var roundVideo60Fps: Bool

    public static let wsProxySettingsChangedNotification = Notification.Name("IOWsProxySettingsChangedNotification")

    public static let defaultConfig = IOCoreConfig(
        saveDeletedMessages: true,
        saveMessagesHistory: true,
        saveForBots: false,
        ghostDontSendOnline: false,
        ghostDontSendTyping: false,
        disableAds: true,
        hideReactionsInPrivateChats: false,
        hideReactionsInChannels: false,
        hideReactionsInGroups: false,
        showExteraBadges: true,
        replaceEditedWithIcon: false,
        saveDisappearingMedia: true,
        disableScreenshotProtection: true,
        showFlameOnSelfDestruct: true,
        hideSideShareButton: false,
        hidePhoneNumber: false,
        downloadSpeedBoost: 0,
        uploadSpeedBoost: false,
        avatarCornerRadiusPercent: -1,
        singleCornerRadius: false,
        showForwardCount: false,
        stickerSizePercent: 100,
        hideKeyboardOnScroll: false,
        hideSendAsButton: false,
        confirmSendingVoice: false,
        confirmSendingRoundVideo: false,
        alwaysSendInHD: false,
        doubleTapSeekSeconds: 15,
        sendWithoutSoundMode: 0,
        wsProxyMode: 0,
        wsProxyCustomDomains: "",
        customChatListTitle: "",
        bypassCopyProtection: false,
        ghostDontReadStories: false,
        alwaysOnline: false,
        disablePerChatWallpapers: false,
        spoofDeviceModel: "",
        spoofSystemVersion: "",
        ghostAskBeforeReadingStories: false,
        roundVideo60Fps: true
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
        hideReactionsInGroups: Bool = false,
        showExteraBadges: Bool = true,
        replaceEditedWithIcon: Bool = false,
        saveDisappearingMedia: Bool = true,
        disableScreenshotProtection: Bool = true,
        showFlameOnSelfDestruct: Bool = true,
        hideSideShareButton: Bool = false,
        hidePhoneNumber: Bool = false,
        downloadSpeedBoost: Int32 = 0,
        uploadSpeedBoost: Bool = false,
        avatarCornerRadiusPercent: Int32 = -1,
        singleCornerRadius: Bool = false,
        showForwardCount: Bool = false,
        stickerSizePercent: Int32 = 100,
        hideKeyboardOnScroll: Bool = false,
        hideSendAsButton: Bool = false,
        confirmSendingVoice: Bool = false,
        confirmSendingRoundVideo: Bool = false,
        alwaysSendInHD: Bool = false,
        doubleTapSeekSeconds: Int32 = 15,
        sendWithoutSoundMode: Int32 = 0,
        wsProxyMode: Int32 = 0,
        wsProxyCustomDomains: String = "",
        customChatListTitle: String = "",
        bypassCopyProtection: Bool = false,
        ghostDontReadStories: Bool = false,
        alwaysOnline: Bool = false,
        disablePerChatWallpapers: Bool = false,
        spoofDeviceModel: String = "",
        spoofSystemVersion: String = "",
        ghostAskBeforeReadingStories: Bool = false,
        roundVideo60Fps: Bool = true
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
        self.showExteraBadges = showExteraBadges
        self.replaceEditedWithIcon = replaceEditedWithIcon
        self.saveDisappearingMedia = saveDisappearingMedia
        self.disableScreenshotProtection = disableScreenshotProtection
        self.showFlameOnSelfDestruct = showFlameOnSelfDestruct
        self.hideSideShareButton = hideSideShareButton
        self.hidePhoneNumber = hidePhoneNumber
        self.downloadSpeedBoost = downloadSpeedBoost
        self.uploadSpeedBoost = uploadSpeedBoost
        self.avatarCornerRadiusPercent = avatarCornerRadiusPercent
        self.singleCornerRadius = singleCornerRadius
        self.showForwardCount = showForwardCount
        self.stickerSizePercent = stickerSizePercent
        self.hideKeyboardOnScroll = hideKeyboardOnScroll
        self.hideSendAsButton = hideSendAsButton
        self.confirmSendingVoice = confirmSendingVoice
        self.confirmSendingRoundVideo = confirmSendingRoundVideo
        self.alwaysSendInHD = alwaysSendInHD
        self.doubleTapSeekSeconds = doubleTapSeekSeconds
        self.sendWithoutSoundMode = sendWithoutSoundMode
        self.wsProxyMode = wsProxyMode
        self.wsProxyCustomDomains = wsProxyCustomDomains
        self.customChatListTitle = customChatListTitle
        self.bypassCopyProtection = bypassCopyProtection
        self.ghostDontReadStories = ghostDontReadStories
        self.alwaysOnline = alwaysOnline
        self.disablePerChatWallpapers = disablePerChatWallpapers
        self.spoofDeviceModel = spoofDeviceModel
        self.spoofSystemVersion = spoofSystemVersion
        self.ghostAskBeforeReadingStories = ghostAskBeforeReadingStories
        self.roundVideo60Fps = roundVideo60Fps
    }

    private static let currentValue = Atomic<IOCoreConfig>(value: .defaultConfig)
    private static let skipReadHistoryValue = Atomic<Bool>(value: false)

    public static var isSkipReadHistory: Bool {
        return self.skipReadHistoryValue.with { $0 }
    }

    public static func setSkipReadHistory(_ value: Bool) {
        let _ = self.skipReadHistoryValue.swap(value)
    }

    public var isGhostModeActive: Bool {
        return self.ghostDontSendOnline || self.ghostDontSendTyping || self.ghostDontReadStories || Self.isSkipReadHistory
    }

    public var effectiveSendWithoutSound: Bool {
        switch self.sendWithoutSoundMode {
        case 1:
            return self.isGhostModeActive
        case 2:
            return true
        default:
            return false
        }
    }

    public static var current: IOCoreConfig {
        return self.currentValue.with { $0 }
    }

    public static func setCurrent(_ config: IOCoreConfig) {
        let previous = self.currentValue.swap(config)
        if previous.spoofDeviceModel != config.spoofDeviceModel {
            if config.spoofDeviceModel.isEmpty {
                UserDefaults.standard.removeObject(forKey: "io.spoofDeviceModel")
            } else {
                UserDefaults.standard.set(config.spoofDeviceModel, forKey: "io.spoofDeviceModel")
            }
        }
        if previous.spoofSystemVersion != config.spoofSystemVersion {
            if config.spoofSystemVersion.isEmpty {
                UserDefaults.standard.removeObject(forKey: "io.spoofSystemVersion")
            } else {
                UserDefaults.standard.set(config.spoofSystemVersion, forKey: "io.spoofSystemVersion")
            }
        }
        UserDefaults.standard.set(config.roundVideo60Fps, forKey: "io.roundVideo60Fps")
        if previous.wsProxyMode != config.wsProxyMode || previous.wsProxyCustomDomains != config.wsProxyCustomDomains {
            NotificationCenter.default.post(name: Self.wsProxySettingsChangedNotification, object: nil)
        }
    }
}

public final class IODeletedMessageAttribute: MessageAttribute, Equatable {
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

    public static func ==(lhs: IODeletedMessageAttribute, rhs: IODeletedMessageAttribute) -> Bool {
        return lhs.deletedTimestamp == rhs.deletedTimestamp
    }
}

public final class IOMessageEditRevision: PostboxCoding, Equatable {
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

    public static func ==(lhs: IOMessageEditRevision, rhs: IOMessageEditRevision) -> Bool {
        return lhs.text == rhs.text && lhs.timestamp == rhs.timestamp && lhs.hasMedia == rhs.hasMedia
    }
}

public final class IOEditHistoryMessageAttribute: MessageAttribute, Equatable {
    public let revisions: [IOMessageEditRevision]
    public let associatedPeerIds: [PeerId] = []
    public let associatedMediaIds: [MediaId] = []

    public init(revisions: [IOMessageEditRevision]) {
        self.revisions = revisions
    }

    public required init(decoder: PostboxDecoder) {
        self.revisions = decoder.decodeObjectArrayWithDecoderForKey("r")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.revisions, forKey: "r")
    }

    public static func ==(lhs: IOEditHistoryMessageAttribute, rhs: IOEditHistoryMessageAttribute) -> Bool {
        return lhs.revisions == rhs.revisions
    }
}

private struct IOStoredMessageId: Codable, Hashable {
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

private struct IODeletedMessageIndex: Codable, Equatable {
    var items: [IOStoredMessageId]
}

private let ioDeletedIndexKey = ValueBoxKey("io.deletedIndex")

private func appendToDeletedIndex(transaction: Transaction, messageIds: [MessageId]) {
    guard !messageIds.isEmpty else {
        return
    }
    var index = transaction.getPreferencesEntry(key: ioDeletedIndexKey)?.get(IODeletedMessageIndex.self) ?? IODeletedMessageIndex(items: [])
    var existing = Set(index.items)
    for id in messageIds {
        let stored = IOStoredMessageId(id)
        if existing.insert(stored).inserted {
            index.items.append(stored)
        }
    }
    if let entry = PreferencesEntry(index) {
        transaction.setPreferencesEntry(key: ioDeletedIndexKey, value: entry)
    }
}

func ioRemoveFromDeletedIndex(transaction: Transaction, messageIds: [MessageId]) {
    guard !messageIds.isEmpty else {
        return
    }
    guard var index = transaction.getPreferencesEntry(key: ioDeletedIndexKey)?.get(IODeletedMessageIndex.self) else {
        return
    }
    let removeSet = Set(messageIds.map(IOStoredMessageId.init))
    index.items.removeAll(where: { removeSet.contains($0) })
    if let entry = PreferencesEntry(index) {
        transaction.setPreferencesEntry(key: ioDeletedIndexKey, value: entry)
    }
}

func ioShouldPreserveDeletedMessage(transaction: Transaction, messageId: MessageId) -> Bool {
    guard IOCoreConfig.current.saveDeletedMessages else {
        return false
    }
    guard let message = transaction.getMessage(messageId) else {
        return false
    }
    if !IOCoreConfig.current.saveForBots {
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
func ioMarkMessagesDeletedOrPurge(
    transaction: Transaction,
    mediaBox: MediaBox,
    ids: [MessageId],
    manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil
) -> [MessageId] {
    var preservedIds: [MessageId] = []
    var purgeIds: [MessageId] = []

    for id in ids {
        if ioShouldPreserveDeletedMessage(transaction: transaction, messageId: id) {
            preservedIds.append(id)
        } else {
            purgeIds.append(id)
        }
    }

    if !preservedIds.isEmpty {
        let now = Int32(Date().timeIntervalSince1970)
        for id in preservedIds {
            transaction.updateMessage(id, update: { currentMessage in
                if currentMessage.attributes.contains(where: { $0 is IODeletedMessageAttribute }) {
                    return .skip
                }
                var attributes = currentMessage.attributes
                attributes.append(IODeletedMessageAttribute(deletedTimestamp: now))
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

func ioMarkMessagesDeletedForEveryoneOrPurge(
    transaction: Transaction,
    mediaBox: MediaBox,
    ids: [MessageId]
) -> [MessageId] {
    var markIds: [MessageId] = []
    var purgeIds: [MessageId] = []

    for id in ids {
        guard let message = transaction.getMessage(id) else {
            purgeIds.append(id)
            continue
        }
        let isLocalOrUnsent = message.flags.contains(.Unsent)
            || message.flags.contains(.Failed)
            || id.namespace == Namespaces.Message.Local
            || id.namespace == Namespaces.Message.ScheduledLocal
            || id.namespace == Namespaces.Message.QuickReplyLocal
            || id.namespace == Namespaces.Message.EphemeralLocal
        if !isLocalOrUnsent
            && !message.attributes.contains(where: { $0 is IODeletedMessageAttribute })
            && ioShouldPreserveDeletedMessage(transaction: transaction, messageId: id)
        {
            markIds.append(id)
        } else {
            purgeIds.append(id)
        }
    }

    if !markIds.isEmpty {
        let _ = ioMarkMessagesDeletedOrPurge(transaction: transaction, mediaBox: mediaBox, ids: markIds)
    }
    if !purgeIds.isEmpty {
        ioRemoveFromDeletedIndex(transaction: transaction, messageIds: purgeIds)
        _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: purgeIds)
    }
    return purgeIds
}

func ioApplyEditHistory(previousMessage: Message, updatedMessage: StoreMessage) -> StoreMessage {
    var attributes = updatedMessage.attributes

    if let deletedAttribute = previousMessage.attributes.first(where: { $0 is IODeletedMessageAttribute }) as? IODeletedMessageAttribute {
        if !attributes.contains(where: { $0 is IODeletedMessageAttribute }) {
            attributes.append(deletedAttribute)
        }
    }

    guard IOCoreConfig.current.saveMessagesHistory else {
        return updatedMessage.withUpdatedAttributes(attributes)
    }

    var revisions = (previousMessage.attributes.first(where: { $0 is IOEditHistoryMessageAttribute }) as? IOEditHistoryMessageAttribute)?.revisions ?? []

    let textChanged = previousMessage.text != updatedMessage.text
    let mediaChanged = previousMessage.media.count != updatedMessage.media.count
    if textChanged || mediaChanged {
        let previousTimestamp = previousMessage.editedTime ?? previousMessage.timestamp
        let previousHasMedia = !previousMessage.media.isEmpty
        if revisions.last?.text != previousMessage.text || revisions.last?.hasMedia != previousHasMedia {
            revisions.append(IOMessageEditRevision(
                text: previousMessage.text,
                timestamp: previousTimestamp,
                hasMedia: previousHasMedia
            ))
        }
    }

    if !revisions.isEmpty {
        attributes.removeAll(where: { $0 is IOEditHistoryMessageAttribute })
        attributes.append(IOEditHistoryMessageAttribute(revisions: revisions))
    }

    return updatedMessage.withUpdatedAttributes(attributes)
}

public func ioLoadSavedDeletedMessages(account: Account, peerId: PeerId? = nil) -> Signal<[Message], NoError> {
    return account.postbox.transaction { transaction -> [Message] in
        guard let index = transaction.getPreferencesEntry(key: ioDeletedIndexKey)?.get(IODeletedMessageIndex.self), !index.items.isEmpty else {
            return []
        }
        var result: [Message] = []
        for item in index.items.reversed() {
            let msgId = item.messageId
            if let peerId, msgId.peerId != peerId {
                continue
            }
            if let message = transaction.getMessage(msgId), message.attributes.contains(where: { $0 is IODeletedMessageAttribute }) {
                result.append(message)
            }
        }
        return result
    }
}

public func ioPurgeSavedDeletedMessage(account: Account, messageId: MessageId) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        ioRemoveFromDeletedIndex(transaction: transaction, messageIds: [messageId])
        _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: [messageId])
    }
}

public func ioClearAllSavedDeletedMessages(account: Account) -> Signal<Int, NoError> {
    return account.postbox.transaction { transaction -> Int in
        guard let index = transaction.getPreferencesEntry(key: ioDeletedIndexKey)?.get(IODeletedMessageIndex.self), !index.items.isEmpty else {
            return 0
        }
        let ids = index.items.map(\.messageId)
        let count = ids.count
        _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: ids)
        if let entry = PreferencesEntry(IODeletedMessageIndex(items: [])) {
            transaction.setPreferencesEntry(key: ioDeletedIndexKey, value: entry)
        }
        return count
    }
}

public func ioMarkPeerRead(account: Account, peerId: PeerId) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        if let index = transaction.getTopPeerMessageIndex(peerId: peerId) {
            _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: account.stateManager, index: index)
        }
    }
}
