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

public func ioDeletedMessagesController(context: AccountContext, peerId: EnginePeer.Id?) -> ViewController {
    return IODeletedMessagesViewController(context: context, peerId: peerId)
}

private struct IODeletedBubbleRow {
    enum Kind {
        case datePill(String)
        case message(author: String, initial: String, authorColor: UIColor, text: String, time: String, isIncoming: Bool, showAvatar: Bool, showAuthor: Bool, copyText: String)
    }
    let kind: Kind
}

private final class IODeletedMessagesViewController: ViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let context: AccountContext
    private let peerId: EnginePeer.Id?
    private var presentationData: PresentationData
    private var disposable: Disposable?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchBar = UISearchBar()
    private let emptyLabel = UILabel()
    private var isSearching = false
    private var searchQuery = ""
    private var allRows: [IODeletedBubbleRow] = []
    private var filteredRows: [IODeletedBubbleRow] = []

    init(context: AccountContext, peerId: EnginePeer.Id?) {
        self.context = context
        self.peerId = peerId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.title = "Deleted Messages"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        if #available(iOS 13.0, *) {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(self.toggleSearch))
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(self.toggleSearch))
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()

        let theme = self.presentationData.theme
        self.displayNode.backgroundColor = theme.list.plainBackgroundColor

        self.searchBar.placeholder = "Search deleted messages"
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.isHidden = true
        self.view.addSubview(self.searchBar)

        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.allowsSelection = true
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.contentInset = UIEdgeInsets(top: 8.0, left: 0.0, bottom: 16.0, right: 0.0)
        self.tableView.register(IODeletedDateCell.self, forCellReuseIdentifier: "IODateCell")
        self.tableView.register(IODeletedBubbleCell.self, forCellReuseIdentifier: "IOBubbleCell")
        self.view.addSubview(self.tableView)

        self.emptyLabel.text = "No saved deleted messages yet."
        self.emptyLabel.font = Font.regular(15.0)
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.isHidden = true
        self.view.addSubview(self.emptyLabel)

        if let peerId = self.peerId {
            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
                guard let self, let peer else { return }
                self.title = peer.displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            })
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .medium
        timeFormatter.dateStyle = .none

        let palette: [UIColor] = [
            UIColor(rgb: 0xFF5C5C), UIColor(rgb: 0xFFA24C), UIColor(rgb: 0xB87AFF),
            UIColor(rgb: 0x5CC864), UIColor(rgb: 0x4EC2E0), UIColor(rgb: 0x5A9BFF), UIColor(rgb: 0xFF6B9D)
        ]

        self.disposable = (ioLoadSavedDeletedMessages(account: self.context.account, peerId: self.peerId)
        |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self else { return }
            let sorted = messages.sorted { $0.timestamp < $1.timestamp }
            var built: [IODeletedBubbleRow] = []
            var lastDateKey = ""
            var lastAuthorId: Int64?

            for message in sorted {
                let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
                let dateKey = dateFormatter.string(from: date)
                if dateKey != lastDateKey {
                    built.append(IODeletedBubbleRow(kind: .datePill(dateKey)))
                    lastDateKey = dateKey
                    lastAuthorId = nil
                }

                let authorName = message.author?.debugDisplayTitle ?? (message.flags.contains(.Incoming) ? "User" : "You")
                let initial = String(authorName.prefix(1)).uppercased()
                let rawAuthorId = message.author?.id.id._internalGetInt64Value() ?? 0
                let color = palette[Int(abs(rawAuthorId)) % palette.count]
                let isIncoming = message.flags.contains(.Incoming)
                let showAuthor = isIncoming && rawAuthorId != lastAuthorId
                lastAuthorId = rawAuthorId

                let mediaPrefix = message.media.isEmpty ? "" : (message.text.isEmpty ? "[Media]" : "[Media]\n")
                let bodyText = mediaPrefix + message.text
                let timeText = timeFormatter.string(from: date)

                built.append(IODeletedBubbleRow(kind: .message(
                    author: authorName,
                    initial: initial.isEmpty ? "?" : initial,
                    authorColor: color,
                    text: bodyText,
                    time: timeText,
                    isIncoming: isIncoming,
                    showAvatar: isIncoming,
                    showAuthor: showAuthor,
                    copyText: message.text
                )))
            }

            self.allRows = built
            self.applySearchFilter()
            if !self.filteredRows.isEmpty && !self.isSearching {
                let lastIndex = IndexPath(row: self.filteredRows.count - 1, section: 0)
                self.tableView.scrollToRow(at: lastIndex, at: .bottom, animated: false)
            }
        })
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationBar?.frame.maxY ?? (layout.statusBarHeight ?? 0.0) + 44.0
        let searchHeight: CGFloat = self.isSearching ? 48.0 : 0.0
        self.searchBar.frame = CGRect(x: layout.safeInsets.left, y: topInset, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: searchHeight)
        self.tableView.frame = CGRect(x: layout.safeInsets.left, y: topInset + searchHeight, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: max(0.0, layout.size.height - topInset - searchHeight - layout.intrinsicInsets.bottom))
        self.emptyLabel.frame = CGRect(x: 24.0, y: floor(layout.size.height / 2.0) - 16.0, width: layout.size.width - 48.0, height: 32.0)
    }

    @objc private func toggleSearch() {
        self.isSearching.toggle()
        self.searchBar.isHidden = !self.isSearching
        if !self.isSearching {
            self.searchBar.text = ""
            self.searchBar.resignFirstResponder()
            self.searchQuery = ""
            self.applySearchFilter()
        } else {
            self.searchBar.becomeFirstResponder()
        }
        self.requestLayout(transition: .animated(duration: 0.2, curve: .easeInOut))
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.applySearchFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func applySearchFilter() {
        if self.searchQuery.isEmpty {
            self.filteredRows = self.allRows
        } else {
            self.filteredRows = self.allRows.filter { row in
                switch row.kind {
                case .datePill:
                    return false
                case let .message(author, _, _, text, _, _, _, _, _):
                    return text.lowercased().contains(self.searchQuery) || author.lowercased().contains(self.searchQuery)
                }
            }
        }
        self.emptyLabel.isHidden = !self.filteredRows.isEmpty
        self.tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = self.filteredRows[indexPath.row]
        switch row.kind {
        case let .datePill(title):
            let cell = tableView.dequeueReusableCell(withIdentifier: "IODateCell", for: indexPath) as! IODeletedDateCell
            cell.configure(title: title, theme: self.presentationData.theme)
            return cell
        case let .message(author, initial, authorColor, text, time, isIncoming, showAvatar, showAuthor, _):
            let cell = tableView.dequeueReusableCell(withIdentifier: "IOBubbleCell", for: indexPath) as! IODeletedBubbleCell
            cell.configure(
                author: author,
                initial: initial,
                authorColor: authorColor,
                text: text,
                time: time,
                isIncoming: isIncoming,
                showAvatar: showAvatar,
                showAuthor: showAuthor,
                theme: self.presentationData.theme
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case let .message(_, _, _, _, _, _, _, _, copyText) = self.filteredRows[indexPath.row].kind, !copyText.isEmpty {
            UIPasteboard.general.string = copyText
            self.present(UndoOverlayController(presentationData: self.presentationData, content: .copy(text: self.presentationData.strings.Conversation_MessageCopied), elevatedLayout: false, action: { _ in return false }), in: .window(.root))
        }
    }
}

private final class IODeletedDateCell: UITableViewCell {
    private let pillView = UIView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        self.pillView.layer.cornerRadius = 11.0
        self.label.font = Font.semibold(12.0)
        self.label.textAlignment = .center
        self.pillView.addSubview(self.label)
        self.contentView.addSubview(self.pillView)
        self.pillView.translatesAutoresizingMaskIntoConstraints = false
        self.label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.pillView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.pillView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 8.0),
            self.pillView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -6.0),
            self.label.topAnchor.constraint(equalTo: self.pillView.topAnchor, constant: 4.0),
            self.label.bottomAnchor.constraint(equalTo: self.pillView.bottomAnchor, constant: -4.0),
            self.label.leadingAnchor.constraint(equalTo: self.pillView.leadingAnchor, constant: 12.0),
            self.label.trailingAnchor.constraint(equalTo: self.pillView.trailingAnchor, constant: -12.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, theme: PresentationTheme) {
        self.label.text = title
        self.label.textColor = theme.chat.serviceMessage.components.withDefaultWallpaper.primaryText
        self.pillView.backgroundColor = theme.chat.serviceMessage.components.withDefaultWallpaper.fill
    }
}

private final class IODeletedBubbleCell: UITableViewCell {
    private let avatarView = UIView()
    private let avatarLabel = UILabel()
    private let bubbleView = UIView()
    private let authorLabel = UILabel()
    private let bodyLabel = UILabel()
    private let timeLabel = UILabel()

    private var leadingBubbleConstraint: NSLayoutConstraint!
    private var trailingBubbleConstraint: NSLayoutConstraint!
    private var bodyTopWithAuthor: NSLayoutConstraint!
    private var bodyTopWithoutAuthor: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none

        self.avatarView.layer.cornerRadius = 17.0
        self.avatarView.clipsToBounds = true
        self.avatarLabel.font = Font.semibold(14.0)
        self.avatarLabel.textColor = .white
        self.avatarLabel.textAlignment = .center
        self.avatarView.addSubview(self.avatarLabel)

        self.bubbleView.layer.cornerRadius = 16.0
        if #available(iOS 13.0, *) {
            self.bubbleView.layer.cornerCurve = .continuous
        }

        self.authorLabel.font = Font.semibold(14.0)
        self.bodyLabel.font = Font.regular(15.5)
        self.bodyLabel.numberOfLines = 0
        self.timeLabel.font = Font.regular(11.0)

        self.contentView.addSubview(self.avatarView)
        self.contentView.addSubview(self.bubbleView)
        self.bubbleView.addSubview(self.authorLabel)
        self.bubbleView.addSubview(self.bodyLabel)
        self.bubbleView.addSubview(self.timeLabel)

        for v in [self.avatarView, self.avatarLabel, self.bubbleView, self.authorLabel, self.bodyLabel, self.timeLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        self.leadingBubbleConstraint = self.bubbleView.leadingAnchor.constraint(equalTo: self.avatarView.trailingAnchor, constant: 8.0)
        self.trailingBubbleConstraint = self.bubbleView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12.0)
        self.bodyTopWithAuthor = self.bodyLabel.topAnchor.constraint(equalTo: self.authorLabel.bottomAnchor, constant: 2.0)
        self.bodyTopWithoutAuthor = self.bodyLabel.topAnchor.constraint(equalTo: self.bubbleView.topAnchor, constant: 8.0)

        NSLayoutConstraint.activate([
            self.avatarView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 10.0),
            self.avatarView.bottomAnchor.constraint(equalTo: self.bubbleView.bottomAnchor),
            self.avatarView.widthAnchor.constraint(equalToConstant: 34.0),
            self.avatarView.heightAnchor.constraint(equalToConstant: 34.0),
            self.avatarLabel.centerXAnchor.constraint(equalTo: self.avatarView.centerXAnchor),
            self.avatarLabel.centerYAnchor.constraint(equalTo: self.avatarView.centerYAnchor),

            self.bubbleView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 3.0),
            self.bubbleView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -3.0),
            self.bubbleView.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.76),

            self.authorLabel.topAnchor.constraint(equalTo: self.bubbleView.topAnchor, constant: 8.0),
            self.authorLabel.leadingAnchor.constraint(equalTo: self.bubbleView.leadingAnchor, constant: 12.0),
            self.authorLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.bubbleView.trailingAnchor, constant: -12.0),

            self.bodyLabel.leadingAnchor.constraint(equalTo: self.bubbleView.leadingAnchor, constant: 12.0),
            self.bodyLabel.trailingAnchor.constraint(equalTo: self.bubbleView.trailingAnchor, constant: -12.0),

            self.timeLabel.topAnchor.constraint(equalTo: self.bodyLabel.bottomAnchor, constant: 3.0),
            self.timeLabel.trailingAnchor.constraint(equalTo: self.bubbleView.trailingAnchor, constant: -10.0),
            self.timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: self.bubbleView.leadingAnchor, constant: 12.0),
            self.timeLabel.bottomAnchor.constraint(equalTo: self.bubbleView.bottomAnchor, constant: -6.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(author: String, initial: String, authorColor: UIColor, text: String, time: String, isIncoming: Bool, showAvatar: Bool, showAuthor: Bool, theme: PresentationTheme) {
        self.avatarView.isHidden = !showAvatar
        self.avatarView.backgroundColor = authorColor
        self.avatarLabel.text = initial

        self.authorLabel.isHidden = !showAuthor
        self.authorLabel.text = author
        self.authorLabel.textColor = authorColor

        self.bodyTopWithAuthor.isActive = showAuthor
        self.bodyTopWithoutAuthor.isActive = !showAuthor

        self.bodyLabel.text = text
        self.timeLabel.text = time

        if isIncoming {
            self.trailingBubbleConstraint.isActive = false
            self.leadingBubbleConstraint.isActive = true
            self.bubbleView.backgroundColor = theme.chat.message.incoming.bubble.withDefaultWallpaper.fill.first ?? theme.list.itemBlocksBackgroundColor
            self.bodyLabel.textColor = theme.chat.message.incoming.primaryTextColor
            self.timeLabel.textColor = theme.chat.message.incoming.secondaryTextColor
        } else {
            self.leadingBubbleConstraint.isActive = false
            self.trailingBubbleConstraint.isActive = true
            self.bubbleView.backgroundColor = theme.chat.message.outgoing.bubble.withDefaultWallpaper.fill.first ?? theme.list.itemAccentColor.withAlphaComponent(0.25)
            self.bodyLabel.textColor = theme.chat.message.outgoing.primaryTextColor
            self.timeLabel.textColor = theme.chat.message.outgoing.secondaryTextColor
        }
    }
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
