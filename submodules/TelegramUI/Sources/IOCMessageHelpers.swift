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
import AppBundle
import ContextUI
import ChatPresentationInterfaceState
import ChatControllerInteraction

private final class IOCEditHistoryArguments {
    let copyText: (String) -> Void

    init(copyText: @escaping (String) -> Void) {
        self.copyText = copyText
    }
}

private enum IOCEditHistoryEntry: ItemListNodeEntry {
    case sectionHeader(Int32, String)
    case sectionText(Int32, String)
    case sectionCopy(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .sectionHeader(sectionIndex, _),
             let .sectionText(sectionIndex, _),
             let .sectionCopy(sectionIndex, _):
            return sectionIndex
        }
    }

    var stableId: Int32 {
        switch self {
        case let .sectionHeader(sectionIndex, _):
            return sectionIndex * 10 + 0
        case let .sectionText(sectionIndex, _):
            return sectionIndex * 10 + 1
        case let .sectionCopy(sectionIndex, _):
            return sectionIndex * 10 + 2
        }
    }

    static func <(lhs: IOCEditHistoryEntry, rhs: IOCEditHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOCEditHistoryArguments
        switch self {
        case let .sectionHeader(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .sectionText(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .sectionCopy(_, text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Copy Version", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.copyText(text)
            })
        }
    }
}

private func messageEditedTimestamp(_ message: EngineMessage) -> Int32? {
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
            return attribute.date
        }
    }
    return nil
}

private func formatFullTimestamp(_ timestamp: Int32) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

public func iocMessageEditHistoryController(context: AccountContext, message: EngineMessage) -> ViewController {
    var presentUndoImpl: ((UndoOverlayContent) -> Void)?

    let arguments = IOCEditHistoryArguments(copyText: { text in
        UIPasteboard.general.string = text
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentUndoImpl?(.copy(text: presentationData.strings.Conversation_MessageCopied))
    })

    let revisions = (message.attributes.first(where: { $0 is IOCEditHistoryMessageAttribute }) as? IOCEditHistoryMessageAttribute)?.revisions ?? []

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        var entries: [IOCEditHistoryEntry] = []
        var sectionIndex: Int32 = 0

        let currentTime = messageEditedTimestamp(message) ?? message.timestamp
        let currentText = message.text.isEmpty ? "(Media / Empty text)" : message.text
        entries.append(.sectionHeader(sectionIndex, "CURRENT · \(formatFullTimestamp(currentTime))"))
        entries.append(.sectionText(sectionIndex, currentText))
        if !message.text.isEmpty {
            entries.append(.sectionCopy(sectionIndex, message.text))
        }
        sectionIndex += 1

        for revision in revisions.reversed() {
            let mediaTag = revision.hasMedia ? " · [Media]" : ""
            let header = "REVISION #\(revisions.count - Int(sectionIndex) + 1) · \(formatFullTimestamp(revision.timestamp))\(mediaTag)"
            let displayText = revision.text.isEmpty ? "(Empty text)" : revision.text
            entries.append(.sectionHeader(sectionIndex, header))
            entries.append(.sectionText(sectionIndex, displayText))
            if !revision.text.isEmpty {
                entries.append(.sectionCopy(sectionIndex, revision.text))
            }
            sectionIndex += 1
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Edit History"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentUndoImpl = { [weak controller] content in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: content, elevatedLayout: false, action: { _ in return false }), in: .window(.root))
    }
    return controller
}

public func iocPresentMessageDetailsAlert(
    context: AccountContext,
    message: EngineMessage,
    present: @escaping (ViewController, Any?) -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let settings = IOCSettings.current
    let mode: IOCSettings.PeerIdDisplayMode = settings.peerIdDisplayMode == .hidden ? .telegramApi : settings.peerIdDisplayMode

    var lines: [String] = []
    lines.append("Message ID: \(message.id.id)")
    if let chatId = IOCUtils.formattedPeerId(message.id.peerId, mode: mode) {
        lines.append("Chat ID: \(chatId)")
    }
    if let authorId = message.author?.id, let formattedAuthor = IOCUtils.formattedPeerId(authorId, mode: mode) {
        lines.append("Author ID: \(formattedAuthor)")
    }
    lines.append("Sent: \(formatFullTimestamp(message.timestamp))")
    if let editedTime = messageEditedTimestamp(message) {
        lines.append("Edited: \(formatFullTimestamp(editedTime))")
    }
    if let deletedAttr = message.attributes.first(where: { $0 is IOCDeletedMessageAttribute }) as? IOCDeletedMessageAttribute {
        lines.append("Deleted: \(formatFullTimestamp(deletedAttr.deletedTimestamp))")
    }
    if let editAttr = message.attributes.first(where: { $0 is IOCEditHistoryMessageAttribute }) as? IOCEditHistoryMessageAttribute {
        lines.append("Saved Revisions: \(editAttr.revisions.count)")
    }
    let detailsText = lines.joined(separator: "\n")

    let alert = textAlertController(
        context: context,
        title: "Message Details",
        text: detailsText,
        actions: [
            TextAlertAction(type: .genericAction, title: "Copy Info", action: {
                UIPasteboard.general.string = detailsText
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]
    )
    present(alert, nil)
}

func iocAppendMessageContextMenuActions(
    actions: inout [ContextMenuItem],
    context: AccountContext,
    message: EngineMessage,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    controllerInteraction: ChatControllerInteraction,
    interfaceInteraction: ChatPanelInterfaceInteraction
) {
    let iocSettings = IOCSettings.current
    var extraActions: [ContextMenuItem] = []

    if iocSettings.showEditHistoryInMenu, let editAttr = message.attributes.first(where: { $0 is IOCEditHistoryMessageAttribute }) as? IOCEditHistoryMessageAttribute, !editAttr.revisions.isEmpty {
        extraActions.append(.action(ContextMenuActionItem(text: "Edit History (\(editAttr.revisions.count))", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                controllerInteraction.navigationController()?.pushViewController(iocMessageEditHistoryController(context: context, message: message))
            })
        })))
    }

    if iocSettings.showRepeatMessageInMenu,
       !chatPresentationInterfaceState.copyProtectionEnabled,
       !message._asMessage().containsSecretMedia,
       !message.engineMedia.contains(where: { $0._asMedia() is TelegramMediaAction || $0._asMedia() is TelegramMediaExpiredContent }),
       canSendMessagesToChat(chatPresentationInterfaceState),
       (!message.text.isEmpty || !message.engineMedia.isEmpty) {
        extraActions.append(.action(ContextMenuActionItem(text: "Repeat", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                let entitiesAttribute = message.attributes.first(where: { $0 is TextEntitiesMessageAttribute })
                let repeatedAttributes: [EngineMessage.Attribute] = entitiesAttribute.map { [$0] } ?? []
                let mediaRef = message.engineMedia.first.map { AnyMediaReference.message(message: MessageReference(message._asMessage()), media: $0._asMedia()) }
                let enqueue = EnqueueMessage.message(
                    text: message.text,
                    attributes: repeatedAttributes,
                    inlineStickers: [:],
                    mediaReference: mediaRef,
                    threadId: chatPresentationInterfaceState.chatLocation.threadId,
                    replyToMessageId: nil,
                    replyToStoryId: nil,
                    localGroupingKey: nil,
                    correlationId: nil,
                    bubbleUpEmojiOrStickersets: []
                )
                if let chatController = interfaceInteraction.chatController() as? ChatControllerImpl {
                    chatController.sendMessages([enqueue])
                } else {
                    let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [enqueue]).startStandalone()
                }
            })
        })))
    }

    if iocSettings.showMessageDetailsInMenu {
        extraActions.append(.action(ContextMenuActionItem(text: "Message Details", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                iocPresentMessageDetailsAlert(context: context, message: message, present: controllerInteraction.presentController)
            })
        })))
    }

    if message.attributes.contains(where: { $0 is IOCDeletedMessageAttribute }) {
        extraActions.append(.action(ContextMenuActionItem(text: "Delete Locally", textColor: .destructive, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                let _ = iocPurgeSavedDeletedMessage(account: context.account, messageId: message.id).startStandalone()
            })
        })))
    }

    if !extraActions.isEmpty {
        if !actions.isEmpty {
            actions.append(.separator)
        }
        actions.append(contentsOf: extraActions)
    }
}
