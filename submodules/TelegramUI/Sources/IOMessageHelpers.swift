import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
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

private final class IOEditHistoryArguments {
    let copyText: (String) -> Void

    init(copyText: @escaping (String) -> Void) {
        self.copyText = copyText
    }
}

private enum IOEditHistoryEntry: ItemListNodeEntry {
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

    static func <(lhs: IOEditHistoryEntry, rhs: IOEditHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! IOEditHistoryArguments
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

public func ioMessageEditHistoryController(context: AccountContext, message: EngineMessage) -> ViewController {
    var presentUndoImpl: ((UndoOverlayContent) -> Void)?

    let arguments = IOEditHistoryArguments(copyText: { text in
        UIPasteboard.general.string = text
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentUndoImpl?(.copy(text: presentationData.strings.Conversation_MessageCopied))
    })

    let revisions = (message.attributes.first(where: { $0 is IOEditHistoryMessageAttribute }) as? IOEditHistoryMessageAttribute)?.revisions ?? []

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        var entries: [IOEditHistoryEntry] = []
        var sectionIndex: Int32 = 0

        let currentTime = messageEditedTimestamp(message) ?? message.timestamp
        let currentText = message.text.isEmpty ? "(Media / Empty text)" : message.text
        entries.append(.sectionHeader(sectionIndex, "CURRENT · \(formatFullTimestamp(currentTime))"))
        entries.append(.sectionText(sectionIndex, currentText))
        if !message.text.isEmpty {
            entries.append(.sectionCopy(sectionIndex, message.text))
        }
        sectionIndex += 1

        if revisions.isEmpty {
            entries.append(.sectionHeader(sectionIndex, "PREVIOUS REVISIONS"))
            entries.append(.sectionText(sectionIndex, "Previous versions were not cached locally before this message was edited."))
        } else {
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

private func ioTranslateAndShowAlert(context: AccountContext, text: String, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let targetLang = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
    guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLang)&dt=t&q=\(encoded)") else {
        return
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10.0
    URLSession.shared.dataTask(with: request) { data, _, _ in
        var translated = ""
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
           let sentences = json.first as? [Any] {
            for item in sentences {
                if let pair = item as? [Any], let chunk = pair.first as? String {
                    translated += chunk
                }
            }
        }
        DispatchQueue.main.async {
            let resultText = translated.isEmpty ? "Translation failed. Check your connection." : translated
            let alert = textAlertController(
                context: context,
                title: "Translation (\(targetLang.uppercased()))",
                text: resultText,
                actions: translated.isEmpty
                    ? [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    : [
                        TextAlertAction(type: .genericAction, title: "Copy", action: {
                            UIPasteboard.general.string = translated
                        }),
                        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
                    ]
            )
            present(alert)
        }
    }.resume()
}

public func ioDeletedMessagesController(context: AccountContext, peerId: PeerId?) -> ViewController {
    var presentUndoImpl: ((UndoOverlayContent) -> Void)?

    let arguments = IOEditHistoryArguments(copyText: { text in
        UIPasteboard.general.string = text
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentUndoImpl?(.copy(text: presentationData.strings.Conversation_MessageCopied))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ioLoadSavedDeletedMessages(account: context.account, peerId: peerId)
    )
    |> deliverOnMainQueue
    |> map { presentationData, messages -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        var entries: [IOEditHistoryEntry] = []
        if messages.isEmpty {
            entries.append(.sectionHeader(0, "DELETED MESSAGES"))
            entries.append(.sectionText(0, "No saved deleted messages in this chat yet."))
        } else {
            for (index, message) in messages.prefix(150).enumerated() {
                let sectionIndex = Int32(index)
                let deletedTime = (message.attributes.first(where: { $0 is IODeletedMessageAttribute }) as? IODeletedMessageAttribute)?.deletedTimestamp ?? message.timestamp
                let authorName = message.author?.debugDisplayTitle ?? "Message"
                let mediaTag = message.media.isEmpty ? "" : " · [Media]"
                let header = "\(authorName) · \(formatFullTimestamp(deletedTime))\(mediaTag)"
                let displayText = message.text.isEmpty ? "(Media / Empty text)" : message.text
                entries.append(.sectionHeader(sectionIndex, header))
                entries.append(.sectionText(sectionIndex, displayText))
                if !message.text.isEmpty {
                    entries.append(.sectionCopy(sectionIndex, message.text))
                }
            }
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Deleted Messages"),
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
        guard let controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: content, elevatedLayout: false, action: { _ in return false }), in: .window(.root))
    }
    return controller
}

public func ioPresentMessageDetailsAlert(
    context: AccountContext,
    message: EngineMessage,
    present: @escaping (ViewController, Any?) -> Void
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let settings = IOSettings.current
    let mode: IOSettings.PeerIdDisplayMode = settings.peerIdDisplayMode == .hidden ? .telegramApi : settings.peerIdDisplayMode

    var lines: [String] = []
    lines.append("Message ID: \(message.id.id)")
    if let chatId = IOUtils.formattedPeerId(message.id.peerId, mode: mode) {
        lines.append("Chat ID: \(chatId)")
    }
    if let authorId = message.author?.id, let formattedAuthor = IOUtils.formattedPeerId(authorId, mode: mode) {
        lines.append("Author ID: \(formattedAuthor)")
    }
    lines.append("Sent: \(formatFullTimestamp(message.timestamp))")
    if let editedTime = messageEditedTimestamp(message) {
        lines.append("Edited: \(formatFullTimestamp(editedTime))")
    }
    if let deletedAttr = message.attributes.first(where: { $0 is IODeletedMessageAttribute }) as? IODeletedMessageAttribute {
        lines.append("Deleted: \(formatFullTimestamp(deletedAttr.deletedTimestamp))")
    }
    if let editAttr = message.attributes.first(where: { $0 is IOEditHistoryMessageAttribute }) as? IOEditHistoryMessageAttribute {
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

func ioAppendMessageContextMenuActions(
    actions: inout [ContextMenuItem],
    context: AccountContext,
    message: EngineMessage,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    controllerInteraction: ChatControllerInteraction,
    interfaceInteraction: ChatPanelInterfaceInteraction
) {
    let ioSettings = IOSettings.current
    var extraActions: [ContextMenuItem] = []

    let editAttr = message.attributes.first(where: { $0 is IOEditHistoryMessageAttribute }) as? IOEditHistoryMessageAttribute
    let isEdited = message.attributes.contains(where: { $0 is EditedMessageAttribute })
    if ioSettings.showEditHistoryInMenu, (editAttr != nil || isEdited) {
        let revCount = editAttr?.revisions.count ?? 0
        let title = revCount > 0 ? "Edit History (\(revCount))" : "Edit History"
        extraActions.append(.action(ContextMenuActionItem(text: title, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                controllerInteraction.navigationController()?.pushViewController(ioMessageEditHistoryController(context: context, message: message))
            })
        })))
    }

    if ioSettings.saveDeletedMessages {
        extraActions.append(.action(ContextMenuActionItem(text: "View Deleted", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                controllerInteraction.navigationController()?.pushViewController(ioDeletedMessagesController(context: context, peerId: message.id.peerId))
            })
        })))
    }

    if ioSettings.showTranslateInMenu, !message.text.isEmpty {
        extraActions.append(.action(ContextMenuActionItem(text: "Translate (iO)", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Translate"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                ioTranslateAndShowAlert(context: context, text: message.text, present: { vc in
                    controllerInteraction.presentController(vc, nil)
                })
            })
        })))
    }

    if ioSettings.showRepeatMessageInMenu,
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

    if ioSettings.showMessageDetailsInMenu {
        extraActions.append(.action(ContextMenuActionItem(text: "Message Details", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                ioPresentMessageDetailsAlert(context: context, message: message, present: controllerInteraction.presentController)
            })
        })))
    }

    if message.attributes.contains(where: { $0 is IODeletedMessageAttribute }) {
        extraActions.append(.action(ContextMenuActionItem(text: "Delete Locally", textColor: .destructive, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.actionSheet.destructiveActionTextColor)
        }, action: { c, _ in
            c?.dismiss(completion: {
                let _ = ioPurgeSavedDeletedMessage(account: context.account, messageId: message.id).startStandalone()
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
