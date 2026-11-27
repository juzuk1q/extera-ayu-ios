import Foundation
import TelegramCore
import SwiftSignalKit

public struct IOTextReplacementRule: Codable, Equatable {
    public var find: String
    public var replace: String
    public var caseSensitive: Bool

    public init(find: String, replace: String, caseSensitive: Bool = false) {
        self.find = find
        self.replace = replace
        self.caseSensitive = caseSensitive
    }
}

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
    public var downloadSpeedBoost: Int32
    public var uploadSpeedBoost: Bool
    public var avatarCornerRadiusPercent: Int32
    public var singleCornerRadius: Bool
    public var showForwardCount: Bool

    // Chats & confirmations
    public var disableOpenLinkWarning: Bool
    public var confirmSendingStickers: Bool
    public var confirmSendingGif: Bool
    public var filterZalgo: Bool
    public var disableGreetingSticker: Bool
    public var stickerSizePercent: Int32
    public var hideKeyboardOnScroll: Bool
    public var hideSendAsButton: Bool
    public var confirmSendingVoice: Bool
    public var confirmSendingRoundVideo: Bool
    public var alwaysSendInHD: Bool
    public var doubleTapSeekSeconds: Int32

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
    public var textReplacements: [IOTextReplacementRule]
    public var ghostAskBeforeReadingStories: Bool
    public var roundVideo60Fps: Bool
    public var askRoundVideoCameraBeforeRecording: Bool
    public var roundVideoMaxZoomMode: Int32
    public var showContactsTab: Bool
    public var stickerShape: Int32
    public var showTranslateInMenu: Bool
    public var customTabBarItem: Int32
    public var showReplyInMenu: Bool
    public var showCopyInMenu: Bool
    public var showForwardInMenu: Bool
    public var showPinInMenu: Bool
    public var showDeleteInMenu: Bool
    public var doubleTapIncomingAction: Int32
    public var doubleTapOutgoingAction: Int32
    public var swipeAction: Int32

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
            downloadSpeedBoost: 0,
            uploadSpeedBoost: false,
            avatarCornerRadiusPercent: -1,
            singleCornerRadius: false,
            showForwardCount: false,
            disableOpenLinkWarning: false,
            confirmSendingStickers: false,
            confirmSendingGif: false,
            filterZalgo: true,
            disableGreetingSticker: false,
            stickerSizePercent: 100,
            hideKeyboardOnScroll: false,
            hideSendAsButton: false,
            confirmSendingVoice: false,
            confirmSendingRoundVideo: false,
            alwaysSendInHD: true,
            doubleTapSeekSeconds: 15,
            saveDeletedMessages: true,
            saveMessagesHistory: true,
            saveForBots: false,
            semiTransparentDeletedMessages: true,
            deletedMark: "deleted · ",
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
            ghostMarkReadAfterAction: false,
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
            textReplacements: [],
            ghostAskBeforeReadingStories: true,
            roundVideo60Fps: true,
            askRoundVideoCameraBeforeRecording: false,
            roundVideoMaxZoomMode: 1,
            showContactsTab: false,
            stickerShape: 0,
            showTranslateInMenu: true,
            customTabBarItem: 0,
            showReplyInMenu: true,
            showCopyInMenu: true,
            showForwardInMenu: true,
            showPinInMenu: true,
            showDeleteInMenu: true,
            doubleTapIncomingAction: 0,
            doubleTapOutgoingAction: 0,
            swipeAction: 0
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
        downloadSpeedBoost: Int32 = 0,
        uploadSpeedBoost: Bool = false,
        avatarCornerRadiusPercent: Int32 = -1,
        singleCornerRadius: Bool = false,
        showForwardCount: Bool = false,
        disableOpenLinkWarning: Bool,
        confirmSendingStickers: Bool,
        confirmSendingGif: Bool,
        filterZalgo: Bool,
        disableGreetingSticker: Bool,
        stickerSizePercent: Int32 = 100,
        hideKeyboardOnScroll: Bool = false,
        hideSendAsButton: Bool = false,
        confirmSendingVoice: Bool = false,
        confirmSendingRoundVideo: Bool = false,
        alwaysSendInHD: Bool = true,
        doubleTapSeekSeconds: Int32 = 15,
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
        ghostMarkReadAfterAction: Bool,
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
        textReplacements: [IOTextReplacementRule] = [],
        ghostAskBeforeReadingStories: Bool = true,
        roundVideo60Fps: Bool = true,
        askRoundVideoCameraBeforeRecording: Bool = false,
        roundVideoMaxZoomMode: Int32 = 1,
        showContactsTab: Bool = false,
        stickerShape: Int32 = 0,
        showTranslateInMenu: Bool = true,
        customTabBarItem: Int32 = 0,
        showReplyInMenu: Bool = true,
        showCopyInMenu: Bool = true,
        showForwardInMenu: Bool = true,
        showPinInMenu: Bool = true,
        showDeleteInMenu: Bool = true,
        doubleTapIncomingAction: Int32 = 0,
        doubleTapOutgoingAction: Int32 = 0,
        swipeAction: Int32 = 0
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
        self.downloadSpeedBoost = downloadSpeedBoost
        self.uploadSpeedBoost = uploadSpeedBoost
        self.avatarCornerRadiusPercent = avatarCornerRadiusPercent
        self.singleCornerRadius = singleCornerRadius
        self.showForwardCount = showForwardCount
        self.disableOpenLinkWarning = disableOpenLinkWarning
        self.confirmSendingStickers = confirmSendingStickers
        self.confirmSendingGif = confirmSendingGif
        self.filterZalgo = filterZalgo
        self.disableGreetingSticker = disableGreetingSticker
        self.stickerSizePercent = stickerSizePercent
        self.hideKeyboardOnScroll = hideKeyboardOnScroll
        self.hideSendAsButton = hideSendAsButton
        self.confirmSendingVoice = confirmSendingVoice
        self.confirmSendingRoundVideo = confirmSendingRoundVideo
        self.alwaysSendInHD = alwaysSendInHD
        self.doubleTapSeekSeconds = doubleTapSeekSeconds
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
        self.textReplacements = textReplacements
        self.ghostAskBeforeReadingStories = ghostAskBeforeReadingStories
        self.roundVideo60Fps = roundVideo60Fps
        self.askRoundVideoCameraBeforeRecording = askRoundVideoCameraBeforeRecording
        self.roundVideoMaxZoomMode = roundVideoMaxZoomMode
        self.showContactsTab = showContactsTab
        self.stickerShape = stickerShape
        self.showTranslateInMenu = showTranslateInMenu
        self.customTabBarItem = customTabBarItem
        self.showReplyInMenu = showReplyInMenu
        self.showCopyInMenu = showCopyInMenu
        self.showForwardInMenu = showForwardInMenu
        self.showPinInMenu = showPinInMenu
        self.showDeleteInMenu = showDeleteInMenu
        self.doubleTapIncomingAction = doubleTapIncomingAction
        self.doubleTapOutgoingAction = doubleTapOutgoingAction
        self.swipeAction = swipeAction
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
        self.downloadSpeedBoost = try container.decodeIfPresent(Int32.self, forKey: "downloadSpeedBoost") ?? 0
        self.uploadSpeedBoost = (try container.decodeIfPresent(Int32.self, forKey: "uploadSpeedBoost") ?? 0) != 0
        self.avatarCornerRadiusPercent = try container.decodeIfPresent(Int32.self, forKey: "avatarCornerRadiusPercent") ?? -1
        self.singleCornerRadius = (try container.decodeIfPresent(Int32.self, forKey: "singleCornerRadius") ?? 0) != 0
        self.showForwardCount = (try container.decodeIfPresent(Int32.self, forKey: "showForwardCount") ?? 0) != 0

        self.disableOpenLinkWarning = (try container.decodeIfPresent(Int32.self, forKey: "disableOpenLinkWarning") ?? 0) != 0
        self.confirmSendingStickers = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingStickers") ?? 0) != 0
        self.confirmSendingGif = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingGif") ?? 0) != 0
        self.filterZalgo = (try container.decodeIfPresent(Int32.self, forKey: "filterZalgo") ?? 1) != 0
        self.disableGreetingSticker = (try container.decodeIfPresent(Int32.self, forKey: "disableGreetingSticker") ?? 0) != 0
        self.stickerSizePercent = try container.decodeIfPresent(Int32.self, forKey: "stickerSizePercent") ?? 100
        self.hideKeyboardOnScroll = (try container.decodeIfPresent(Int32.self, forKey: "hideKeyboardOnScroll") ?? 0) != 0
        self.hideSendAsButton = (try container.decodeIfPresent(Int32.self, forKey: "hideSendAsButton") ?? 0) != 0
        self.confirmSendingVoice = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingVoice") ?? 0) != 0
        self.confirmSendingRoundVideo = (try container.decodeIfPresent(Int32.self, forKey: "confirmSendingRoundVideo") ?? 0) != 0
        self.alwaysSendInHD = (try container.decodeIfPresent(Int32.self, forKey: "alwaysSendInHD") ?? 1) != 0
        self.doubleTapSeekSeconds = try container.decodeIfPresent(Int32.self, forKey: "doubleTapSeekSeconds") ?? 15

        self.saveDeletedMessages = (try container.decodeIfPresent(Int32.self, forKey: "saveDeletedMessages") ?? 1) != 0
        self.saveMessagesHistory = (try container.decodeIfPresent(Int32.self, forKey: "saveMessagesHistory") ?? 1) != 0
        self.saveForBots = (try container.decodeIfPresent(Int32.self, forKey: "saveForBots") ?? 0) != 0
        self.semiTransparentDeletedMessages = (try container.decodeIfPresent(Int32.self, forKey: "semiTransparentDeletedMessages") ?? 1) != 0
        self.deletedMark = try container.decodeIfPresent(String.self, forKey: "deletedMark") ?? "deleted · "
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
        self.sendWithoutSoundMode = try container.decodeIfPresent(Int32.self, forKey: "sendWithoutSoundMode") ?? (self.ghostSendWithoutSound ? 2 : 0)
        self.wsProxyMode = try container.decodeIfPresent(Int32.self, forKey: "wsProxyMode") ?? 0
        self.wsProxyCustomDomains = try container.decodeIfPresent(String.self, forKey: "wsProxyCustomDomains") ?? ""
        self.customChatListTitle = try container.decodeIfPresent(String.self, forKey: "customChatListTitle") ?? ""
        self.bypassCopyProtection = (try container.decodeIfPresent(Int32.self, forKey: "bypassCopyProtection") ?? 0) != 0
        self.ghostDontReadStories = (try container.decodeIfPresent(Int32.self, forKey: "ghostDontReadStories") ?? 0) != 0
        self.alwaysOnline = (try container.decodeIfPresent(Int32.self, forKey: "alwaysOnline") ?? 0) != 0
        self.disablePerChatWallpapers = (try container.decodeIfPresent(Int32.self, forKey: "disablePerChatWallpapers") ?? 0) != 0
        self.spoofDeviceModel = try container.decodeIfPresent(String.self, forKey: "spoofDeviceModel") ?? ""
        self.spoofSystemVersion = try container.decodeIfPresent(String.self, forKey: "spoofSystemVersion") ?? ""
        self.textReplacements = try container.decodeIfPresent([IOTextReplacementRule].self, forKey: "textReplacements") ?? []
        self.ghostAskBeforeReadingStories = (try container.decodeIfPresent(Int32.self, forKey: "ghostAskBeforeReadingStories") ?? 1) != 0
        self.roundVideo60Fps = (try container.decodeIfPresent(Int32.self, forKey: "roundVideo60Fps") ?? 1) != 0
        self.askRoundVideoCameraBeforeRecording = (try container.decodeIfPresent(Int32.self, forKey: "askRoundVideoCameraBeforeRecording") ?? 0) != 0
        self.roundVideoMaxZoomMode = try container.decodeIfPresent(Int32.self, forKey: "roundVideoMaxZoomMode") ?? 1
        self.showContactsTab = (try container.decodeIfPresent(Int32.self, forKey: "showContactsTab") ?? 0) != 0
        self.stickerShape = try container.decodeIfPresent(Int32.self, forKey: "stickerShape") ?? 0
        self.showTranslateInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showTranslateInMenu") ?? 1) != 0
        self.customTabBarItem = try container.decodeIfPresent(Int32.self, forKey: "customTabBarItem") ?? (self.showContactsTab ? 1 : 0)
        self.showReplyInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showReplyInMenu") ?? 1) != 0
        self.showCopyInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showCopyInMenu") ?? 1) != 0
        self.showForwardInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showForwardInMenu") ?? 1) != 0
        self.showPinInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showPinInMenu") ?? 1) != 0
        self.showDeleteInMenu = (try container.decodeIfPresent(Int32.self, forKey: "showDeleteInMenu") ?? 1) != 0
        self.doubleTapIncomingAction = try container.decodeIfPresent(Int32.self, forKey: "doubleTapIncomingAction") ?? 0
        self.doubleTapOutgoingAction = try container.decodeIfPresent(Int32.self, forKey: "doubleTapOutgoingAction") ?? 0
        self.swipeAction = try container.decodeIfPresent(Int32.self, forKey: "swipeAction") ?? 0
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
        try container.encode(self.downloadSpeedBoost, forKey: "downloadSpeedBoost")
        try container.encode((self.uploadSpeedBoost ? 1 : 0) as Int32, forKey: "uploadSpeedBoost")
        try container.encode(self.avatarCornerRadiusPercent, forKey: "avatarCornerRadiusPercent")
        try container.encode((self.singleCornerRadius ? 1 : 0) as Int32, forKey: "singleCornerRadius")
        try container.encode((self.showForwardCount ? 1 : 0) as Int32, forKey: "showForwardCount")

        try container.encode((self.disableOpenLinkWarning ? 1 : 0) as Int32, forKey: "disableOpenLinkWarning")
        try container.encode((self.confirmSendingStickers ? 1 : 0) as Int32, forKey: "confirmSendingStickers")
        try container.encode((self.confirmSendingGif ? 1 : 0) as Int32, forKey: "confirmSendingGif")
        try container.encode((self.filterZalgo ? 1 : 0) as Int32, forKey: "filterZalgo")
        try container.encode((self.disableGreetingSticker ? 1 : 0) as Int32, forKey: "disableGreetingSticker")
        try container.encode(self.stickerSizePercent, forKey: "stickerSizePercent")
        try container.encode((self.hideKeyboardOnScroll ? 1 : 0) as Int32, forKey: "hideKeyboardOnScroll")
        try container.encode((self.hideSendAsButton ? 1 : 0) as Int32, forKey: "hideSendAsButton")
        try container.encode((self.confirmSendingVoice ? 1 : 0) as Int32, forKey: "confirmSendingVoice")
        try container.encode((self.confirmSendingRoundVideo ? 1 : 0) as Int32, forKey: "confirmSendingRoundVideo")
        try container.encode((self.alwaysSendInHD ? 1 : 0) as Int32, forKey: "alwaysSendInHD")
        try container.encode(self.doubleTapSeekSeconds, forKey: "doubleTapSeekSeconds")

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
        try container.encode(self.sendWithoutSoundMode, forKey: "sendWithoutSoundMode")
        try container.encode(self.wsProxyMode, forKey: "wsProxyMode")
        try container.encode(self.wsProxyCustomDomains, forKey: "wsProxyCustomDomains")
        try container.encode(self.customChatListTitle, forKey: "customChatListTitle")
        try container.encode((self.bypassCopyProtection ? 1 : 0) as Int32, forKey: "bypassCopyProtection")
        try container.encode((self.ghostDontReadStories ? 1 : 0) as Int32, forKey: "ghostDontReadStories")
        try container.encode((self.alwaysOnline ? 1 : 0) as Int32, forKey: "alwaysOnline")
        try container.encode((self.disablePerChatWallpapers ? 1 : 0) as Int32, forKey: "disablePerChatWallpapers")
        try container.encode(self.spoofDeviceModel, forKey: "spoofDeviceModel")
        try container.encode(self.spoofSystemVersion, forKey: "spoofSystemVersion")
        try container.encode(self.textReplacements, forKey: "textReplacements")
        try container.encode((self.ghostAskBeforeReadingStories ? 1 : 0) as Int32, forKey: "ghostAskBeforeReadingStories")
        try container.encode((self.roundVideo60Fps ? 1 : 0) as Int32, forKey: "roundVideo60Fps")
        try container.encode((self.askRoundVideoCameraBeforeRecording ? 1 : 0) as Int32, forKey: "askRoundVideoCameraBeforeRecording")
        try container.encode(self.roundVideoMaxZoomMode, forKey: "roundVideoMaxZoomMode")
        try container.encode((self.showContactsTab ? 1 : 0) as Int32, forKey: "showContactsTab")
        try container.encode(self.stickerShape, forKey: "stickerShape")
        try container.encode((self.showTranslateInMenu ? 1 : 0) as Int32, forKey: "showTranslateInMenu")
        try container.encode(self.customTabBarItem, forKey: "customTabBarItem")
        try container.encode((self.showReplyInMenu ? 1 : 0) as Int32, forKey: "showReplyInMenu")
        try container.encode((self.showCopyInMenu ? 1 : 0) as Int32, forKey: "showCopyInMenu")
        try container.encode((self.showForwardInMenu ? 1 : 0) as Int32, forKey: "showForwardInMenu")
        try container.encode((self.showPinInMenu ? 1 : 0) as Int32, forKey: "showPinInMenu")
        try container.encode((self.showDeleteInMenu ? 1 : 0) as Int32, forKey: "showDeleteInMenu")
        try container.encode(self.doubleTapIncomingAction, forKey: "doubleTapIncomingAction")
        try container.encode(self.doubleTapOutgoingAction, forKey: "doubleTapOutgoingAction")
        try container.encode(self.swipeAction, forKey: "swipeAction")
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
            hideSideShareButton: settings.hideSideShareButton,
            hidePhoneNumber: settings.hidePhoneNumber,
            downloadSpeedBoost: settings.downloadSpeedBoost,
            uploadSpeedBoost: settings.uploadSpeedBoost,
            avatarCornerRadiusPercent: settings.avatarCornerRadiusPercent,
            singleCornerRadius: settings.singleCornerRadius,
            showForwardCount: settings.showForwardCount,
            stickerSizePercent: settings.stickerSizePercent,
            hideKeyboardOnScroll: settings.hideKeyboardOnScroll,
            hideSendAsButton: settings.hideSendAsButton,
            confirmSendingVoice: settings.confirmSendingVoice,
            confirmSendingRoundVideo: settings.confirmSendingRoundVideo,
            alwaysSendInHD: settings.alwaysSendInHD,
            doubleTapSeekSeconds: settings.doubleTapSeekSeconds,
            sendWithoutSoundMode: settings.sendWithoutSoundMode,
            wsProxyMode: settings.wsProxyMode,
            wsProxyCustomDomains: settings.wsProxyCustomDomains,
            customChatListTitle: settings.customChatListTitle,
            bypassCopyProtection: settings.bypassCopyProtection,
            ghostDontReadStories: settings.ghostDontReadStories,
            alwaysOnline: settings.alwaysOnline,
            disablePerChatWallpapers: settings.disablePerChatWallpapers,
            spoofDeviceModel: settings.spoofDeviceModel,
            spoofSystemVersion: settings.spoofSystemVersion,
            ghostAskBeforeReadingStories: settings.ghostAskBeforeReadingStories,
            roundVideo60Fps: settings.roundVideo60Fps,
            askRoundVideoCameraBeforeRecording: settings.askRoundVideoCameraBeforeRecording,
            roundVideoMaxZoomMode: settings.roundVideoMaxZoomMode,
            showContactsTab: settings.showContactsTab,
            stickerShape: settings.stickerShape,
            showTranslateInMenu: settings.showTranslateInMenu
        ))
        UserDefaults.standard.set(settings.roundVideoMaxZoomMode, forKey: "io.roundVideoMaxZoomMode")
        if settings.alwaysSendInHD {
            UserDefaults.standard.set(true, forKey: "TG_photoHighQuality_v0")
            UserDefaults.standard.set(5, forKey: "TG_preferredVideoPreset_v0")
        }
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
            "downloadSpeedBoost": self.downloadSpeedBoost,
            "uploadSpeedBoost": self.uploadSpeedBoost,
            "avatarCornerRadiusPercent": self.avatarCornerRadiusPercent,
            "singleCornerRadius": self.singleCornerRadius,
            "showForwardCount": self.showForwardCount,
            "disableOpenLinkWarning": self.disableOpenLinkWarning,
            "confirmSendingStickers": self.confirmSendingStickers,
            "confirmSendingGif": self.confirmSendingGif,
            "filterZalgo": self.filterZalgo,
            "disableGreetingSticker": self.disableGreetingSticker,
            "stickerSizePercent": self.stickerSizePercent,
            "hideKeyboardOnScroll": self.hideKeyboardOnScroll,
            "hideSendAsButton": self.hideSendAsButton,
            "confirmSendingVoice": self.confirmSendingVoice,
            "confirmSendingRoundVideo": self.confirmSendingRoundVideo,
            "alwaysSendInHD": self.alwaysSendInHD,
            "doubleTapSeekSeconds": self.doubleTapSeekSeconds,
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
            "ghostMarkReadAfterAction": self.ghostMarkReadAfterAction,
            "sendWithoutSoundMode": self.sendWithoutSoundMode,
            "wsProxyMode": self.wsProxyMode,
            "wsProxyCustomDomains": self.wsProxyCustomDomains,
            "customChatListTitle": self.customChatListTitle,
            "bypassCopyProtection": self.bypassCopyProtection,
            "ghostDontReadStories": self.ghostDontReadStories,
            "alwaysOnline": self.alwaysOnline,
            "disablePerChatWallpapers": self.disablePerChatWallpapers,
            "spoofDeviceModel": self.spoofDeviceModel,
            "spoofSystemVersion": self.spoofSystemVersion,
            "ghostAskBeforeReadingStories": self.ghostAskBeforeReadingStories,
            "roundVideo60Fps": self.roundVideo60Fps,
            "askRoundVideoCameraBeforeRecording": self.askRoundVideoCameraBeforeRecording,
            "roundVideoMaxZoomMode": self.roundVideoMaxZoomMode,
            "showContactsTab": self.showContactsTab,
            "stickerShape": self.stickerShape,
            "showTranslateInMenu": self.showTranslateInMenu,
            "customTabBarItem": self.customTabBarItem,
            "showReplyInMenu": self.showReplyInMenu,
            "showCopyInMenu": self.showCopyInMenu,
            "showForwardInMenu": self.showForwardInMenu,
            "showPinInMenu": self.showPinInMenu,
            "showDeleteInMenu": self.showDeleteInMenu,
            "doubleTapIncomingAction": self.doubleTapIncomingAction,
            "doubleTapOutgoingAction": self.doubleTapOutgoingAction,
            "swipeAction": self.swipeAction
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
        if let v = intValue(["downloadSpeedBoost"]) { updated.downloadSpeedBoost = max(0, min(2, v)); count += 1 }
        if let v = boolValue(["uploadSpeedBoost"]) { updated.uploadSpeedBoost = v; count += 1 }
        if let v = intValue(["avatarCornerRadiusPercent"]) { updated.avatarCornerRadiusPercent = max(-1, min(50, v)); count += 1 }
        if let v = boolValue(["singleCornerRadius"]) { updated.singleCornerRadius = v; count += 1 }
        if let v = boolValue(["showForwardCount"]) { updated.showForwardCount = v; count += 1 }
        if let v = boolValue(["disableOpenLinkWarning"]) { updated.disableOpenLinkWarning = v; count += 1 }
        if let v = boolValue(["confirmSendingStickers"]) { updated.confirmSendingStickers = v; count += 1 }
        if let v = boolValue(["confirmSendingGif"]) { updated.confirmSendingGif = v; count += 1 }
        if let v = boolValue(["filterZalgo"]) { updated.filterZalgo = v; count += 1 }
        if let v = boolValue(["disableGreetingSticker"]) { updated.disableGreetingSticker = v; count += 1 }
        if let v = intValue(["stickerSizePercent"]) { updated.stickerSizePercent = max(50, min(140, v)); count += 1 }
        if let v = boolValue(["hideKeyboardOnScroll"]) { updated.hideKeyboardOnScroll = v; count += 1 }
        if let v = boolValue(["hideSendAsButton"]) { updated.hideSendAsButton = v; count += 1 }
        if let v = boolValue(["confirmSendingVoice"]) { updated.confirmSendingVoice = v; count += 1 }
        if let v = boolValue(["confirmSendingRoundVideo"]) { updated.confirmSendingRoundVideo = v; count += 1 }
        if let v = boolValue(["alwaysSendInHD", "sendPhotosInHd"]) { updated.alwaysSendInHD = v; count += 1 }
        if let v = intValue(["doubleTapSeekSeconds", "doubleTapSeekTime"]) { updated.doubleTapSeekSeconds = max(5, min(60, v)); count += 1 }
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
        if let v = intValue(["sendWithoutSoundMode"]) { updated.sendWithoutSoundMode = max(0, min(2, v)); updated.ghostSendWithoutSound = (updated.sendWithoutSoundMode == 2); count += 1 }
        if let v = intValue(["wsProxyMode"]) { updated.wsProxyMode = max(0, min(2, v)); count += 1 }
        if let v = sourceDict["wsProxyCustomDomains"] as? String { updated.wsProxyCustomDomains = v; count += 1 }
        if let v = sourceDict["customChatListTitle"] as? String { updated.customChatListTitle = v; count += 1 }
        if let v = boolValue(["bypassCopyProtection"]) { updated.bypassCopyProtection = v; count += 1 }
        if let v = boolValue(["ghostDontReadStories"]) { updated.ghostDontReadStories = v; count += 1 }
        if let v = boolValue(["alwaysOnline"]) { updated.alwaysOnline = v; count += 1 }
        if let v = boolValue(["disablePerChatWallpapers"]) { updated.disablePerChatWallpapers = v; count += 1 }
        if let v = sourceDict["spoofDeviceModel"] as? String { updated.spoofDeviceModel = v; count += 1 }
        if let v = sourceDict["spoofSystemVersion"] as? String { updated.spoofSystemVersion = v; count += 1 }
        if let v = boolValue(["ghostAskBeforeReadingStories"]) { updated.ghostAskBeforeReadingStories = v; count += 1 }
        if let v = boolValue(["roundVideo60Fps"]) { updated.roundVideo60Fps = v; count += 1 }
        if let v = boolValue(["askRoundVideoCameraBeforeRecording"]) { updated.askRoundVideoCameraBeforeRecording = v; count += 1 }
        if let v = intValue(["roundVideoMaxZoomMode"]) { updated.roundVideoMaxZoomMode = v; count += 1 }
        if let v = boolValue(["showContactsTab"]) { updated.showContactsTab = v; count += 1 }
        if let v = intValue(["stickerShape"]) { updated.stickerShape = v; count += 1 }
        if let v = boolValue(["showTranslateInMenu"]) { updated.showTranslateInMenu = v; count += 1 }
        if let v = intValue(["customTabBarItem"]) { updated.customTabBarItem = v; count += 1 }
        if let v = boolValue(["showReplyInMenu"]) { updated.showReplyInMenu = v; count += 1 }
        if let v = boolValue(["showCopyInMenu"]) { updated.showCopyInMenu = v; count += 1 }
        if let v = boolValue(["showForwardInMenu"]) { updated.showForwardInMenu = v; count += 1 }
        if let v = boolValue(["showPinInMenu"]) { updated.showPinInMenu = v; count += 1 }
        if let v = boolValue(["showDeleteInMenu"]) { updated.showDeleteInMenu = v; count += 1 }
        if let v = intValue(["doubleTapIncomingAction"]) { updated.doubleTapIncomingAction = v; count += 1 }
        if let v = intValue(["doubleTapOutgoingAction"]) { updated.doubleTapOutgoingAction = v; count += 1 }
        if let v = intValue(["swipeAction"]) { updated.swipeAction = v; count += 1 }

        guard count > 0 else {
            return nil
        }
        return (updated, count)
    }
    public func applyTextReplacements(_ text: String) -> String {
        guard !text.isEmpty, !self.textReplacements.isEmpty else {
            return text
        }
        var result = text
        for rule in self.textReplacements {
            guard !rule.find.isEmpty else { continue }
            let options: String.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]
            result = result.replacingOccurrences(of: rule.find, with: rule.replace, options: options)
        }
        return result
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
