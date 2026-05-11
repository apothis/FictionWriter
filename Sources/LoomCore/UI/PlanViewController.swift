import AppKit

/// Phase 3 §E — Plan view. NSCollectionView-based card-grid showing
/// scene cards in manuscript order. The first iteration is a flat
/// single-column layout; chapter/part grouping via section headers
/// is a follow-on once the basic flow is exercised.
///
/// HANDOFF §11.4 calls this out as the AppKit-vs-pivot decision
/// gate — NSCollectionView's quirks are the live concern. Smoke
/// tests pin the public surface; rendering is honest UI.
public final class PlanViewController: NSViewController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate
{
    public let session: ProjectSession

    private var collectionView: NSCollectionView!
    private var cards: [PlanSceneCard] = []
    private var sessionObserver: NSObjectProtocol?

    public init(session: ProjectSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        if let o = sessionObserver { NotificationCenter.default.removeObserver(o) }
    }

    @available(*, unavailable) public required init?(coder: NSCoder) { nil }

    public override func loadView() {
        let container = ThemedBackgroundView(backgroundColor: DesignTokens.Background.window)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 320, height: 110)
        layout.sectionInset = NSEdgeInsets(
            top: DesignTokens.Spacing.md,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.md,
            right: DesignTokens.Spacing.md
        )
        layout.minimumInteritemSpacing = DesignTokens.Spacing.md
        layout.minimumLineSpacing = DesignTokens.Spacing.md

        let cv = NSCollectionView()
        cv.collectionViewLayout = layout
        cv.dataSource = self
        cv.delegate = self
        cv.isSelectable = true
        cv.allowsMultipleSelection = false
        cv.backgroundColors = [.clear]
        cv.register(PlanSceneCardItem.self, forItemWithIdentifier: PlanSceneCardItem.identifier)
        self.collectionView = cv
        scroll.documentView = cv

        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container

        cards = PlanViewLayout.build(for: session.project, scenes: session.scenes).cards
        sessionObserver = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    public func reload() {
        cards = PlanViewLayout.build(for: session.project, scenes: session.scenes).cards
        collectionView?.reloadData()
    }

    // MARK: NSCollectionViewDataSource

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        cards.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PlanSceneCardItem.identifier, for: indexPath)
        if let cell = item as? PlanSceneCardItem, indexPath.item < cards.count {
            cell.configure(with: cards[indexPath.item])
        }
        return item
    }

    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let path = indexPaths.first, path.item < cards.count else { return }
        let card = cards[path.item]
        session.selectScene(id: card.sceneId)
    }

    // MARK: Test surface

    public var cardsForTesting: [PlanSceneCard] { cards }

    public func simulateCardClickForTesting(at index: Int) {
        guard index < cards.count else { return }
        session.selectScene(id: cards[index].sceneId)
    }
}

/// NSCollectionViewItem renderer for a single Plan-view scene card.
/// Title (headline), group title (caption), word count + status
/// pill, summary excerpt body.
public final class PlanSceneCardItem: NSCollectionViewItem {
    public static let identifier = NSUserInterfaceItemIdentifier("PlanSceneCard")

    private let cardBackground = ThemedBackgroundView(backgroundColor: DesignTokens.Background.group)
    private let titleLabel = NSTextField(labelWithString: "")
    private let groupLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")

    public override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        cardBackground.translatesAutoresizingMaskIntoConstraints = false
        cardBackground.wantsLayer = true
        cardBackground.layer?.cornerRadius = DesignTokens.Radius.section
        cardBackground.layer?.borderWidth = 0.5
        cardBackground.layer?.borderColor = NSColor.separatorColor.cgColor

        titleLabel.font = DesignTokens.Typography.headline
        titleLabel.textColor = DesignTokens.Foreground.primary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        groupLabel.font = DesignTokens.Typography.caption1
        groupLabel.textColor = DesignTokens.Foreground.tertiary
        groupLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = DesignTokens.Typography.caption1
        metaLabel.textColor = DesignTokens.Foreground.secondary
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = DesignTokens.Typography.body
        summaryLabel.textColor = DesignTokens.Foreground.secondary
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.maximumNumberOfLines = 2

        view.addSubview(cardBackground)
        cardBackground.addSubview(groupLabel)
        cardBackground.addSubview(titleLabel)
        cardBackground.addSubview(metaLabel)
        cardBackground.addSubview(summaryLabel)

        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: view.topAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            groupLabel.topAnchor.constraint(equalTo: cardBackground.topAnchor, constant: DesignTokens.Spacing.sm),
            groupLabel.leadingAnchor.constraint(equalTo: cardBackground.leadingAnchor, constant: DesignTokens.Spacing.sm),
            groupLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardBackground.trailingAnchor, constant: -DesignTokens.Spacing.sm),

            titleLabel.topAnchor.constraint(equalTo: groupLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: cardBackground.leadingAnchor, constant: DesignTokens.Spacing.sm),
            titleLabel.trailingAnchor.constraint(equalTo: metaLabel.leadingAnchor, constant: -DesignTokens.Spacing.sm),

            metaLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: cardBackground.trailingAnchor, constant: -DesignTokens.Spacing.sm),

            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DesignTokens.Spacing.xs),
            summaryLabel.leadingAnchor.constraint(equalTo: cardBackground.leadingAnchor, constant: DesignTokens.Spacing.sm),
            summaryLabel.trailingAnchor.constraint(equalTo: cardBackground.trailingAnchor, constant: -DesignTokens.Spacing.sm),
            summaryLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardBackground.bottomAnchor, constant: -DesignTokens.Spacing.sm),
        ])
    }

    func configure(with card: PlanSceneCard) {
        groupLabel.stringValue = card.groupTitle.uppercased()
        titleLabel.stringValue = card.title.isEmpty ? "Untitled" : card.title
        metaLabel.stringValue = "\(card.wordCount)w · \(card.status.rawValue)"
        summaryLabel.stringValue = card.summary
    }

    public override var isSelected: Bool {
        didSet {
            cardBackground.layer?.borderColor = isSelected
                ? DesignTokens.Foreground.accent.cgColor
                : NSColor.separatorColor.cgColor
            cardBackground.layer?.borderWidth = isSelected ? 1.5 : 0.5
        }
    }
}
