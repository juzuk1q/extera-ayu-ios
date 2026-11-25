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

private struct IOCFiltersState: Equatable {
    var pendingKeyword: String = ""
    var pendingPeerId: String = ""
}

private final class IOCFiltersControllerArguments {
    let updateState: ((IOCFiltersState) -> IOCFiltersState) -> Void
    let updateSettings: (@escaping (IOCSettings) -> IOCSettings) -> Void
    let addKeyword: () -> Void
    let removeKeyword: (Int) -> Void
    let addShadowBanPeerId: () -> Void
    let removeShadowBanPeerId: (Int) -> Void

    init(
        updateState: @escaping ((IOCFiltersState) -> IOCFiltersState) -> Void,
        updateSettings: @escaping (@escaping (IOCSettings) -> IOCSettings) -> Void,
        addKeyword: @escaping () -> Void,
        removeKeyword: @escaping (Int) -> Void,
        addShadowBanPeerId: @escaping () -> Void,
        removeShadowBanPeerId: @escaping (Int) -> Void
    ) {
        self.updateState = updateState
        self.updateSettings = updateSettings
        self.addKeyword = addKeyword
        self.removeKeyword = removeKeyword
        self.addShadowBanPeerId = addShadowBanPeerId
        self.removeShadowBanPeerId = removeShadowBanPeerId
    }
}

private enum IOCFiltersSection: Int32 {
    case general
    case keywords
    case shadowBan
}

private enum IOCFiltersEntry: ItemListNodeEntry {
    case generalHeader
    case filtersEnabled(Bool)
    case filtersEnabledInChats(Bool)
    case hideFromBlocked(Bool)

    case keywordsHeader
    case keywordInput(String)
    case addKeyword(Bool)
    case keywordItem(Int, String)
    case keywordsFooter

    case shadowBanHeader
    case shadowBanInput(String)
    case addShadowBan(Bool)
    case shadowBanItem(Int, Int64)
    case shadowBanFooter

    var section: ItemListSectionId {
        switch self {
        case .generalHeader, .filtersEnabled, .filtersEnabledInChats, .hideFromBlocked:
            return IOCFiltersSection.general.rawValue
        case .keywordsHeader, .keywordInput, .addKeyword, .keywordItem, .keywordsFooter:
            return IOCFiltersSection.keywords.rawValue
        case .shadowBanHeader, .shadowBanInput, .addShadowBan, .shadowBanItem, .shadowBanFooter:
            return IOCFiltersSection.shadowBan.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .generalHeader: return 0
        case .filtersEnabled: return 1
        case .filtersEnabledInChats: return 2
        case .hideFromBlocked: return 3

        case .keywordsHeader: return 100
        case .keywordInput: return 101
        case .addKeyword: return 102
        case let .keywordItem(index, _): return 103 + Int32(index)
        case .keywordsFooter: return 999

        case .shadowBanHeader: return 1000
        case .shadowBanInput: return 1001
        case .addShadowBan: return 1002
        case let .shadowBanItem(index, _): return 1003 + Int32(index)
        case .shadowBanFooter: return 1999
        }
    }

    static func <(lhs: IOCFiltersEntry, rhs: IOCFiltersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOCFiltersControllerArguments
        switch self {
        case .generalHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "FILTER OPTIONS", sectionId: self.section)
        case let .filtersEnabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Enable Filters", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.filtersEnabled = value
                    return updated
                }
            })
        case let .filtersEnabledInChats(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Filter in Groups & Chats", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.filtersEnabledInChats = value
                    return updated
                }
            })
        case let .hideFromBlocked(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Hide Blocked Users in Groups", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSettings { current in
                    var updated = current
                    updated.hideFromBlocked = value
                    return updated
                }
            })

        case .keywordsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "KEYWORD & REGEX FILTERS", sectionId: self.section)
        case let .keywordInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Word or /regex/", type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, sectionId: self.section, textUpdated: { value in
                arguments.updateState { current in
                    var state = current
                    state.pendingKeyword = value
                    return state
                }
            }, action: {
                arguments.addKeyword()
            })
        case let .addKeyword(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Add Keyword Filter", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addKeyword()
            })
        case let .keywordItem(index, keyword):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: keyword, label: "Remove", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.removeKeyword(index)
            })
        case .keywordsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Messages matching any keyword (case-insensitive) or /regex/ will be hidden. Tap an item to remove it."), sectionId: self.section)

        case .shadowBanHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "SHADOW-BAN PEER IDS", sectionId: self.section)
        case let .shadowBanInput(text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: "Telegram User/Channel ID (e.g. 123456789)", type: .number, returnKeyType: .done, sectionId: self.section, textUpdated: { value in
                arguments.updateState { current in
                    var state = current
                    state.pendingPeerId = value
                    return state
                }
            }, action: {
                arguments.addShadowBanPeerId()
            })
        case let .addShadowBan(enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Add Shadow-Banned Peer ID", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addShadowBanPeerId()
            })
        case let .shadowBanItem(index, peerId):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "\(peerId)", label: "Remove", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.removeShadowBanPeerId(index)
            })
        case .shadowBanFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Messages from shadow-banned Peer IDs (and forwards from them) are hidden in groups and chats."), sectionId: self.section)
        }
    }
}

private func iocFiltersControllerEntries(
    settings: IOCSettings,
    state: IOCFiltersState
) -> [IOCFiltersEntry] {
    var entries: [IOCFiltersEntry] = []

    entries.append(.generalHeader)
    entries.append(.filtersEnabled(settings.filtersEnabled))
    entries.append(.filtersEnabledInChats(settings.filtersEnabledInChats))
    entries.append(.hideFromBlocked(settings.hideFromBlocked))

    entries.append(.keywordsHeader)
    entries.append(.keywordInput(state.pendingKeyword))
    entries.append(.addKeyword(!state.pendingKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    for (index, keyword) in settings.blockedKeywords.enumerated() {
        entries.append(.keywordItem(index, keyword))
    }
    entries.append(.keywordsFooter)

    entries.append(.shadowBanHeader)
    entries.append(.shadowBanInput(state.pendingPeerId))
    let parsedPeerId = Int64(state.pendingPeerId.trimmingCharacters(in: .whitespacesAndNewlines))
    entries.append(.addShadowBan(parsedPeerId != nil))
    for (index, peerId) in settings.shadowBannedPeerIds.enumerated() {
        entries.append(.shadowBanItem(index, peerId))
    }
    entries.append(.shadowBanFooter)

    return entries
}

public func iocFiltersController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(IOCFiltersState(), ignoreRepeated: true)
    let stateValue = Atomic(value: IOCFiltersState())
    let updateState: ((IOCFiltersState) -> IOCFiltersState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let arguments = IOCFiltersControllerArguments(
        updateState: updateState,
        updateSettings: { f in
            let _ = updateIOCSettingsInteractively(accountManager: context.sharedContext.accountManager, f).start()
        },
        addKeyword: {
            let trimmed = stateValue.with { $0.pendingKeyword }.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            updateState { current in
                var state = current
                state.pendingKeyword = ""
                return state
            }
            let _ = updateIOCSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                if !updated.blockedKeywords.contains(trimmed) {
                    updated.blockedKeywords.append(trimmed)
                }
                return updated
            }).start()
        },
        removeKeyword: { index in
            let _ = updateIOCSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                if index >= 0 && index < updated.blockedKeywords.count {
                    updated.blockedKeywords.remove(at: index)
                }
                return updated
            }).start()
        },
        addShadowBanPeerId: {
            let trimmed = stateValue.with { $0.pendingPeerId }.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let peerId = Int64(trimmed) else {
                return
            }
            updateState { current in
                var state = current
                state.pendingPeerId = ""
                return state
            }
            let _ = updateIOCSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                if !updated.shadowBannedPeerIds.contains(peerId) {
                    updated.shadowBannedPeerIds.append(peerId)
                }
                return updated
            }).start()
        },
        removeShadowBanPeerId: { index in
            let _ = updateIOCSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                if index >= 0 && index < updated.shadowBannedPeerIds.count {
                    updated.shadowBannedPeerIds.remove(at: index)
                }
                return updated
            }).start()
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.iocSettings]),
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, sharedData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.iocSettings]?.get(IOCSettings.self) ?? IOCSettings.defaultSettings

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Filters & Shadow-Ban"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: iocFiltersControllerEntries(settings: settings, state: state),
            style: .blocks,
            animateChanges: true
        )

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
