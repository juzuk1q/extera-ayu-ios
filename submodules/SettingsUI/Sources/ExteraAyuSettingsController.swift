import Foundation
import UIKit
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

private final class ExteraAyuSettingsControllerArguments {
    let updateSettings: (@escaping (ExteraAyuSettings) -> ExteraAyuSettings) -> Void
    let toggleSkipReadHistory: (Bool) -> Void
    let cyclePeerIdDisplayMode: () -> Void
    let cycleDeletedMark: () -> Void
    let openFilters: () -> Void
    let clearSavedDeletedMessages: () -> Void
    let resetDefaults: () -> Void

    init(
        updateSettings: @escaping (@escaping (ExteraAyuSettings) -> ExteraAyuSettings) -> Void,
        toggleSkipReadHistory: @escaping (Bool) -> Void,
        cyclePeerIdDisplayMode: @escaping () -> Void,
        cycleDeletedMark: @escaping () -> Void,
        openFilters: @escaping () -> Void,
        clearSavedDeletedMessages: @escaping () -> Void,
        resetDefaults: @escaping () -> Void
    ) {
        self.updateSettings = updateSettings
        self.toggleSkipReadHistory = toggleSkipReadHistory
        self.cyclePeerIdDisplayMode = cyclePeerIdDisplayMode
        self.cycleDeletedMark = cycleDeletedMark
        self.openFilters = openFilters
        self.clearSavedDeletedMessages = clearSavedDeletedMessages
        self.resetDefaults = resetDefaults
    }
}

private enum ExteraAyuSettingsSection: Int32 {
    case antiRecall
    case ghostMode
    case appearance
    case reactions
    case chats
    case filters
    case local
    case reset
}

private enum ExteraAyuSettingsEntry: ItemListNodeEntry {
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
    case antiRecallFooter

    case ghostHeader
    case skipReadHistory(Bool)
    case ghostDontSendOnline(Bool)
    case ghostDontSendTyping(Bool)
    case ghostSendWithoutSound(Bool)
    case ghostMarkReadAfterAction(Bool)
    case ghostFooter

    case appearanceHeader
    case hideStories(Bool)
    case removeMessageTail(Bool)
    case showMessageSeconds(Bool)
    case disableNumberRounding(Bool)
    case hideAllChatsFolder(Bool)
    case disableAds(Bool)
    case hidePhoneNumber(Bool)
    case peerIdDisplayMode(ExteraAyuSettings.PeerIdDisplayMode)
    case appearanceFooter

    case reactionsHeader
    case hideReactionsInPrivateChats(Bool)
    case hideReactionsInGroups(Bool)
    case hideReactionsInChannels(Bool)

    case chatsHeader
    case disableOpenLinkWarning(Bool)
    case confirmSendingStickers(Bool)
    case confirmSendingGif(Bool)
    case filterZalgo(Bool)
    case disableGreetingSticker(Bool)

    case filtersHeader
    case openFilters(Int, Int)
    case filtersFooter

    case localHeader
    case localPremium(Bool)
    case localFooter

    case resetDefaults

    var section: ItemListSectionId {
        switch self {
        case .antiRecallHeader, .saveDeletedMessages, .saveMessagesHistory, .saveForBots, .semiTransparentDeletedMessages, .deletedMark, .showEditHistoryInMenu, .showMessageDetailsInMenu, .showRepeatMessageInMenu, .clearSavedDeletedMessages, .antiRecallFooter:
            return ExteraAyuSettingsSection.antiRecall.rawValue
        case .ghostHeader, .skipReadHistory, .ghostDontSendOnline, .ghostDontSendTyping, .ghostSendWithoutSound, .ghostMarkReadAfterAction, .ghostFooter:
            return ExteraAyuSettingsSection.ghostMode.rawValue
        case .appearanceHeader, .hideStories, .removeMessageTail, .showMessageSeconds, .disableNumberRounding, .hideAllChatsFolder, .disableAds, .hidePhoneNumber, .peerIdDisplayMode, .appearanceFooter:
            return ExteraAyuSettingsSection.appearance.rawValue
        case .reactionsHeader, .hideReactionsInPrivateChats, .hideReactionsInGroups, .hideReactionsInChannels:
            return ExteraAyuSettingsSection.reactions.rawValue
        case .chatsHeader, .disableOpenLinkWarning, .confirmSendingStickers, .confirmSendingGif, .filterZalgo, .disableGreetingSticker:
            return ExteraAyuSettingsSection.chats.rawValue
        case .filtersHeader, .openFilters, .filtersFooter:
            return ExteraAyuSettingsSection.filters.rawValue
        case .localHeader, .localPremium, .localFooter:
            return ExteraAyuSettingsSection.local.rawValue
        case .resetDefaults:
            return ExteraAyuSettingsSection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .antiRecallHeader: return 0
        case .saveDeletedMessages: return 1
        case .saveMessagesHistory: return 2
        case .saveForBots: return 3
        case .semiTransparentDeletedMessages: return 4
        case .deletedMark: return 5
        case .showEditHistoryInMenu: return 6
        case .showMessageDetailsInMenu: return 7
        case .showRepeatMessageInMenu: return 8
        case .clearSavedDeletedMessages: return 9
        case .antiRecallFooter: return 10

        case .ghostHeader: return 100
        case .skipReadHistory: return 101
        case .ghostDontSendOnline: return 102
        case .ghostDontSendTyping: return 103
        case .ghostSendWithoutSound: return 104
        case .ghostMarkReadAfterAction: return 105
        case .ghostFooter: return 106

        case .appearanceHeader: return 200
        case .hideStories: return 201
        case .removeMessageTail: return 202
        case .showMessageSeconds: return 203
        case .disableNumberRounding: return 204
        case .hideAllChatsFolder: return 205
        case .disableAds: return 206
        case .hidePhoneNumber: return 207
        case .peerIdDisplayMode: return 208
        case .appearanceFooter: return 209

        case .reactionsHeader: return 300
        case .hideReactionsInPrivateChats: return 301
        case .hideReactionsInGroups: return 302
        case .hideReactionsInChannels: return 303

        case .chatsHeader: return 400
        case .disableOpenLinkWarning: return 401
        case .confirmSendingStickers: return 402
        case .confirmSendingGif: return 403
        case .filterZalgo: return 404
        case .disableGreetingSticker: return 405

        case .filtersHeader: return 500
        case .openFilters: return 501
        case .filtersFooter: return 502

        case .localHeader: return 600
        case .localPremium: return 601
        case .localFooter: return 602

        case .resetDefaults: return 700
        }
    }

    static func <(lhs: ExteraAyuSettingsEntry, rhs: ExteraAyuSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ExteraAyuSettingsControllerArguments
        switch self {
        case .antiRecallHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ANTI-RECALL & HISTORY", sectionId: self.section)
        case let .saveDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Deleted Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.saveDeletedMessages = value
                    return updated
                }
            })
        case let .saveMessagesHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Edit History", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.saveMessagesHistory = value
                    return updated
                }
            })
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save Deleted Bot Messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.saveForBots = value
                    return updated
                }
            })
        case let .semiTransparentDeletedMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Semi-Transparent Deleted", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.semiTransparentDeletedMessages = value
                    return updated
                }
            })
        case let .deletedMark(mark):
            let display = mark.trimmingCharacters(in: .whitespaces)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Deleted Mark", label: display.isEmpty ? "Hidden" : display, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.cycleDeletedMark()
            })
        case let .showEditHistoryInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Edit History in Context Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.showEditHistoryInMenu = value
                    return updated
                }
            })
        case let .showMessageDetailsInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Message Details in Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.showMessageDetailsInMenu = value
                    return updated
                }
            })
        case let .showRepeatMessageInMenu(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Repeat Message in Menu", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.showRepeatMessageInMenu = value
                    return updated
                }
            })
        case .clearSavedDeletedMessages:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Clear Saved Deleted Messages", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearSavedDeletedMessages()
            })
        case .antiRecallFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Preserves messages deleted by others and records previous versions when messages are edited."), sectionId: self.section)

        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "GHOST MODE", sectionId: self.section)
        case let .skipReadHistory(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Read Messages & Stories", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleSkipReadHistory(value)
            })
        case let .ghostDontSendOnline(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Send Online Status", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.ghostDontSendOnline = value
                    return updated
                }
            })
        case let .ghostDontSendTyping(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Don't Send Typing & Upload", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.ghostDontSendTyping = value
                    return updated
                }
            })
        case let .ghostSendWithoutSound(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Always Send Without Sound", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.ghostSendWithoutSound = value
                    return updated
                }
            })
        case let .ghostMarkReadAfterAction(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Mark Read After Sending", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.ghostMarkReadAfterAction = value
                    return updated
                }
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Prevents sending read receipts, online packets, and typing indicators."), sectionId: self.section)

        case .appearanceHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "APPEARANCE & UI", sectionId: self.section)
        case let .hideStories(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Stories Bar", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideStories = value
                    return updated
                }
            })
        case let .removeMessageTail(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Remove Bubble Tails", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.removeMessageTail = value
                    return updated
                }
            })
        case let .showMessageSeconds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show Seconds in Timestamps", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.showMessageSeconds = value
                    return updated
                }
            })
        case let .disableNumberRounding(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Number Rounding (1.2K)", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.disableNumberRounding = value
                    return updated
                }
            })
        case let .hideAllChatsFolder(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide \"All Chats\" Tab", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideAllChatsFolder = value
                    return updated
                }
            })
        case let .disableAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Sponsored Ads", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.disableAds = value
                    return updated
                }
            })
        case let .hidePhoneNumber(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Phone Number", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hidePhoneNumber = value
                    return updated
                }
            })
        case let .peerIdDisplayMode(mode):
            let label: String
            switch mode {
            case .hidden:
                label = "Hidden"
            case .telegramApi:
                label = "Telegram API"
            case .botApi:
                label = "Bot API (-100...)"
            }
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Show Peer ID & DC", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: {
                arguments.cyclePeerIdDisplayMode()
            })
        case .appearanceFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Changing \"Remove Bubble Tails\" takes full effect after switching theme or reopening the app."), sectionId: self.section)

        case .reactionsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "HIDE REACTIONS", sectionId: self.section)
        case let .hideReactionsInPrivateChats(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Private Chats", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideReactionsInPrivateChats = value
                    return updated
                }
            })
        case let .hideReactionsInGroups(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Groups", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideReactionsInGroups = value
                    return updated
                }
            })
        case let .hideReactionsInChannels(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide in Channels", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideReactionsInChannels = value
                    return updated
                }
            })

        case .chatsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "CHATS & CONFIRMATIONS", sectionId: self.section)
        case let .disableOpenLinkWarning(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable External Link Warning", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.disableOpenLinkWarning = value
                    return updated
                }
            })
        case let .confirmSendingStickers(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending Stickers", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.confirmSendingStickers = value
                    return updated
                }
            })
        case let .confirmSendingGif(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Confirm Sending GIFs", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.confirmSendingGif = value
                    return updated
                }
            })
        case let .filterZalgo(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Filter Zalgo Text", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.filterZalgo = value
                    return updated
                }
            })
        case let .disableGreetingSticker(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Disable Greeting Sticker", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.disableGreetingSticker = value
                    return updated
                }
            })

        case .filtersHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "FILTERS & ANTI-SPAM", sectionId: self.section)
        case let .openFilters(keywordCount, peerCount):
            let total = keywordCount + peerCount
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Message Filters & Shadow-Ban", label: total == 0 ? "Off" : "\(total)", sectionId: self.section, style: .blocks, action: {
                arguments.openFilters()
            })
        case .filtersFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Hide messages by keywords, /regex/ patterns, blocked senders, or shadow-banned Peer IDs."), sectionId: self.section)

        case .localHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "LOCAL PREMIUM", sectionId: self.section)
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Local Telegram Premium", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.localPremium = value
                    return updated
                }
            })
        case .localFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Local Premium unlocks client-side UI features only; server-side limits remain enforced by Telegram."), sectionId: self.section)

        case .resetDefaults:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Reset Tweaks to Defaults", kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.resetDefaults()
            })
        }
    }
}

private func exteraAyuSettingsControllerEntries(
    settings: ExteraAyuSettings,
    experimentalUISettings: ExperimentalUISettings
) -> [ExteraAyuSettingsEntry] {
    var entries: [ExteraAyuSettingsEntry] = []

    entries.append(.antiRecallHeader)
    entries.append(.saveDeletedMessages(settings.saveDeletedMessages))
    entries.append(.saveMessagesHistory(settings.saveMessagesHistory))
    entries.append(.saveForBots(settings.saveForBots))
    entries.append(.semiTransparentDeletedMessages(settings.semiTransparentDeletedMessages))
    entries.append(.deletedMark(settings.deletedMark))
    entries.append(.showEditHistoryInMenu(settings.showEditHistoryInMenu))
    entries.append(.showMessageDetailsInMenu(settings.showMessageDetailsInMenu))
    entries.append(.showRepeatMessageInMenu(settings.showRepeatMessageInMenu))
    entries.append(.clearSavedDeletedMessages)
    entries.append(.antiRecallFooter)

    entries.append(.ghostHeader)
    entries.append(.skipReadHistory(experimentalUISettings.skipReadHistory))
    entries.append(.ghostDontSendOnline(settings.ghostDontSendOnline))
    entries.append(.ghostDontSendTyping(settings.ghostDontSendTyping))
    entries.append(.ghostSendWithoutSound(settings.ghostSendWithoutSound))
    entries.append(.ghostMarkReadAfterAction(settings.ghostMarkReadAfterAction))
    entries.append(.ghostFooter)

    entries.append(.appearanceHeader)
    entries.append(.hideStories(settings.hideStories))
    entries.append(.removeMessageTail(settings.removeMessageTail))
    entries.append(.showMessageSeconds(settings.showMessageSeconds))
    entries.append(.disableNumberRounding(settings.disableNumberRounding))
    entries.append(.hideAllChatsFolder(settings.hideAllChatsFolder))
    entries.append(.disableAds(settings.disableAds))
    entries.append(.hidePhoneNumber(settings.hidePhoneNumber))
    entries.append(.peerIdDisplayMode(settings.peerIdDisplayMode))
    entries.append(.appearanceFooter)

    entries.append(.reactionsHeader)
    entries.append(.hideReactionsInPrivateChats(settings.hideReactionsInPrivateChats))
    entries.append(.hideReactionsInGroups(settings.hideReactionsInGroups))
    entries.append(.hideReactionsInChannels(settings.hideReactionsInChannels))

    entries.append(.chatsHeader)
    entries.append(.disableOpenLinkWarning(settings.disableOpenLinkWarning))
    entries.append(.confirmSendingStickers(settings.confirmSendingStickers))
    entries.append(.confirmSendingGif(settings.confirmSendingGif))
    entries.append(.filterZalgo(settings.filterZalgo))
    entries.append(.disableGreetingSticker(settings.disableGreetingSticker))

    entries.append(.filtersHeader)
    entries.append(.openFilters(settings.blockedKeywords.count, settings.shadowBannedPeerIds.count))
    entries.append(.filtersFooter)

    entries.append(.localHeader)
    entries.append(.localPremium(settings.localPremium))
    entries.append(.localFooter)

    entries.append(.resetDefaults)

    return entries
}

public func exteraAyuSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = ExteraAyuSettingsControllerArguments(
        updateSettings: { f in
            let _ = updateExteraAyuSettingsInteractively(accountManager: context.sharedContext.accountManager, f).start()
        },
        toggleSkipReadHistory: { value in
            let _ = (context.sharedContext.accountManager.transaction { transaction -> Void in
                transaction.updateSharedData(ApplicationSpecificSharedDataKeys.experimentalUISettings, { entry in
                    var settings = entry?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
                    settings.skipReadHistory = value
                    return SharedPreferencesEntry(settings)
                })
            }).start()
        },
        cyclePeerIdDisplayMode: {
            let _ = updateExteraAyuSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                switch current.peerIdDisplayMode {
                case .hidden:
                    updated.peerIdDisplayMode = .telegramApi
                case .telegramApi:
                    updated.peerIdDisplayMode = .botApi
                case .botApi:
                    updated.peerIdDisplayMode = .hidden
                }
                return updated
            }).start()
        },
        cycleDeletedMark: {
            let marks = ["🗑 ", "deleted · ", "× ", ""]
            let _ = updateExteraAyuSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                if let index = marks.firstIndex(of: current.deletedMark) {
                    updated.deletedMark = marks[(index + 1) % marks.count]
                } else {
                    updated.deletedMark = marks[0]
                }
                return updated
            }).start()
        },
        openFilters: {
            pushControllerImpl?(exteraAyuFiltersController(context: context))
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
                        let _ = (exteraAyuClearAllSavedDeletedMessages(account: context.account)
                        |> deliverOnMainQueue).startStandalone(next: { count in
                            let undo = UndoOverlayController(
                                presentationData: presentationData,
                                content: .info(title: nil, text: "Removed \(count) saved deleted messages", timeout: nil, customUndoText: nil),
                                elevatedLayout: false,
                                action: { _ in return false }
                            )
                            presentControllerImpl?(undo)
                        })
                    })
                ]
            )
            presentControllerImpl?(alert)
        },
        resetDefaults: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                title: "Reset Tweaks",
                text: "Reset all ExteraAyu tweaks and filters back to default values?",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Reset", action: {
                        let _ = updateExteraAyuSettingsInteractively(accountManager: context.sharedContext.accountManager, { _ in
                            return ExteraAyuSettings.defaultSettings
                        }).start()
                        let undo = UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Tweaks reset to defaults", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                        presentControllerImpl?(undo)
                    })
                ]
            )
            presentControllerImpl?(alert)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [
            ApplicationSpecificSharedDataKeys.exteraAyuSettings,
            ApplicationSpecificSharedDataKeys.experimentalUISettings
        ])
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.exteraAyuSettings]?.get(ExteraAyuSettings.self) ?? ExteraAyuSettings.defaultSettings
        let experimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("ExteraAyu Tweaks"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: exteraAyuSettingsControllerEntries(settings: settings, experimentalUISettings: experimentalUISettings),
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
