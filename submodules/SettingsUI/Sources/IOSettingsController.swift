import Foundation
import ObjectiveC
import UIKit
import UIKitRuntimeUtils
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI
import UndoUI

private let ioDocumentPickerDelegateKey = UnsafeRawPointer(bitPattern: 0x494F4450)!

private final class IOConfigDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL) -> Void
    private let onCancel: () -> Void

    init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.onPick(url)
        } else {
            self.onCancel()
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.onCancel()
    }
}

private func ioShowToast(context: AccountContext, present: ((ViewController) -> Void)?, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let undo = UndoOverlayController(
        presentationData: presentationData,
        content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
        elevatedLayout: false,
        action: { _ in return false }
    )
    present?(undo)
}

private func ioUpdateSettings(context: AccountContext, _ f: @escaping (IOSettings) -> IOSettings) {
    let _ = updateIOSettingsInteractively(accountManager: context.sharedContext.accountManager, f).start()
}

private func ioPresentOptionsSheet(
    context: AccountContext,
    present: ((ViewController) -> Void)?,
    title: String,
    options: [(String, () -> Void)]
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let controller = ActionSheetController(presentationData: presentationData)
    var actionItems: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
    for (label, handler) in options {
        actionItems.append(ActionSheetButtonItem(title: label, color: .accent, action: { [weak controller] in
            controller?.dismissAnimated()
            handler()
        }))
    }
    controller.setItemGroups([
        ActionSheetItemGroup(items: actionItems),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak controller] in
                controller?.dismissAnimated()
            })
        ])
    ])
    present?(controller)
}

// MARK: - Main Hub Controller (exteraGram / iOGram Preferences)

private final class IOMainHubArguments {
    let openGeneral: () -> Void
    let openAppearance: () -> Void
    let openChats: () -> Void
    let openGhostPrivacy: () -> Void
    let openFilters: () -> Void
    let openBackup: () -> Void
    let syncBadges: () -> Void
    let openUrl: (String) -> Void

    init(
        openGeneral: @escaping () -> Void,
        openAppearance: @escaping () -> Void,
        openChats: @escaping () -> Void,
        openGhostPrivacy: @escaping () -> Void,
        openFilters: @escaping () -> Void,
        openBackup: @escaping () -> Void,
        syncBadges: @escaping () -> Void,
        openUrl: @escaping (String) -> Void
    ) {
        self.openGeneral = openGeneral
        self.openAppearance = openAppearance
        self.openChats = openChats
        self.openGhostPrivacy = openGhostPrivacy
        self.openFilters = openFilters
        self.openBackup = openBackup
        self.syncBadges = syncBadges
        self.openUrl = openUrl
    }
}

private enum IOMainHubSection: Int32 {
    case header
    case categories
    case tools
    case links
}

private enum IOMainHubEntry: ItemListNodeEntry {
    case headerInfo(Int)
    case categoriesHeader
    case generalCategory
    case appearanceCategory
    case chatsCategory
    case ghostCategory
    case filtersCategory(Int, Int)
    case backupCategory
    case categoriesFooter
    case toolsHeader
    case syncBadges(Int)
    case linksHeader
    case exteraSource
    case ayuSource
    case linksFooter

    var section: ItemListSectionId {
        switch self {
        case .headerInfo:
            return IOMainHubSection.header.rawValue
        case .categoriesHeader, .generalCategory, .appearanceCategory, .chatsCategory, .ghostCategory, .filtersCategory, .backupCategory, .categoriesFooter:
            return IOMainHubSection.categories.rawValue
        case .toolsHeader, .syncBadges:
            return IOMainHubSection.tools.rawValue
        case .linksHeader, .exteraSource, .ayuSource, .linksFooter:
            return IOMainHubSection.links.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .headerInfo: return 0
        case .categoriesHeader: return 10
        case .generalCategory: return 11
        case .appearanceCategory: return 12
        case .chatsCategory: return 13
        case .ghostCategory: return 14
        case .filtersCategory: return 15
        case .backupCategory: return 16
        case .categoriesFooter: return 17
        case .toolsHeader: return 30
        case .syncBadges: return 31
        case .linksHeader: return 50
        case .exteraSource: return 51
        case .ayuSource: return 52
        case .linksFooter: return 53
        }
    }

    static func <(lhs: IOMainHubEntry, rhs: IOMainHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOMainHubArguments
        switch self {
        case let .headerInfo(badgesCount):
            return ItemListTextItem(
                presentationData: presentationData,
                text: .plain("iOGram Preferences · exteraGram & AyuGram Tweaks (\(badgesCount) cached badges)"),
                sectionId: self.section
            )
        case .categoriesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "CATEGORIES", sectionId: self.section)
        case .generalCategory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.dataAndStorage, title: "General", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGeneral()
            })
        case .appearanceCategory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: "Appearance", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openAppearance()
            })
        case .chatsCategory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.groups, title: "Chats", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openChats()
            })
        case .ghostCategory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: "Ghost & Anti-Recall", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGhostPrivacy()
            })
        case let .filtersCategory(keywords, peers):
            let total = keywords + peers
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.block, title: "Filters & Anti-Spam", label: total == 0 ? "Off" : "\(total)", sectionId: self.section, style: .blocks, action: {
                arguments.openFilters()
            })
        case .backupCategory:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.chatFolders, title: "Backup & Restore", label: ".json / .extera", sectionId: self.section, style: .blocks, action: {
                arguments.openBackup()
            })
        case .categoriesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Configure speed boosts, avatar geometry, stickers, Ghost Mode, Anti-Recall, disappearing media protection, and exteraGram badges."), sectionId: self.section)
        case .toolsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "EXTERAGRAM BADGES", sectionId: self.section)
        case let .syncBadges(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.premium, title: "Sync exteraGram Badges", label: count > 0 ? "\(count) cached" : "Sync", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.syncBadges()
            })
        case .linksHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "LINKS", sectionId: self.section)
        case .exteraSource:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.channels, title: "exteraGram", label: "GitHub", sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://github.com/exteraSquad/exteraGram")
            })
        case .ayuSource:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.bot, title: "AyuGram Desktop", label: "GitHub", sectionId: self.section, style: .blocks, action: {
                arguments.openUrl("https://github.com/AyuGram/AyuGramDesktop")
            })
        case .linksFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Features inspired by exteraGram and AyuGram."), sectionId: self.section)
        }
    }
}

public func ioSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    let badgeSyncVersion = ValuePromise<Int>(0, ignoreRepeated: false)

    let arguments = IOMainHubArguments(
        openGeneral: {
            pushControllerImpl?(ioGeneralSettingsController(context: context))
        },
        openAppearance: {
            pushControllerImpl?(ioAppearanceSettingsController(context: context))
        },
        openChats: {
            pushControllerImpl?(ioChatsSettingsController(context: context))
        },
        openGhostPrivacy: {
            pushControllerImpl?(ioGhostSettingsController(context: context))
        },
        openFilters: {
            pushControllerImpl?(ioFiltersController(context: context))
        },
        openBackup: {
            pushControllerImpl?(ioBackupSettingsController(context: context))
        },
        syncBadges: {
            let _ = (Signal<(Int, Bool), NoError> { subscriber in
                IOExteraBadges.shared.syncIfNeeded(force: true) { count, success in
                    subscriber.putNext((count, success))
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
            |> deliverOnMainQueue).startStandalone(next: { count, success in
                badgeSyncVersion.set(count + 1)
                if success {
                    ioShowToast(context: context, present: presentControllerImpl, text: "Synced \(count) exteraGram badges")
                } else {
                    ioShowToast(context: context, present: presentControllerImpl, text: "Badge sync failed (\(count) cached)")
                }
            })
        },
        openUrl: { urlString in
            if let url = URL(string: urlString) {
                context.sharedContext.applicationBindings.openUrl(url.absoluteString)
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.ioSettings]),
        badgeSyncVersion.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.ioSettings]?.get(IOSettings.self) ?? IOSettings.defaultSettings
        let cachedCount = IOExteraBadges.shared.cachedProfileCount

        let entries: [IOMainHubEntry] = [
            .headerInfo(cachedCount),
            .categoriesHeader,
            .generalCategory,
            .appearanceCategory,
            .chatsCategory,
            .ghostCategory,
            .filtersCategory(settings.blockedKeywords.count, settings.shadowBannedPeerIds.count),
            .backupCategory,
            .categoriesFooter,
            .toolsHeader,
            .syncBadges(cachedCount),
            .linksHeader,
            .exteraSource,
            .ayuSource,
            .linksFooter
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("iOGram Preferences"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - 1. General Preferences

private final class IOGeneralArguments {
    let update: (@escaping (IOSettings) -> IOSettings) -> Void
    let pickWsProxyMode: () -> Void
    let pickDownloadBoost: () -> Void
    let pickIdFormat: () -> Void

    init(
        update: @escaping (@escaping (IOSettings) -> IOSettings) -> Void,
        pickWsProxyMode: @escaping () -> Void,
        pickDownloadBoost: @escaping () -> Void,
        pickIdFormat: @escaping () -> Void
    ) {
        self.update = update
        self.pickWsProxyMode = pickWsProxyMode
        self.pickDownloadBoost = pickDownloadBoost
        self.pickIdFormat = pickIdFormat
    }
}

private enum IOGeneralSection: Int32 {
    case connection
    case speed
    case profile
    case other
}

private enum IOGeneralEntry: ItemListNodeEntry {
    case connectionHeader
    case wsProxyMode(Int32)
    case wsProxyCustomDomains(String)
    case connectionFooter
    case speedHeader
    case downloadSpeedBoost(Int32)
    case uploadSpeedBoost(Bool)
    case speedFooter
    case profileHeader
    case hidePhoneNumber(Bool)
    case peerIdDisplayMode(IOSettings.PeerIdDisplayMode)
    case profileFooter
    case otherHeader
    case disableAds(Bool)
    case disableOpenLinkWarning(Bool)
    case localPremium(Bool)
    case otherFooter

    var section: ItemListSectionId {
        switch self {
        case .connectionHeader, .wsProxyMode, .wsProxyCustomDomains, .connectionFooter:
            return IOGeneralSection.connection.rawValue
        case .speedHeader, .downloadSpeedBoost, .uploadSpeedBoost, .speedFooter:
            return IOGeneralSection.speed.rawValue
        case .profileHeader, .hidePhoneNumber, .peerIdDisplayMode, .profileFooter:
            return IOGeneralSection.profile.rawValue
        case .otherHeader, .disableAds, .disableOpenLinkWarning, .localPremium, .otherFooter:
            return IOGeneralSection.other.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .connectionHeader: return 0
        case .wsProxyMode: return 1
        case .wsProxyCustomDomains: return 2
        case .connectionFooter: return 3
        case .speedHeader: return 10
        case .downloadSpeedBoost: return 11
        case .uploadSpeedBoost: return 12
        case .speedFooter: return 13
        case .profileHeader: return 20
        case .hidePhoneNumber: return 21
        case .peerIdDisplayMode: return 22
        case .profileFooter: return 23
        case .otherHeader: return 30
        case .disableAds: return 31
        case .disableOpenLinkWarning: return 32
        case .localPremium: return 33
        case .otherFooter: return 34
        }
    }

    static func <(lhs: IOGeneralEntry, rhs: IOGeneralEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOGeneralArguments
        switch self {
        case .connectionHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "BUILT-IN WS PROXY (TG-WS-PROXY)", sectionId: self.section)
        case let .wsProxyMode(mode):
            let label: String
            switch mode {
            case 1: label = "Auto (WS + CF)"
            case 2: label = "Cloudflare Only"
            default: label = "Off"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "TG-WS Proxy (No-VPN)", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickWsProxyMode()
            })
        case let .wsProxyCustomDomains(domains):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: domains, placeholder: "Custom CF domains (optional, comma-separated)", type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, sectionId: self.section, textUpdated: { value in
                arguments.update { var u = $0; u.wsProxyCustomDomains = value; return u }
            }, action: {})
        case .connectionFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Routes MTProto over TLS WebSocket (kws.web.telegram.org) and Cloudflare relay domains when no manual proxy is enabled."), sectionId: self.section)
        case .speedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "DOWNLOAD & UPLOAD BOOST", sectionId: self.section)
        case let .downloadSpeedBoost(level):
            let label: String
            switch level {
            case 1: label = "Fast"
            case 2: label = "Ultra"
            default: label = "Off"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Download Speed Boost", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickDownloadBoost()
            })
        case let .uploadSpeedBoost(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Upload Speed Boost", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.uploadSpeedBoost = value; return u }
            })
        case .speedFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Increases concurrent chunk downloads (Fast/Ultra) and parallel upload threads for larger files."), sectionId: self.section)
        case .profileHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "PROFILE", sectionId: self.section)
        case let .hidePhoneNumber(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Phone Number", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hidePhoneNumber = value; return u }
            })
        case let .peerIdDisplayMode(mode):
            let label: String
            switch mode {
            case .hidden: label = "Hidden"
            case .telegramApi: label = "Telegram API"
            case .botApi: label = "Bot API"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Show ID and DC", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickIdFormat()
            })
        case .profileFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Telegram API shows IDs as they are, while Bot API adds -100 prefix for channels and supergroups."), sectionId: self.section)
        case .otherHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GENERAL", sectionId: self.section)
        case let .disableAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Sponsored Ads", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.disableAds = value; return u }
            })
        case let .disableOpenLinkWarning(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Open Link Warning", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.disableOpenLinkWarning = value; return u }
            })
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Local Telegram Premium", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.localPremium = value; return u }
            })
        case .otherFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Local Premium unlocks client-side visual perks only; server-side limits remain enforced by Telegram."), sectionId: self.section)
        }
    }
}

private func ioGeneralSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = IOGeneralArguments(
        update: { f in ioUpdateSettings(context: context, f) },
        pickWsProxyMode: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "TG-WS Proxy (No-VPN)", options: [
                ("Off", { ioUpdateSettings(context: context) { var u = $0; u.wsProxyMode = 0; return u } }),
                ("Auto (WS + Cloudflare Relay)", { ioUpdateSettings(context: context) { var u = $0; u.wsProxyMode = 1; return u } }),
                ("Cloudflare Relay Only", { ioUpdateSettings(context: context) { var u = $0; u.wsProxyMode = 2; return u } })
            ])
        },
        pickDownloadBoost: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Download Speed Boost", options: [
                ("Off (Default)", { ioUpdateSettings(context: context) { var u = $0; u.downloadSpeedBoost = 0; return u } }),
                ("Fast", { ioUpdateSettings(context: context) { var u = $0; u.downloadSpeedBoost = 1; return u } }),
                ("Ultra", { ioUpdateSettings(context: context) { var u = $0; u.downloadSpeedBoost = 2; return u } })
            ])
        },
        pickIdFormat: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Show Peer ID Format", options: [
                ("Hidden", { ioUpdateSettings(context: context) { var u = $0; u.peerIdDisplayMode = .hidden; return u } }),
                ("Telegram API", { ioUpdateSettings(context: context) { var u = $0; u.peerIdDisplayMode = .telegramApi; return u } }),
                ("Bot API (-100)", { ioUpdateSettings(context: context) { var u = $0; u.peerIdDisplayMode = .botApi; return u } })
            ])
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.ioSettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.ioSettings]?.get(IOSettings.self) ?? IOSettings.defaultSettings

        var entries: [IOGeneralEntry] = [
            .connectionHeader,
            .wsProxyMode(settings.wsProxyMode)
        ]
        if settings.wsProxyMode > 0 {
            entries.append(.wsProxyCustomDomains(settings.wsProxyCustomDomains))
        }
        entries.append(contentsOf: [
            .connectionFooter,
            .speedHeader,
            .downloadSpeedBoost(settings.downloadSpeedBoost),
            .uploadSpeedBoost(settings.uploadSpeedBoost),
            .speedFooter,
            .profileHeader,
            .hidePhoneNumber(settings.hidePhoneNumber),
            .peerIdDisplayMode(settings.peerIdDisplayMode),
            .profileFooter,
            .otherHeader,
            .disableAds(settings.disableAds),
            .disableOpenLinkWarning(settings.disableOpenLinkWarning),
            .localPremium(settings.localPremium),
            .otherFooter
        ])
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text("General"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                arguments
            )
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}

// MARK: - 2. Appearance Preferences

private final class IOAppearanceArguments {
    let update: (@escaping (IOSettings) -> IOSettings) -> Void
    let pickAvatarCorners: () -> Void
    let syncBadges: () -> Void

    init(
        update: @escaping (@escaping (IOSettings) -> IOSettings) -> Void,
        pickAvatarCorners: @escaping () -> Void,
        syncBadges: @escaping () -> Void
    ) {
        self.update = update
        self.pickAvatarCorners = pickAvatarCorners
        self.syncBadges = syncBadges
    }
}

private enum IOAppearanceSection: Int32 {
    case avatars
    case chatList
    case messages
    case badges
}

private enum IOAppearanceEntry: ItemListNodeEntry {
    case avatarsHeader
    case avatarCorners(Int32)
    case singleCornerRadius(Bool)
    case avatarsFooter
    case chatListHeader
    case hideStories(Bool)
    case hideAllChatsFolder(Bool)
    case messagesHeader
    case removeMessageTail(Bool)
    case replaceEditedWithIcon(Bool)
    case showForwardCount(Bool)
    case hideSideShareButton(Bool)
    case showMessageSeconds(Bool)
    case disableNumberRounding(Bool)
    case messagesFooter
    case badgesHeader
    case showExteraBadges(Bool)
    case syncExteraBadges(Int)

    var section: ItemListSectionId {
        switch self {
        case .avatarsHeader, .avatarCorners, .singleCornerRadius, .avatarsFooter:
            return IOAppearanceSection.avatars.rawValue
        case .chatListHeader, .hideStories, .hideAllChatsFolder:
            return IOAppearanceSection.chatList.rawValue
        case .messagesHeader, .removeMessageTail, .replaceEditedWithIcon, .showForwardCount, .hideSideShareButton, .showMessageSeconds, .disableNumberRounding, .messagesFooter:
            return IOAppearanceSection.messages.rawValue
        case .badgesHeader, .showExteraBadges, .syncExteraBadges:
            return IOAppearanceSection.badges.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .avatarsHeader: return 0
        case .avatarCorners: return 1
        case .singleCornerRadius: return 2
        case .avatarsFooter: return 3
        case .chatListHeader: return 10
        case .hideStories: return 11
        case .hideAllChatsFolder: return 12
        case .messagesHeader: return 20
        case .removeMessageTail: return 21
        case .replaceEditedWithIcon: return 22
        case .showForwardCount: return 23
        case .hideSideShareButton: return 24
        case .showMessageSeconds: return 25
        case .disableNumberRounding: return 26
        case .messagesFooter: return 27
        case .badgesHeader: return 30
        case .showExteraBadges: return 31
        case .syncExteraBadges: return 32
        }
    }

    static func <(lhs: IOAppearanceEntry, rhs: IOAppearanceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOAppearanceArguments
        switch self {
        case .avatarsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "AVATAR CORNERS", sectionId: self.section)
        case let .avatarCorners(percent):
            let label: String
            switch percent {
            case -1: label = "Default"
            case 50: label = "Circle"
            case 35: label = "Rounded (35%)"
            case 25: label = "Squircle (25%)"
            case 12: label = "Square (12%)"
            case 0: label = "Sharp (0%)"
            default: label = "\(percent)%"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Avatar Corners", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickAvatarCorners()
            })
        case let .singleCornerRadius(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Single Corner Radius", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.singleCornerRadius = value; return u }
            })
        case .avatarsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Forums will have the same avatar shape as regular chats when Single Corner Radius is enabled."), sectionId: self.section)
        case .chatListHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "CHAT LIST", sectionId: self.section)
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideStories = value; return u }
            })
        case let .hideAllChatsFolder(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide \"All Chats\" Tab", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideAllChatsFolder = value; return u }
            })
        case .messagesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "MESSAGES", sectionId: self.section)
        case let .removeMessageTail(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Remove Message Tail", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.removeMessageTail = value; return u }
            })
        case let .replaceEditedWithIcon(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Replace \"edited\" with ✎", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.replaceEditedWithIcon = value; return u }
            })
        case let .showForwardCount(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Forward Count", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showForwardCount = value; return u }
            })
        case let .hideSideShareButton(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Side \"Share\" Button", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideSideShareButton = value; return u }
            })
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Time with Seconds", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showMessageSeconds = value; return u }
            })
        case let .disableNumberRounding(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Number Rounding", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.disableNumberRounding = value; return u }
            })
        case .messagesFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Changing \"Remove Message Tail\" or Avatar Corners applies cleanly after switching chats or restarting."), sectionId: self.section)
        case .badgesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "EXTERAGRAM BADGES", sectionId: self.section)
        case let .showExteraBadges(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show exteraGram Badges", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showExteraBadges = value; return u }
                if value {
                    IOExteraBadges.shared.syncIfNeeded()
                }
            })
        case let .syncExteraBadges(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Sync exteraGram Badges", label: count > 0 ? "\(count) cached" : "Sync", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.syncBadges()
            })
        }
    }
}

private func ioAppearanceSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let badgeSyncVersion = ValuePromise<Int>(0, ignoreRepeated: false)

    let arguments = IOAppearanceArguments(
        update: { f in ioUpdateSettings(context: context, f) },
        pickAvatarCorners: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Avatar Corners", options: [
                ("Default", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = -1; return u } }),
                ("Circle (50%)", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = 50; return u } }),
                ("Rounded (35%)", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = 35; return u } }),
                ("Squircle (25%)", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = 25; return u } }),
                ("Square (12%)", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = 12; return u } }),
                ("Sharp (0%)", { ioUpdateSettings(context: context) { var u = $0; u.avatarCornerRadiusPercent = 0; return u } })
            ])
        },
        syncBadges: {
            let _ = (Signal<(Int, Bool), NoError> { subscriber in
                IOExteraBadges.shared.syncIfNeeded(force: true) { count, success in
                    subscriber.putNext((count, success))
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
            |> deliverOnMainQueue).startStandalone(next: { count, success in
                badgeSyncVersion.set(count + 1)
                ioShowToast(context: context, present: presentControllerImpl, text: success ? "Synced \(count) exteraGram badges" : "Badge sync failed (\(count) cached)")
            })
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.ioSettings]),
        badgeSyncVersion.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.ioSettings]?.get(IOSettings.self) ?? IOSettings.defaultSettings

        let entries: [IOAppearanceEntry] = [
            .avatarsHeader,
            .avatarCorners(settings.avatarCornerRadiusPercent),
            .singleCornerRadius(settings.singleCornerRadius),
            .avatarsFooter,
            .chatListHeader,
            .hideStories(settings.hideStories),
            .hideAllChatsFolder(settings.hideAllChatsFolder),
            .messagesHeader,
            .removeMessageTail(settings.removeMessageTail),
            .replaceEditedWithIcon(settings.replaceEditedWithIcon),
            .showForwardCount(settings.showForwardCount),
            .hideSideShareButton(settings.hideSideShareButton),
            .showMessageSeconds(settings.showMessageSeconds),
            .disableNumberRounding(settings.disableNumberRounding),
            .messagesFooter,
            .badgesHeader,
            .showExteraBadges(settings.showExteraBadges),
            .syncExteraBadges(IOExteraBadges.shared.cachedProfileCount)
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text("Appearance"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                arguments
            )
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}

// MARK: - 3. Chats Preferences

private final class IOChatsArguments {
    let update: (@escaping (IOSettings) -> IOSettings) -> Void
    let pickStickerSize: () -> Void
    let pickDoubleTapSeek: () -> Void

    init(
        update: @escaping (@escaping (IOSettings) -> IOSettings) -> Void,
        pickStickerSize: @escaping () -> Void,
        pickDoubleTapSeek: @escaping () -> Void
    ) {
        self.update = update
        self.pickStickerSize = pickStickerSize
        self.pickDoubleTapSeek = pickDoubleTapSeek
    }
}

private enum IOChatsSection: Int32 {
    case stickers
    case reactions
    case input
    case confirmations
    case media
}

private enum IOChatsEntry: ItemListNodeEntry {
    case stickersHeader
    case stickerSize(Int32)
    case disableGreetingSticker(Bool)
    case reactionsHeader
    case hideReactionsPrivate(Bool)
    case hideReactionsGroups(Bool)
    case hideReactionsChannels(Bool)
    case inputHeader
    case hideKeyboardOnScroll(Bool)
    case hideSendAsButton(Bool)
    case filterZalgo(Bool)
    case confirmationsHeader
    case confirmStickers(Bool)
    case confirmGif(Bool)
    case confirmVoice(Bool)
    case confirmRoundVideo(Bool)
    case mediaHeader
    case alwaysSendInHD(Bool)
    case doubleTapSeek(Int32)

    var section: ItemListSectionId {
        switch self {
        case .stickersHeader, .stickerSize, .disableGreetingSticker:
            return IOChatsSection.stickers.rawValue
        case .reactionsHeader, .hideReactionsPrivate, .hideReactionsGroups, .hideReactionsChannels:
            return IOChatsSection.reactions.rawValue
        case .inputHeader, .hideKeyboardOnScroll, .hideSendAsButton, .filterZalgo:
            return IOChatsSection.input.rawValue
        case .confirmationsHeader, .confirmStickers, .confirmGif, .confirmVoice, .confirmRoundVideo:
            return IOChatsSection.confirmations.rawValue
        case .mediaHeader, .alwaysSendInHD, .doubleTapSeek:
            return IOChatsSection.media.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .stickersHeader: return 0
        case .stickerSize: return 1
        case .disableGreetingSticker: return 2
        case .reactionsHeader: return 10
        case .hideReactionsPrivate: return 11
        case .hideReactionsGroups: return 12
        case .hideReactionsChannels: return 13
        case .inputHeader: return 20
        case .hideKeyboardOnScroll: return 21
        case .hideSendAsButton: return 22
        case .filterZalgo: return 23
        case .confirmationsHeader: return 30
        case .confirmStickers: return 31
        case .confirmGif: return 32
        case .confirmVoice: return 33
        case .confirmRoundVideo: return 34
        case .mediaHeader: return 40
        case .alwaysSendInHD: return 41
        case .doubleTapSeek: return 42
        }
    }

    static func <(lhs: IOChatsEntry, rhs: IOChatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOChatsArguments
        switch self {
        case .stickersHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "STICKERS", sectionId: self.section)
        case let .stickerSize(percent):
            let label = percent == 100 ? "100% (Default)" : "\(percent)%"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Sticker Size", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickStickerSize()
            })
        case let .disableGreetingSticker(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Greeting Sticker", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.disableGreetingSticker = value; return u }
            })
        case .reactionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "HIDE REACTIONS", sectionId: self.section)
        case let .hideReactionsPrivate(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Private Chats", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideReactionsInPrivateChats = value; return u }
            })
        case let .hideReactionsGroups(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Groups", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideReactionsInGroups = value; return u }
            })
        case let .hideReactionsChannels(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Channels", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideReactionsInChannels = value; return u }
            })
        case .inputHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "CHATS & INPUT", sectionId: self.section)
        case let .hideKeyboardOnScroll(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Keyboard on Scroll", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideKeyboardOnScroll = value; return u }
            })
        case let .hideSendAsButton(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide \"Send as...\" Button", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.hideSendAsButton = value; return u }
            })
        case let .filterZalgo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Filter Zalgo Text", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.filterZalgo = value; return u }
            })
        case .confirmationsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "SEND CONFIRMATIONS", sectionId: self.section)
        case let .confirmStickers(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending Stickers", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.confirmSendingStickers = value; return u }
            })
        case let .confirmGif(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending GIFs", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.confirmSendingGif = value; return u }
            })
        case let .confirmVoice(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending Voice Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.confirmSendingVoice = value; return u }
            })
        case let .confirmRoundVideo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending Round Videos", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.confirmSendingRoundVideo = value; return u }
            })
        case .mediaHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "PHOTOS & VIDEOS", sectionId: self.section)
        case let .alwaysSendInHD(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Always Send Photos in HD", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.alwaysSendInHD = value; return u }
            })
        case let .doubleTapSeek(seconds):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Double Tap Skip Time", label: "\(seconds) seconds", sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickDoubleTapSeek()
            })
        }
    }
}

private func ioChatsSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = IOChatsArguments(
        update: { f in ioUpdateSettings(context: context, f) },
        pickStickerSize: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Sticker Size", options: [
                ("Small (60%)", { ioUpdateSettings(context: context) { var u = $0; u.stickerSizePercent = 60; return u } }),
                ("Medium (80%)", { ioUpdateSettings(context: context) { var u = $0; u.stickerSizePercent = 80; return u } }),
                ("Default (100%)", { ioUpdateSettings(context: context) { var u = $0; u.stickerSizePercent = 100; return u } }),
                ("Large (120%)", { ioUpdateSettings(context: context) { var u = $0; u.stickerSizePercent = 120; return u } })
            ])
        },
        pickDoubleTapSeek: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Double Tap Skip Time", options: [
                ("5 seconds", { ioUpdateSettings(context: context) { var u = $0; u.doubleTapSeekSeconds = 5; return u } }),
                ("10 seconds", { ioUpdateSettings(context: context) { var u = $0; u.doubleTapSeekSeconds = 10; return u } }),
                ("15 seconds (Default)", { ioUpdateSettings(context: context) { var u = $0; u.doubleTapSeekSeconds = 15; return u } }),
                ("30 seconds", { ioUpdateSettings(context: context) { var u = $0; u.doubleTapSeekSeconds = 30; return u } })
            ])
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.ioSettings])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.ioSettings]?.get(IOSettings.self) ?? IOSettings.defaultSettings

        let entries: [IOChatsEntry] = [
            .stickersHeader,
            .stickerSize(settings.stickerSizePercent),
            .disableGreetingSticker(settings.disableGreetingSticker),
            .reactionsHeader,
            .hideReactionsPrivate(settings.hideReactionsInPrivateChats),
            .hideReactionsGroups(settings.hideReactionsInGroups),
            .hideReactionsChannels(settings.hideReactionsInChannels),
            .inputHeader,
            .hideKeyboardOnScroll(settings.hideKeyboardOnScroll),
            .hideSendAsButton(settings.hideSendAsButton),
            .filterZalgo(settings.filterZalgo),
            .confirmationsHeader,
            .confirmStickers(settings.confirmSendingStickers),
            .confirmGif(settings.confirmSendingGif),
            .confirmVoice(settings.confirmSendingVoice),
            .confirmRoundVideo(settings.confirmSendingRoundVideo),
            .mediaHeader,
            .alwaysSendInHD(settings.alwaysSendInHD),
            .doubleTapSeek(settings.doubleTapSeekSeconds)
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text("Chats"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                arguments
            )
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}

// MARK: - 4. Ghost Mode & Anti-Recall Preferences

private final class IOGhostArguments {
    let update: (@escaping (IOSettings) -> IOSettings) -> Void
    let toggleSkipReadHistory: (Bool) -> Void
    let pickSendWithoutSoundMode: () -> Void
    let pickDeletedMark: () -> Void
    let clearSavedDeletedMessages: () -> Void

    init(
        update: @escaping (@escaping (IOSettings) -> IOSettings) -> Void,
        toggleSkipReadHistory: @escaping (Bool) -> Void,
        pickSendWithoutSoundMode: @escaping () -> Void,
        pickDeletedMark: @escaping () -> Void,
        clearSavedDeletedMessages: @escaping () -> Void
    ) {
        self.update = update
        self.toggleSkipReadHistory = toggleSkipReadHistory
        self.pickSendWithoutSoundMode = pickSendWithoutSoundMode
        self.pickDeletedMark = pickDeletedMark
        self.clearSavedDeletedMessages = clearSavedDeletedMessages
    }
}

private enum IOGhostSection: Int32 {
    case ghost
    case antiRecall
    case disappearing
}

private enum IOGhostEntry: ItemListNodeEntry {
    case ghostHeader
    case skipReadHistory(Bool)
    case ghostDontSendOnline(Bool)
    case ghostDontSendTyping(Bool)
    case sendWithoutSoundMode(Int32)
    case ghostMarkReadAfterAction(Bool)
    case ghostFooter

    case antiRecallHeader
    case saveDeletedMessages(Bool)
    case saveMessagesHistory(Bool)
    case saveForBots(Bool)
    case semiTransparentDeletedMessages(Bool)
    case deletedMark(String)
    case showEditHistoryInMenu(Bool)
    case showMessageDetailsInMenu(Bool)
    case showRepeatMessageInMenu(Bool)
    case clearSavedDeletedMessages

    case disappearingHeader
    case saveDisappearingMedia(Bool)
    case disableScreenshotProtection(Bool)
    case showFlameOnSelfDestruct(Bool)
    case disappearingFooter

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .skipReadHistory, .ghostDontSendOnline, .ghostDontSendTyping, .sendWithoutSoundMode, .ghostMarkReadAfterAction, .ghostFooter:
            return IOGhostSection.ghost.rawValue
        case .antiRecallHeader, .saveDeletedMessages, .saveMessagesHistory, .saveForBots, .semiTransparentDeletedMessages, .deletedMark, .showEditHistoryInMenu, .showMessageDetailsInMenu, .showRepeatMessageInMenu, .clearSavedDeletedMessages:
            return IOGhostSection.antiRecall.rawValue
        case .disappearingHeader, .saveDisappearingMedia, .disableScreenshotProtection, .showFlameOnSelfDestruct, .disappearingFooter:
            return IOGhostSection.disappearing.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader: return 0
        case .skipReadHistory: return 1
        case .ghostDontSendOnline: return 2
        case .ghostDontSendTyping: return 3
        case .sendWithoutSoundMode: return 4
        case .ghostMarkReadAfterAction: return 5
        case .ghostFooter: return 6
        case .antiRecallHeader: return 20
        case .saveDeletedMessages: return 21
        case .saveMessagesHistory: return 22
        case .saveForBots: return 23
        case .semiTransparentDeletedMessages: return 24
        case .deletedMark: return 25
        case .showEditHistoryInMenu: return 26
        case .showMessageDetailsInMenu: return 27
        case .showRepeatMessageInMenu: return 28
        case .clearSavedDeletedMessages: return 29
        case .disappearingHeader: return 40
        case .saveDisappearingMedia: return 41
        case .disableScreenshotProtection: return 42
        case .showFlameOnSelfDestruct: return 43
        case .disappearingFooter: return 44
        }
    }

    static func <(lhs: IOGhostEntry, rhs: IOGhostEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOGhostArguments
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GHOST MODE", sectionId: self.section)
        case let .skipReadHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Read Messages & Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleSkipReadHistory(value)
            })
        case let .ghostDontSendOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Send Online Status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.ghostDontSendOnline = value; return u }
            })
        case let .ghostDontSendTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Send Typing & Upload", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.ghostDontSendTyping = value; return u }
            })
        case let .sendWithoutSoundMode(mode):
            let label: String
            switch mode {
            case 1: label = "Ghost Mode"
            case 2: label = "Always"
            default: label = "Never"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Send Without Sound", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickSendWithoutSoundMode()
            })
        case let .ghostMarkReadAfterAction(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Read on Interact", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.ghostMarkReadAfterAction = value; return u }
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Prevents read receipts, online pings, and typing indicators. Read on Interact marks messages read only when you reply or react."), sectionId: self.section)
        case .antiRecallHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ANTI-RECALL & EDIT HISTORY", sectionId: self.section)
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Deleted Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.saveDeletedMessages = value; return u }
            })
        case let .saveMessagesHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Edit History", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.saveMessagesHistory = value; return u }
            })
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Deleted Bot Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.saveForBots = value; return u }
            })
        case let .semiTransparentDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Translucent Deleted Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.semiTransparentDeletedMessages = value; return u }
            })
        case let .deletedMark(mark):
            let display = mark.trimmingCharacters(in: .whitespaces)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Deleted Mark", label: display.isEmpty ? "Hidden" : display, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.pickDeletedMark()
            })
        case let .showEditHistoryInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Edit History in Context Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showEditHistoryInMenu = value; return u }
            })
        case let .showMessageDetailsInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Message Details in Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showMessageDetailsInMenu = value; return u }
            })
        case let .showRepeatMessageInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Repeat Message in Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showRepeatMessageInMenu = value; return u }
            })
        case .clearSavedDeletedMessages:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Clear Saved Deleted Messages", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearSavedDeletedMessages()
            })
        case .disappearingHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "SELF-DESTRUCTING MEDIA", sectionId: self.section)
        case let .saveDisappearingMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Disappearing Media", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.saveDisappearingMedia = value; return u }
            })
        case let .disableScreenshotProtection(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Allow Screenshots & Saving", value: value, sectionId: self.section, style: .blocks, updated: { value in
                ioSetAllowScreenshots(value)
                arguments.update { var u = $0; u.disableScreenshotProtection = value; return u }
            })
        case let .showFlameOnSelfDestruct(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Flame Icon on Disappearing Media", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { var u = $0; u.showFlameOnSelfDestruct = value; return u }
            })
        case .disappearingFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Saves view-once/timed media locally with spoiler blur, 🔥 mark, unrestricted replay, screenshots, and gallery export."), sectionId: self.section)
        }
    }
}

private func ioGhostSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = IOGhostArguments(
        update: { f in ioUpdateSettings(context: context, f) },
        toggleSkipReadHistory: { value in
            IOCoreConfig.setSkipReadHistory(value)
            let _ = (context.sharedContext.accountManager.transaction { transaction -> Void in
                transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { entry in
                    var settings = entry?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
                    settings.skipReadHistory = value
                    return SharedPreferencesEntry(settings)
                })
            }).start()
        },
        pickSendWithoutSoundMode: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Send Without Sound", options: [
                ("Never", { ioUpdateSettings(context: context) { var u = $0; u.sendWithoutSoundMode = 0; u.ghostSendWithoutSound = false; return u } }),
                ("When using Ghost Mode", { ioUpdateSettings(context: context) { var u = $0; u.sendWithoutSoundMode = 1; u.ghostSendWithoutSound = false; return u } }),
                ("Always", { ioUpdateSettings(context: context) { var u = $0; u.sendWithoutSoundMode = 2; u.ghostSendWithoutSound = true; return u } })
            ])
        },
        pickDeletedMark: {
            ioPresentOptionsSheet(context: context, present: presentControllerImpl, title: "Deleted Mark", options: [
                ("🗑", { ioUpdateSettings(context: context) { var u = $0; u.deletedMark = "🗑 "; return u } }),
                ("deleted ·", { ioUpdateSettings(context: context) { var u = $0; u.deletedMark = "deleted · "; return u } }),
                ("×", { ioUpdateSettings(context: context) { var u = $0; u.deletedMark = "× "; return u } }),
                ("Hidden", { ioUpdateSettings(context: context) { var u = $0; u.deletedMark = ""; return u } })
            ])
        },
        clearSavedDeletedMessages: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: "Clear Saved Deleted Messages",
                text: "Permanently remove all locally preserved deleted messages from this device?",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Clear", action: {
                        let _ = (ioClearAllSavedDeletedMessages(account: context.account)
                        |> deliverOnMainQueue).startStandalone(next: { count in
                            ioShowToast(context: context, present: presentControllerImpl, text: "Removed \(count) saved deleted messages")
                        })
                    })
                ]
            )
            presentControllerImpl?(alert)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [
            ApplicationSpecificSharedDataKeys.ioSettings,
            ApplicationSpecificSharedDataKeys.experimentalUISettings
        ])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.ioSettings]?.get(IOSettings.self) ?? IOSettings.defaultSettings
        let experimental = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings

        let entries: [IOGhostEntry] = [
            .ghostHeader,
            .skipReadHistory(experimental.skipReadHistory),
            .ghostDontSendOnline(settings.ghostDontSendOnline),
            .ghostDontSendTyping(settings.ghostDontSendTyping),
            .sendWithoutSoundMode(settings.sendWithoutSoundMode),
            .ghostMarkReadAfterAction(settings.ghostMarkReadAfterAction),
            .ghostFooter,
            .antiRecallHeader,
            .saveDeletedMessages(settings.saveDeletedMessages),
            .saveMessagesHistory(settings.saveMessagesHistory),
            .saveForBots(settings.saveForBots),
            .semiTransparentDeletedMessages(settings.semiTransparentDeletedMessages),
            .deletedMark(settings.deletedMark),
            .showEditHistoryInMenu(settings.showEditHistoryInMenu),
            .showMessageDetailsInMenu(settings.showMessageDetailsInMenu),
            .showRepeatMessageInMenu(settings.showRepeatMessageInMenu),
            .clearSavedDeletedMessages,
            .disappearingHeader,
            .saveDisappearingMedia(settings.saveDisappearingMedia),
            .disableScreenshotProtection(settings.disableScreenshotProtection),
            .showFlameOnSelfDestruct(settings.showFlameOnSelfDestruct),
            .disappearingFooter
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text("Ghost & Anti-Recall"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                arguments
            )
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    return controller
}

// MARK: - 5. Backup & Restore Preferences

private final class IOBackupArguments {
    let exportConfigFile: () -> Void
    let copyConfigJson: () -> Void
    let importConfigClipboard: () -> Void
    let importConfigFile: () -> Void
    let resetDefaults: () -> Void

    init(
        exportConfigFile: @escaping () -> Void,
        copyConfigJson: @escaping () -> Void,
        importConfigClipboard: @escaping () -> Void,
        importConfigFile: @escaping () -> Void,
        resetDefaults: @escaping () -> Void
    ) {
        self.exportConfigFile = exportConfigFile
        self.copyConfigJson = copyConfigJson
        self.importConfigClipboard = importConfigClipboard
        self.importConfigFile = importConfigFile
        self.resetDefaults = resetDefaults
    }
}

private enum IOBackupSection: Int32 {
    case configs
    case reset
}

private enum IOBackupEntry: ItemListNodeEntry {
    case configsHeader
    case exportConfigFile
    case copyConfigJson
    case importConfigClipboard
    case importConfigFile
    case configsFooter
    case resetDefaults

    var section: ItemListSectionId {
        switch self {
        case .configsHeader, .exportConfigFile, .copyConfigJson, .importConfigClipboard, .importConfigFile, .configsFooter:
            return IOBackupSection.configs.rawValue
        case .resetDefaults:
            return IOBackupSection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .configsHeader: return 0
        case .exportConfigFile: return 1
        case .copyConfigJson: return 2
        case .importConfigClipboard: return 3
        case .importConfigFile: return 4
        case .configsFooter: return 5
        case .resetDefaults: return 20
        }
    }

    static func <(lhs: IOBackupEntry, rhs: IOBackupEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOBackupArguments
        switch self {
        case .configsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "CONFIG BACKUP & RESTORE", sectionId: self.section)
        case .exportConfigFile:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Export Config File (.json)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportConfigFile()
            })
        case .copyConfigJson:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Copy Config JSON", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyConfigJson()
            })
        case .importConfigClipboard:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Import Config from Clipboard", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importConfigClipboard()
            })
        case .importConfigFile:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Import Config File (.json / .extera)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importConfigFile()
            })
        case .configsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Compatible with iOGram JSON and Android exteraGram .extera config backups."), sectionId: self.section)
        case .resetDefaults:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Reset Tweaks to Defaults", kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.resetDefaults()
            })
        }
    }
}

private func ioBackupSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var getControllerViewImpl: (() -> UIView?)?

    let applyImportedConfigData: (Data) -> Void = { data in
        let resultBox = Atomic<Int>(value: -1)
        let _ = (updateIOSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
            if let imported = IOSettings.importConfig(from: data, current: current) {
                let _ = resultBox.swap(imported.updatedKeys)
                return imported.settings
            }
            return current
        })
        |> deliverOnMainQueue).startStandalone(completed: {
            let updatedKeys = resultBox.with { $0 }
            if updatedKeys < 0 {
                ioShowToast(context: context, present: presentControllerImpl, text: "Invalid or unsupported config format")
            } else if updatedKeys == 0 {
                ioShowToast(context: context, present: presentControllerImpl, text: "Config already matches current settings")
            } else {
                ioSetAllowScreenshots(IOSettings.current.disableScreenshotProtection)
                ioShowToast(context: context, present: presentControllerImpl, text: "Imported config (\(updatedKeys) settings updated)")
            }
        })
    }

    let arguments = IOBackupArguments(
        exportConfigFile: {
            guard let data = IOSettings.current.exportConfigJSONData() else {
                ioShowToast(context: context, present: presentControllerImpl, text: "Failed to serialize config")
                return
            }
            let fileUrl = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("iOGram-config.json")
            do {
                try data.write(to: fileUrl, options: [.atomic])
            } catch {
                ioShowToast(context: context, present: presentControllerImpl, text: "Failed to write config file")
                return
            }
            let activityController = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
            if let sourceView = getControllerViewImpl?(), let popover = activityController.popoverPresentationController {
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1.0, height: 1.0)
            }
            context.sharedContext.applicationBindings.presentNativeController(activityController)
        },
        copyConfigJson: {
            guard let data = IOSettings.current.exportConfigJSONData(),
                  let jsonString = String(data: data, encoding: .utf8) else {
                ioShowToast(context: context, present: presentControllerImpl, text: "Failed to serialize config")
                return
            }
            UIPasteboard.general.string = jsonString
            ioShowToast(context: context, present: presentControllerImpl, text: "Config JSON copied to clipboard")
        },
        importConfigClipboard: {
            guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  let data = text.data(using: .utf8) else {
                ioShowToast(context: context, present: presentControllerImpl, text: "Clipboard does not contain config JSON")
                return
            }
            applyImportedConfigData(data)
        },
        importConfigFile: {
            MainActor.assumeIsolated {
                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [UTType.json, UTType.plainText, UTType.data],
                    asCopy: true
                )
                picker.allowsMultipleSelection = false
                let delegate = IOConfigDocumentPickerDelegate(
                    onPick: { url in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessed {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        guard let data = try? Data(contentsOf: url) else {
                            ioShowToast(context: context, present: presentControllerImpl, text: "Could not read selected file")
                            return
                        }
                        applyImportedConfigData(data)
                    },
                    onCancel: {}
                )
                objc_setAssociatedObject(picker, ioDocumentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                picker.delegate = delegate
                context.sharedContext.applicationBindings.presentNativeController(picker)
            }
        },
        resetDefaults: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: "Reset Tweaks",
                text: "Reset all iOGram Preferences and filters back to default values?",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Reset", action: {
                        ioUpdateSettings(context: context) { _ in IOSettings.defaultSettings }
                        ioSetAllowScreenshots(IOSettings.defaultSettings.disableScreenshotProtection)
                        ioShowToast(context: context, present: presentControllerImpl, text: "Tweaks reset to defaults")
                    })
                ]
            )
            presentControllerImpl?(alert)
        }
    )

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let entries: [IOBackupEntry] = [
            .configsHeader,
            .exportConfigFile,
            .copyConfigJson,
            .importConfigClipboard,
            .importConfigFile,
            .configsFooter,
            .resetDefaults
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text("Backup & Restore"),
                leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (
                ItemListNodeState(
                    presentationData: ItemListPresentationData(presentationData),
                    entries: entries,
                    style: .blocks,
                    animateChanges: true
                ),
                arguments
            )
        )
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    getControllerViewImpl = { [weak controller] in return controller?.view }
    return controller
}
