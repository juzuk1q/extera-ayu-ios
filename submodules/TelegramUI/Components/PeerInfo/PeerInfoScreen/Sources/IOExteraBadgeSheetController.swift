import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ComponentFlow
import EmojiStatusComponent
import AnimationCache
import MultiAnimationRenderer

final class IOExteraBadgeSheetController: ViewController {
    private let context: AccountContext
    private let peerTitle: String
    private let badge: IOExteraBadgeResolved
    private let isSelf: Bool
    private var presentationData: PresentationData

    private let dimView = UIView()
    private let cardView = UIView()
    private let starsView = UIView()
    private let badgeHostView = ComponentHostView<Empty>()
    private let badgePillView = UIView()
    private let badgePillGradient = CAGradientLayer()
    private let badgePillLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var perkRows: [(icon: UIImageView, title: UILabel, desc: UILabel)] = []
    private let actionButton = UIButton(type: .system)

    init(context: AccountContext, peerTitle: String, badge: IOExteraBadgeResolved, isSelf: Bool, presentationData: PresentationData) {
        self.context = context
        self.peerTitle = peerTitle
        self.badge = badge
        self.isSelf = isSelf
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .Ignore
        self.blocksBackgroundWhenInOverlay = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .clear
        self.displayNodeDidLoad()
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()

        let theme = self.presentationData.theme

        self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.dimView.alpha = 0.0
        self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapped)))
        self.view.addSubview(self.dimView)

        self.cardView.backgroundColor = theme.list.blocksBackgroundColor
        self.cardView.layer.cornerRadius = 22.0
        if #available(iOS 13.0, *) {
            self.cardView.layer.cornerCurve = .continuous
        }
        self.cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.cardView.clipsToBounds = true
        self.view.addSubview(self.cardView)

        self.starsView.isUserInteractionEnabled = false
        self.starsView.clipsToBounds = true
        self.cardView.addSubview(self.starsView)
        self.populateSparkles(color: theme.list.itemAccentColor)

        let _ = self.badgeHostView.update(
            transition: .immediate,
            component: AnyComponent(EmojiStatusComponent(
                context: self.context,
                animationCache: self.context.animationCache,
                animationRenderer: self.context.animationRenderer,
                content: .animation(
                    content: .customEmoji(fileId: self.badge.documentId),
                    size: CGSize(width: 140.0, height: 140.0),
                    placeholderColor: theme.list.mediaPlaceholderColor,
                    themeColor: theme.list.itemAccentColor,
                    loopMode: .forever
                ),
                isVisibleForAnimations: true,
                useSharedAnimation: true,
                action: nil,
                emojiFileUpdated: nil
            )),
            environment: {},
            containerSize: CGSize(width: 88.0, height: 88.0)
        )
        self.cardView.addSubview(self.badgeHostView)

        self.badgePillGradient.colors = [
            UIColor(rgb: 0x57B5FF).cgColor,
            UIColor(rgb: 0x827BFF).cgColor
        ]
        self.badgePillGradient.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.badgePillGradient.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.badgePillView.layer.insertSublayer(self.badgePillGradient, at: 0)
        self.badgePillView.layer.cornerRadius = 13.0
        self.badgePillView.clipsToBounds = true
        self.cardView.addSubview(self.badgePillView)

        self.badgePillLabel.font = Font.semibold(13.0)
        self.badgePillLabel.textColor = .white
        self.badgePillLabel.textAlignment = .center
        if let number = self.badge.number {
            self.badgePillLabel.text = "Arrow Badge #\(number)"
        } else {
            self.badgePillLabel.text = "Arrow Badge"
        }
        self.badgePillView.addSubview(self.badgePillLabel)
        self.badgePillView.isHidden = self.isSelf

        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 0
        if self.isSelf {
            self.titleLabel.font = Font.bold(22.0)
            self.titleLabel.textColor = theme.list.itemPrimaryTextColor
            self.titleLabel.text = "Your Perks"
        } else {
            let full = NSMutableAttributedString(
                string: self.peerTitle,
                attributes: [
                    .font: Font.bold(21.0),
                    .foregroundColor: theme.list.itemAccentColor
                ]
            )
            full.append(NSAttributedString(
                string: " supports exteraGram",
                attributes: [
                    .font: Font.bold(21.0),
                    .foregroundColor: theme.list.itemPrimaryTextColor
                ]
            ))
            self.titleLabel.attributedText = full
        }
        self.cardView.addSubview(self.titleLabel)

        self.subtitleLabel.font = Font.semibold(15.0)
        self.subtitleLabel.textColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.9)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 1
        if self.isSelf, let number = self.badge.number {
            self.subtitleLabel.text = "Badge #\(number) — here's what you get:"
        } else if self.isSelf {
            self.subtitleLabel.text = "Here's what you get:"
        } else {
            self.subtitleLabel.text = "Supporters get these perks:"
        }
        self.cardView.addSubview(self.subtitleLabel)

        let perks: [(String, String, String)] = [
            ("checkmark.seal", "Numbered Badge", "A badge with your number next to your name, visible to everyone on exteraGram."),
            ("headphones", "Now Playing", "Show the track you're playing on Last.fm or stats.fm in your profile."),
            ("calendar", "Registration Dates", "More accurate account creation dates in profiles."),
            ("megaphone", "Early Builds", "A private channel with test versions before they're released.")
        ]

        for (symbol, title, desc) in perks {
            let iconView = UIImageView()
            if #available(iOS 13.0, *) {
                let config = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .regular)
                iconView.image = UIImage(systemName: symbol, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
            }
            iconView.tintColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.85)
            iconView.contentMode = .scaleAspectFit
            self.cardView.addSubview(iconView)

            let titleLbl = UILabel()
            titleLbl.font = Font.semibold(16.0)
            titleLbl.textColor = theme.list.itemPrimaryTextColor
            titleLbl.text = title
            titleLbl.numberOfLines = 1
            self.cardView.addSubview(titleLbl)

            let descLbl = UILabel()
            descLbl.font = Font.regular(14.0)
            descLbl.textColor = theme.list.itemSecondaryTextColor
            descLbl.text = desc
            descLbl.numberOfLines = 0
            self.cardView.addSubview(descLbl)

            self.perkRows.append((iconView, titleLbl, descLbl))
        }

        self.actionButton.backgroundColor = theme.list.itemCheckColors.fillColor
        self.actionButton.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.actionButton.titleLabel?.font = Font.semibold(17.0)
        self.actionButton.setTitle("Got it", for: .normal)
        self.actionButton.layer.cornerRadius = 24.0
        if #available(iOS 13.0, *) {
            self.actionButton.layer.cornerCurve = .continuous
        }
        self.actionButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.cardView.addSubview(self.actionButton)
    }

    private func populateSparkles(color: UIColor) {
        let positions: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.14, 0.22, 10.0, 0.25), (0.23, 0.42, 7.0, 0.20), (0.11, 0.68, 9.0, 0.18),
            (0.30, 0.18, 6.0, 0.22), (0.34, 0.72, 11.0, 0.24), (0.68, 0.19, 8.0, 0.24),
            (0.75, 0.38, 12.0, 0.26), (0.85, 0.28, 7.0, 0.20), (0.82, 0.65, 10.0, 0.22),
            (0.66, 0.74, 8.0, 0.18), (0.20, 0.84, 6.0, 0.16), (0.88, 0.82, 8.0, 0.16)
        ]
        for (rx, ry, size, alpha) in positions {
            let lbl = UILabel()
            lbl.text = "✦"
            lbl.font = UIFont.systemFont(ofSize: size)
            lbl.textColor = color.withAlphaComponent(alpha)
            lbl.tag = Int(rx * 1000) * 1000 + Int(ry * 1000)
            self.starsView.addSubview(lbl)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.animateIn()
    }

    @objc private func dimTapped() {
        self.animateOutAndDismiss()
    }

    @objc private func closePressed() {
        self.animateOutAndDismiss()
    }

    private func animateIn() {
        let cardHeight = self.cardView.bounds.height
        self.cardView.transform = CGAffineTransform(translationX: 0.0, y: max(240.0, cardHeight))
        UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.0, options: [.allowUserInteraction]) {
            self.dimView.alpha = 1.0
            self.cardView.transform = .identity
        }
    }

    private func animateOutAndDismiss() {
        let cardHeight = self.cardView.bounds.height
        UIView.animate(withDuration: 0.22, delay: 0.0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0.0
            self.cardView.transform = CGAffineTransform(translationX: 0.0, y: max(240.0, cardHeight))
        } completion: { [weak self] _ in
            self?.dismiss()
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.dimView.frame = CGRect(origin: .zero, size: layout.size)

        let sideInset: CGFloat = 20.0
        let maxCardWidth = min(layout.size.width, 460.0)
        let innerWidth = maxCardWidth - sideInset * 2.0

        let starsHeight: CGFloat = 156.0
        self.starsView.frame = CGRect(x: 0.0, y: 0.0, width: maxCardWidth, height: starsHeight)
        for subview in self.starsView.subviews {
            let rx = CGFloat(subview.tag / 1000) / 1000.0
            let ry = CGFloat(subview.tag % 1000) / 1000.0
            subview.sizeToFit()
            subview.center = CGPoint(x: maxCardWidth * rx, y: starsHeight * ry)
        }

        var y: CGFloat = 26.0
        let badgeSize = CGSize(width: 88.0, height: 88.0)
        self.badgeHostView.frame = CGRect(x: floor((maxCardWidth - badgeSize.width) / 2.0), y: y, width: badgeSize.width, height: badgeSize.height)
        y += badgeSize.height + 14.0

        if !self.badgePillView.isHidden {
            let pillTextSize = self.badgePillLabel.sizeThatFits(CGSize(width: innerWidth, height: 30.0))
            let pillWidth = min(innerWidth, ceil(pillTextSize.width) + 24.0)
            let pillHeight: CGFloat = 26.0
            self.badgePillView.frame = CGRect(x: floor((maxCardWidth - pillWidth) / 2.0), y: y, width: pillWidth, height: pillHeight)
            self.badgePillGradient.frame = self.badgePillView.bounds
            self.badgePillLabel.frame = self.badgePillView.bounds
            y += pillHeight + 12.0
        }

        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: innerWidth, height: 120.0))
        self.titleLabel.frame = CGRect(x: sideInset, y: y, width: innerWidth, height: ceil(titleSize.height))
        y += ceil(titleSize.height) + 6.0

        let subSize = self.subtitleLabel.sizeThatFits(CGSize(width: innerWidth, height: 40.0))
        self.subtitleLabel.frame = CGRect(x: sideInset, y: y, width: innerWidth, height: ceil(subSize.height))
        y += ceil(subSize.height) + 20.0

        let iconSize: CGFloat = 24.0
        let textX = sideInset + iconSize + 14.0
        let textWidth = innerWidth - iconSize - 14.0
        for row in self.perkRows {
            let tSize = row.title.sizeThatFits(CGSize(width: textWidth, height: 40.0))
            let dSize = row.desc.sizeThatFits(CGSize(width: textWidth, height: 120.0))
            row.icon.frame = CGRect(x: sideInset, y: y + 2.0, width: iconSize, height: iconSize)
            row.title.frame = CGRect(x: textX, y: y, width: textWidth, height: ceil(tSize.height))
            row.desc.frame = CGRect(x: textX, y: y + ceil(tSize.height) + 2.0, width: textWidth, height: ceil(dSize.height))
            y += ceil(tSize.height) + 2.0 + ceil(dSize.height) + 16.0
        }

        y += 4.0
        let buttonHeight: CGFloat = 48.0
        self.actionButton.frame = CGRect(x: sideInset, y: y, width: innerWidth, height: buttonHeight)
        y += buttonHeight + max(16.0, layout.intrinsicInsets.bottom + 12.0)

        let cardX = floor((layout.size.width - maxCardWidth) / 2.0)
        self.cardView.frame = CGRect(x: cardX, y: layout.size.height - y, width: maxCardWidth, height: y)
    }
}
