import Foundation
import TelegramCore
import SwiftSignalKit

public struct IOSettings: Codable, Equatable {
    public enum PeerIdDisplayMode: Int32, Codable, Equatable, CaseIterable {
        case hidden = 0
        case telegramApi = 1
        case botApi = 2
    }

    // Appearance & UI tweaks
    public var hideStories: Bool
    public var removeMessageTail: Bool
    public var showMessageSeconds: Bool
    public var disableAds: Bool
    public var hideAllChatsFolder: Bool
    public var hidePhoneNumber: Bool
    public var peerIdDisplayMode: PeerIdDisplayMode
    public var disableNumberRounding: Bool
    public var hideReactionsInPrivateChats: Bool
    public var hideReactionsInChannels: Bool
    public var hideReactionsInGroups: Bool
    public var showExteraBadges: Bool
    public var replaceEditedWithIcon: Bool
    public var hideSideShareButton: Bool

    // Chats & confirmations
    public var disableOpenLinkWarning: Bool
    public var confirmSendingStickers: Bool
    public var confirmSendingGif: Bool
    public var filterZalgo: Bool
    public var disableGreetingSticker: Bool

    // Anti-Recall & Edit History
    public var saveDeletedMessages: Bool
    public var saveMessagesHistory: Bool
    public var saveForBots: Bool
    public var semiTransparentDeletedMessages: Bool
    public var deletedMark: String
    public var showEditHistoryInMenu: Bool
    public var showMessageDetailsInMenu: Bool
    public var showRepeatMessageInMenu: Bool
    public var saveDisappearingMedia: Bool
    public var disableScreenshotProtection: Bool
    public var showFlameOnSelfDestruct: Bool

    // Filters & anti-spam
    public var filtersEnabled: Bool
    public var filtersEnabledInChats: Bool
    public var hideFromBlocked: Bool
    public var blockedKeywords: [String]
    public var shadowBannedPeerIds: [Int64]

    // Local & Ghost Mode
    public var localPremium: Bool
    public var ghostDontSendOnline: Bool
    public var ghostDontSendTyping: Bool
    public var ghostSendWithoutSound: Bool
    public var ghostMarkReadAfterAction: Bool

    public static var defaultSettings: IOSettings {
        return IOSettings(
            hideStories: false,
            removeMessageTail: false,
            showMessageSeconds: false,
            disableAds: true,
            hideAllChatsFolder: false,
            hidePhoneNumber: false,
            peerIdDisplayMode: .telegramApi,
            disableNumberRounding: false,
            hideReactionsInPrivateChats: false,
            hideReactionsInChannels: false,
            hideReactionsInGroups: false,
            showExteraBadges: true,
            replaceEditedWithIcon: false,
            hideSideShareButton: false,
            disableOpenLinkWarning: false,
            confirmSendingStickers: false,
            confirmSendingGif: false,
            filterZalgo: true,
            disableGreetingSticker: false,
            saveDeletedMessages: true,
            saveMessagesHistory: true,
            saveForBots: false,
            semiTransparentDeletedMessages: true,
            deletedMark: "🗑 ",
            showEditHistoryInMenu: true,
            showMessageDetailsInMenu: true,
            showRepeatMessageInMenu: true,
            saveDisappearingMedia: true,
            disableScreenshotProtection: true,
            showFlameOnSelfDestruct: true,
            filtersEnabled: true,
            filtersEnabledInChats: false,
            hideFromBlocked: false,
            blockedKeywords: [],
            shadowBannedPeerIds: [],
            localPremium: false,
            ghostDontSendOnline: false,
            ghostDontSendTyping: false,
            ghostSendWithoutSound: false,
            ghostMarkReadAfterAction: false
        )
    }

    public init(
        hideStories: Bool,
        removeMessageTail: Bool,
        showMessageSeconds: Bool,
        disableAds: Bool,
        hideAllChatsFolder: Bool,
        hidePhoneNumber: Bool,
        peerIdDisplayMode: PeerIdDisplayMode,
        disableNumberRounding: Bool,
        hideReactionsInPrivateChats: Bool,
        hideReactionsInChannels: Bool,
        hideReactionsInGroups: Bool,
        showExteraBadges: Bool = true,
        replaceEditedWithIcon: Bool = false,
        hideSideShareButton: Bool = false,
        disableOpenLinkWarning: Bool,
        confirmSendingStickers: Bool,
        confirmSendingGif: Bool,
        filterZalgo: Bool,
        disableGreetingSticker: Bool,
        saveDeletedMessages: Bool,
        saveMessagesHistory: Bool,
        saveForBots: Bool,
        semiTransparentDeletedMessages: Bool,
        deletedMark: String,
        showEditHistoryInMenu: Bool,
        showMessageDetailsInMenu: Bool,
        showRepeatMessageInMenu: Bool,
        saveDisappearingMedia: Bool = true,
        disableScreenshotProtection: Bool = true,
        showFlameOnSelfDestruct: Bool = true,
        filtersEnabled: Bool,
        filtersEnabledInChats: Bool,
        hideFromBlocked: Bool,
        blockedKeywords: [String],
        shadowBannedPeerIds: [Int64],
        localPremium: Bool,
        ghostDontSendOnline: Bool,
        ghostDontSendTyping: Bool,
        ghostSendWithoutSound: Bool,
        ghostMarkReadAfterAction: Bool
    ) {
        self.hideStories = hideStories
        self.removeMessageTail = removeMessageTail
        self.showMessageSeconds = showMessageSeconds
        self.disableAds = disableAds
        self.hideAllChatsFolder = hideAllChatsFolder
        self.hidePhoneNumber = hidePhoneNumber
        self.peerIdDisplayMode = peerIdDisplayMode
        self.disableNumberRounding = disableNumberRounding
        self.hideReactionsInPrivateChats = hideReactionsInPrivateChats
        self.hideReactionsInChannels = hideReactionsInChannels
        self.hideReactionsInGroups = hideReactionsInGroups
        self.showExteraBadges = showExteraBadges
        self.replaceEditedWithIcon = replaceEditedWithIcon
        self.hideSideShareButton = hideSideShareButton
        self.disableOpenLinkWarning = disableOpenLinkWarning
        self.confirmSendingStickers = confirmSendingStickers
        self.confirmSendingGif = confirmSendingGif
        self.filterZalgo = filterZalgo
        self.disableGreetingSticker = disableGreetingSticker
        self.saveDeletedMessages = saveDeletedMessages
        self.saveMessagesHistory = saveMessagesHistory
        self.saveForBots = saveForBots
        self.semiTransparentDeletedMessages = semiTransparentDeletedMessages
        self.deletedMark = deletedMark
        self.showEditHistoryInMenu = showEditHistoryInMenu
        self.showMessageDetailsInMenu = showMessageDetailsInMenu
        self.showRepeatMessageInMenu = showRepeatMessageInMenu
        self.saveDisappearingMedia = saveDisappearingMedia
        self.disableScreenshotProtection = disableScreenshotProtection
        self.showFlameOnSelfDestruct = showFlameOnSelfDestruct
        self.filtersEnabled = filtersEnabled
        self.filtersEnabledInChats = filtersEnabledInChats
        self.hideFromBlocked = hideFromBlocked
        self.blockedKeywords = blockedKeywords
        self.shadowBannedPeerIds = shadowBannedPeerIds
        self.localPremium = localPremium
        self.ghostDontSendOnline = ghostDontSendOnline
        self.ghostDontSendTyping = ghostDontSendTyping
        self.ghostSendWithoutSound = ghostSendWithoutSound
        self.ghostMarkReadAfterAction = ghostMarkReadAfterAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.hideStories = (try container.decodeIfPresent(Int32.self, forKey: "hideStories") ?? 0) != 0
        self.removeMessageTail = (try container.decodeIfPresent(Int32.self, forKey: "removeMessageTail") ?? 0) != 0
        self.showMessageSeconds = (try container.decodeIfPresent(Int32.self, forKey: "showMessageSeconds") ?? 0) != 0
        self.disableAds = (try container.decodeIfPresent(Int32.self, forKey: "disableAds") ?? 1) != 0
        self.hideAllChatsFolder = (try container.decodeIfPresent(Int32.self, forKey: "hideAllChatsFolder") ?? 0) != 0
        self.hidePhoneNumber = (try container.decodeIfPresent(Int32.self, forKey: "hidePhoneNumber") ?? 0) != 0
        let peerIdModeRaw = try container.decodeIfPresent(Int32.self, forKey: "peerIdDisplayMode") ?? PeerIdDisplayMode.telegramApi.rawValue
        self.peerIdDisplayMode = PeerIdDisplayMode(rawValue: peerIdModeRaw) ?? .telegramApi
        self.disableNumberRounding = (try container.decodeIfPresent(Int32.self, forKey: "disableNumberRounding") ?? 0) != 0
        self.hideReactionsInPrivateChats = (try container.decodeIfPresent(Int32.self, forKey: "hideReactionsInPrivateChats") ?? 0) != 0
        self.hideReactionsInChannels = (try container.decodeIfPresent(Int32.self, forKey: "hideReactionsInChannels") ?? 0) != 0
        self.hideReactionsInGroups = (try container.decodeIfPresent(Int32.self, forKey: "hideReactionsInGroups") ?? 0) != 0
        self.showExteraBadges = (try container.decodeIfPresent(Int32.self, forKey: "showExteraBadges") ?? 1) != 0
        self.replaceEditedWithIcon = (try container.decodeIfPresent(Int32.self, forKey: "replaceEditedWithIcon") ?? 0) != 0
        self.hideSideShareButton = (try container.decodeIfPresent(Int32.self, forKey: "hideSideShareButton") ?? 0) != 0

        self.disableOpenLinkWarning = (try container.decodeIfPresent(Int32.self, forKey: "disableOpenLinkWarning") ?? 0) != 0
        self.confirmSendingStickers = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingStickers") ?? 0) != 0
        self.confirmSendingGif = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingGif") ?? 0) != 0
        self.filterZalgo = (try container.decodeIfPresent(Int32.self, forKey: "filterZalgo") ?? 1) != 0
        self.disableGreetingSticker = (try container.decodeIfPresent(Int32.self, forKey: "disableGreetingSticker") ?? 0) != 0

        self.saveDeletedMessages = (try container.decodeIfPresent(Int32.self, forKey: "saveDeletedMessages") ?? 1) != 0
        self.saveMessagesHistory = (try container.decodeIfPresent(Int32.self, forKey: "saveMessagesHistory") ?? 1) != 0
        self.saveForBots = (try container.decodeIfPresent(Int32.self, forKey: "saveForBots") ?? 0) != 0
        self.semiTransparentDeletedMessages = (try container.decodeIfPresent(Int32.self, forKey: "semiTransparentDeletedMessages") ?? 1) != 0
        self.deletedMark = try container.decodeIfPresent(String.self, forKey: "deletedMark") ?? "🗑 "
        self.showEditHistoryInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showEditHistoryInMenu") ?? 1) != 0
        self.showMessageDetailsInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showMessageDetailsInMenu") ?? 1) != 0
        self.showRepeatMessageInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showRepeatMessageInMenu") ?? 1) != 0
        self.saveDisappearingMedia = (try container.decodeIfPresent(Int32.self, forKey: "saveDisappearingMedia") ?? 1) != 0
        self.disableScreenshotProtection = (try container.decodeIfPresent(Int32.self, forKey: "disableScreenshotProtection") ?? 1) != 0
        self.showFlameOnSelfDestruct = (try container.decodeIfPresent(Int32.self, forKey: "showFlameOnSelfDestruct") ?? 1) != 0

        self.filtersEnabled = (try container.decodeIfPresent(Int32.self, forKey: "filtersEnabled") ?? 1) != 0
        self.filtersEnabledInChats = (try container.decodeIfPresent(Int32.self, forKey: "filtersEnabledInChats") ?? 0) != 0
        self.hideFromBlocked = (try container.decodeIfPresent(Int32.self, forKey: "hideFromBlocked") ?? 0) != 0
        self.blockedKeywords = try container.decodeIfPresent([String].self, forKey: "blockedKeywords") ?? []
        self.shadowBannedPeerIds = try container.decodeIfPresent([Int64].self, forKey: "shadowBannedPeerIds") ?? []

        self.localPremium = (try container.decodeIfPresent(Int32.self, forKey: "localPremium") ?? 0) != 0
        self.ghostDontSendOnline = (try container.decodeIfPresent(Int32.self, forKey: "ghostDontSendOnline") ?? 0) != 0
        self.ghostDontSendTyping = (try container.decodeIfPresent(Int32.self, forKey: "ghostDontSendTyping") ?? 0) != 0
        self.ghostSendWithoutSound = (try container.decodeIfPresent(Int32.self, forKey: "ghostSendWithoutSound") ?? 0) != 0
        self.ghostMarkReadAfterAction = (try container.decodeIfPresent(Int32.self, forKey: "ghostMarkReadAfterAction") ?? 0) != 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.hideStories ? 1 : 0) as Int32, forKey: "hideStories")
        try container.encode((self.removeMessageTail ? 1 : 0) as Int32, forKey: "removeMessageTail")
        try container.encode((self.showMessageSeconds ? 1 : 0) as Int32, forKey: "showMessageSeconds")
        try container.encode((self.disableAds ? 1 : 0) as Int32, forKey: "disableAds")
        try container.encode((self.hideAllChatsFolder ? 1 : 0) as Int32, forKey: "hideAllChatsFolder")
        try container.encode((self.hidePhoneNumber ? 1 : 0) as Int32, forKey: "hidePhoneNumber")
        try container.encode(self.peerIdDisplayMode.rawValue, forKey: "peerIdDisplayMode")
        try container.encode((self.disableNumberRounding ? 1 : 0) as Int32, forKey: "disableNumberRounding")
        try container.encode((self.hideReactionsInPrivateChats ? 1 : 0) as Int32, forKey: "hideReactionsInPrivateChats")
        try container.encode((self.hideReactionsInChannels ? 1 : 0) as Int32, forKey: "hideReactionsInChannels")
        try container.encode((self.hideReactionsInGroups ? 1 : 0) as Int32, forKey: "hideReactionsInGroups")
        try container.encode((self.showExteraBadges ? 1 : 0) as Int32, forKey: "showExteraBadges")
        try container.encode((self.replaceEditedWithIcon ? 1 : 0) as Int32, forKey: "replaceEditedWithIcon")
        try container.encode((self.hideSideShareButton ? 1 : 0) as Int32, forKey: "hideSideShareButton")

        try container.encode((self.disableOpenLinkWarning ? 1 : 0) as Int32, forKey: "disableOpenLinkWarning")
        try container.encode((self.confirmSendingStickers ? 1 : 0) as Int32, forKey: "confirmSendingStickers")
        try container.encode((self.confirmSendingGif ? 1 : 0) as Int32, forKey: "confirmSendingGif")
        try container.encode((self.filterZalgo ? 1 : 0) as Int32, forKey: "filterZalgo")
        try container.encode((self.disableGreetingSticker ? 1 : 0) as Int32, forKey: "disableGreetingSticker")

        try container.encode((self.saveDeletedMessages ? 1 : 0) as Int32, forKey: "saveDeletedMessages")
        try container.encode((self.saveMessagesHistory ? 1 : 0) as Int32, forKey: "saveMessagesHistory")
        try container.encode((self.saveForBots ? 1 : 0) as Int32, forKey: "saveForBots")
        try container.encode((self.semiTransparentDeletedMessages ? 1 : 0) as Int32, forKey: "semiTransparentDeletedMessages")
        try container.encode(self.deletedMark, forKey: "deletedMark")
        try container.encode((self.showEditHistoryInMenu ? 1 : 0) as Int32, forKey: "showEditHistoryInMenu")
        try container.encode((self.showMessageDetailsInMenu ? 1 : 0) as Int32, forKey: "showMessageDetailsInMenu")
        try container.encode((self.showRepeatMessageInMenu ? 1 : 0) as Int32, forKey: "showRepeatMessageInMenu")
        try container.encode((self.saveDisappearingMedia ? 1 : 0) as Int32, forKey: "saveDisappearingMedia")
        try container.encode((self.disableScreenshotProtection ? 1 : 0) as Int32, forKey: "disableScreenshotProtection")
        try container.encode((self.showFlameOnSelfDestruct ? 1 : 0) as Int32, forKey: "showFlameOnSelfDestruct")

        try container.encode((self.filtersEnabled ? 1 : 0) as Int32, forKey: "filtersEnabled")
        try container.encode((self.filtersEnabledInChats ? 1 : 0) as Int32, forKey: "filtersEnabledInChats")
        try container.encode((self.hideFromBlocked ? 1 : 0) as Int32, forKey: "hideFromBlocked")
        try container.encode(self.blockedKeywords, forKey: "blockedKeywords")
        try container.encode(self.shadowBannedPeerIds, forKey: "shadowBannedPeerIds")

        try container.encode((self.localPremium ? 1 : 0) as Int32, forKey: "localPremium")
        try container.encode((self.ghostDontSendOnline ? 1 : 0) as Int32, forKey: "ghostDontSendOnline")
        try container.encode((self.ghostDontSendTyping ? 1 : 0) as Int32, forKey: "ghostDontSendTyping")
        try container.encode((self.ghostSendWithoutSound ? 1 : 0) as Int32, forKey: "ghostSendWithoutSound")
        try container.encode((self.ghostMarkReadAfterAction ? 1 : 0) as Int32, forKey: "ghostMarkReadAfterAction")
    }

    private static let currentValue = Atomic<IOSettings>(value: .defaultSettings)

    public static var current: IOSettings {
        return self.currentValue.with { $0 }
    }

    public static func setCurrent(_ settings: IOSettings) {
        let _ = self.currentValue.swap(settings)
        IOCoreConfig.setCurrent(IOCoreConfig(
            saveDeletedMessages: settings.saveDeletedMessages,
            saveMessagesHistory: settings.saveMessagesHistory,
            saveForBots: settings.saveForBots,
            ghostDontSendOnline: settings.ghostDontSendOnline,
            ghostDontSendTyping: settings.ghostDontSendTyping,
            disableAds: settings.disableAds,
            hideReactionsInPrivateChats: settings.hideReactionsInPrivateChats,
            hideReactionsInChannels: settings.hideReactionsInChannels,
            hideReactionsInGroups: settings.hideReactionsInGroups,
            showExteraBadges: settings.showExteraBadges,
            replaceEditedWithIcon: settings.replaceEditedWithIcon,
            saveDisappearingMedia: settings.saveDisappearingMedia,
            disableScreenshotProtection: settings.disableScreenshotProtection,
            showFlameOnSelfDestruct: settings.showFlameOnSelfDestruct,
            hideSideShareButton: settings.hideSideShareButton
        ))
    }

    public func exportConfigJSONData() -> Data? {
        let settingsDict: [String: Any] = [
            "hideStories": self.hideStories,
            "removeMessageTail": self.removeMessageTail,
            "showMessageSeconds": self.showMessageSeconds,
            "disableAds": self.disableAds,
            "hideAllChatsFolder": self.hideAllChatsFolder,
            "hidePhoneNumber": self.hidePhoneNumber,
            "peerIdDisplayMode": self.peerIdDisplayMode.rawValue,
            "disableNumberRounding": self.disableNumberRounding,
            "hideReactionsInPrivateChats": self.hideReactionsInPrivateChats,
            "hideReactionsInChannels": self.hideReactionsInChannels,
            "hideReactionsInGroups": self.hideReactionsInGroups,
            "showExteraBadges": self.showExteraBadges,
            "replaceEditedWithIcon": self.replaceEditedWithIcon,
            "hideSideShareButton": self.hideSideShareButton,
            "disableOpenLinkWarning": self.disableOpenLinkWarning,
            "confirmSendingStickers": self.confirmSendingStickers,
            "confirmSendingGif": self.confirmSendingGif,
            "filterZalgo": self.filterZalgo,
            "disableGreetingSticker": self.disableGreetingSticker,
            "saveDeletedMessages": self.saveDeletedMessages,
            "saveMessagesHistory": self.saveMessagesHistory,
            "saveForBots": self.saveForBots,
            "semiTransparentDeletedMessages": self.semiTransparentDeletedMessages,
            "deletedMark": self.deletedMark,
            "showEditHistoryInMenu": self.showEditHistoryInMenu,
            "showMessageDetailsInMenu": self.showMessageDetailsInMenu,
            "showRepeatMessageInMenu": self.showRepeatMessageInMenu,
            "saveDisappearingMedia": self.saveDisappearingMedia,
            "disableScreenshotProtection": self.disableScreenshotProtection,
            "showFlameOnSelfDestruct": self.showFlameOnSelfDestruct,
            "filtersEnabled": self.filtersEnabled,
            "filtersEnabledInChats": self.filtersEnabledInChats,
            "hideFromBlocked": self.hideFromBlocked,
            "blockedKeywords": self.blockedKeywords,
            "shadowBannedPeerIds": self.shadowBannedPeerIds,
            "localPremium": self.localPremium,
            "ghostDontSendOnline": self.ghostDontSendOnline,
            "ghostDontSendTyping": self.ghostDontSendTyping,
            "ghostSendWithoutSound": self.ghostSendWithoutSound,
            "ghostMarkReadAfterAction": self.ghostMarkReadAfterAction
        ]
        let root: [String: Any] = [
            "client": "iOGram",
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "settings": settingsDict
        ]
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func importConfig(from data: Data, current: IOSettings) -> (settings: IOSettings, updatedKeys: Int)? {
        guard let rawObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let rootDict = rawObject as? [String: Any] else {
            return nil
        }

        let sourceDict: [String: Any]
        if let settings = rootDict["settings"] as? [String: Any] {
            sourceDict = settings
        } else if let extera = rootDict["exteraconfig"] as? [String: Any] {
            sourceDict = extera
        } else {
            sourceDict = rootDict
        }

        func boolValue(_ keys: [String]) -> Bool? {
            for key in keys {
                if let boolVal = sourceDict[key] as? Bool {
                    return boolVal
                }
                if let numVal = sourceDict[key] as? NSNumber {
                    return numVal.intValue != 0
                }
            }
            return nil
        }

        func intValue(_ keys: [String]) -> Int32? {
            for key in keys {
                if let numVal = sourceDict[key] as? NSNumber {
                    return numVal.int32Value
                }
            }
            return nil
        }

        var updated = current
        var count = 0

        if let v = boolValue(["hideStories"]) { updated.hideStories = v; count += 1 }
        if let v = boolValue(["removeMessageTail"]) { updated.removeMessageTail = v; count += 1 }
        if let v = boolValue(["showMessageSeconds", "formatTimeWithSeconds"]) { updated.showMessageSeconds = v; count += 1 }
        if let v = boolValue(["disableAds"]) { updated.disableAds = v; count += 1 }
        if let v = boolValue(["hideAllChatsFolder", "hideAllChats"]) { updated.hideAllChatsFolder = v; count += 1 }
        if let v = boolValue(["hidePhoneNumber"]) { updated.hidePhoneNumber = v; count += 1 }
        if let v = intValue(["peerIdDisplayMode", "showIdAndDc"]), let mode = PeerIdDisplayMode(rawValue: v) {
            updated.peerIdDisplayMode = mode
            count += 1
        }
        if let v = boolValue(["disableNumberRounding"]) { updated.disableNumberRounding = v; count += 1 }
        if let v = boolValue(["hideReactionsInPrivateChats"]) { updated.hideReactionsInPrivateChats = v; count += 1 }
        if let v = boolValue(["hideReactionsInChannels"]) { updated.hideReactionsInChannels = v; count += 1 }
        if let v = boolValue(["hideReactionsInGroups"]) { updated.hideReactionsInGroups = v; count += 1 }
        if let v = boolValue(["showExteraBadges"]) { updated.showExteraBadges = v; count += 1 }
        if let v = boolValue(["replaceEditedWithIcon"]) { updated.replaceEditedWithIcon = v; count += 1 }
        if let v = boolValue(["hideSideShareButton", "hideFastShare"]) { updated.hideSideShareButton = v; count += 1 }
        if let v = boolValue(["disableOpenLinkWarning"]) { updated.disableOpenLinkWarning = v; count += 1 }
        if let v = boolValue(["confirmSendingStickers"]) { updated.confirmSendingStickers = v; count += 1 }
        if let v = boolValue(["confirmSendingGif"]) { updated.confirmSendingGif = v; count += 1 }
        if let v = boolValue(["filterZalgo"]) { updated.filterZalgo = v; count += 1 }
        if let v = boolValue(["disableGreetingSticker"]) { updated.disableGreetingSticker = v; count += 1 }
        if let v = boolValue(["saveDeletedMessages"]) { updated.saveDeletedMessages = v; count += 1 }
        if let v = boolValue(["saveMessagesHistory"]) { updated.saveMessagesHistory = v; count += 1 }
        if let v = boolValue(["saveForBots"]) { updated.saveForBots = v; count += 1 }
        if let v = boolValue(["semiTransparentDeletedMessages"]) { updated.semiTransparentDeletedMessages = v; count += 1 }
        if let v = sourceDict["deletedMark"] as? String { updated.deletedMark = v; count += 1 }
        if let v = boolValue(["showEditHistoryInMenu", "showHistoryButton"]) { updated.showEditHistoryInMenu = v; count += 1 }
        if let v = boolValue(["showMessageDetailsInMenu", "showDetailsButton"]) { updated.showMessageDetailsInMenu = v; count += 1 }
        if let v = boolValue(["showRepeatMessageInMenu", "showRepeatMessageButton"]) { updated.showRepeatMessageInMenu = v; count += 1 }
        if let v = boolValue(["saveDisappearingMedia"]) { updated.saveDisappearingMedia = v; count += 1 }
        if let v = boolValue(["disableScreenshotProtection"]) { updated.disableScreenshotProtection = v; count += 1 }
        if let v = boolValue(["showFlameOnSelfDestruct"]) { updated.showFlameOnSelfDestruct = v; count += 1 }
        if let v = boolValue(["filtersEnabled"]) { updated.filtersEnabled = v; count += 1 }
        if let v = boolValue(["filtersEnabledInChats"]) { updated.filtersEnabledInChats = v; count += 1 }
        if let v = boolValue(["hideFromBlocked"]) { updated.hideFromBlocked = v; count += 1 }
        if let v = sourceDict["blockedKeywords"] as? [String] { updated.blockedKeywords = v; count += 1 }
        if let rawIds = sourceDict["shadowBannedPeerIds"] as? [NSNumber] {
            updated.shadowBannedPeerIds = rawIds.map(\.int64Value)
            count += 1
        }
        if let v = boolValue(["localPremium"]) { updated.localPremium = v; count += 1 }
        if let v = boolValue(["ghostDontSendOnline"]) { updated.ghostDontSendOnline = v; count += 1 }
        if let v = boolValue(["ghostDontSendTyping"]) { updated.ghostDontSendTyping = v; count += 1 }
        if let v = boolValue(["ghostSendWithoutSound"]) { updated.ghostSendWithoutSound = v; count += 1 }
        if let v = boolValue(["ghostMarkReadAfterAction"]) { updated.ghostMarkReadAfterAction = v; count += 1 }

        guard count > 0 else {
            return nil
        }
        return (updated, count)
    }
}

public enum IOBlockedPeers {
    private static let blockedIdsValue = Atomic<Set<Int64>>(value: Set())

    public static var ids: Set<Int64> {
        return self.blockedIdsValue.with { $0 }
    }

    public static func setIds(_ ids: Set<Int64>) {
        let _ = self.blockedIdsValue.swap(ids)
    }
}

public func updateIOSettingsInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (IOSettings) -> IOSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.ioSettings, { entry in
            let currentSettings: IOSettings
            if let entry = entry?.get(IOSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = IOSettings.defaultSettings
            }
            let updated = f(currentSettings)
            IOSettings.setCurrent(updated)
            return SharedPreferencesEntry(updated)
        })
    }
}

public enum IOUtils {
    private static let maxConsecutiveCombiningMarks = 2

    /// Replaces excessive combining Unicode marks with U+2060 (1 UTF-16 unit) so UTF-16 entity offsets stay intact.
    public static func stripZalgo(_ text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        var didModify = false
        var resultScalars = String.UnicodeScalarView()
        resultScalars.reserveCapacity(text.unicodeScalars.count)

        var combiningRun = 0
        for scalar in text.unicodeScalars {
            let category = scalar.properties.generalCategory
            let isCombining = category == .nonspacingMark || category == .enclosingMark || category == .spacingMark
            if isCombining {
                combiningRun += 1
                if combiningRun > self.maxConsecutiveCombiningMarks {
                    didModify = true
                    for _ in 0 ..< scalar.utf16.count {
                        resultScalars.append(Unicode.Scalar(0x2060)!)
                    }
                    continue
                }
            } else {
                combiningRun = 0
            }
            resultScalars.append(scalar)
        }

        return didModify ? String(resultScalars) : text
    }

    public static func matchesFilter(text: String, patterns: [String]) -> Bool {
        guard !text.isEmpty, !patterns.isEmpty else {
            return false
        }
        let nsRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        for rawPattern in patterns {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else {
                continue
            }
            if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
                let inner = String(pattern.dropFirst().dropLast())
                if let regex = try? NSRegularExpression(pattern: inner, options: [.caseInsensitive]) {
                    if regex.firstMatch(in: text, options: [], range: nsRange) != nil {
                        return true
                    }
                }
            } else if text.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    public static func formattedPeerId(_ peerId: EnginePeer.Id, mode: IOSettings.PeerIdDisplayMode) -> String? {
        let rawId = peerId.id._internalGetInt64Value()
        switch mode {
        case .hidden:
            return nil
        case .telegramApi:
            return "\(rawId)"
        case .botApi:
            switch peerId.namespace {
            case Namespaces.Peer.CloudChannel:
                return "-100\(rawId)"
            case Namespaces.Peer.CloudGroup:
                return "-\(rawId)"
            default:
                return "\(rawId)"
            }
        }
    }
}
