//
//  MangaListCell.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Gifu
import Nuke
import UIKit

class MangaListCell: UICollectionViewCell {
    // row heights used by the collection view layouts that display these cells
    static let rowHeight: CGFloat = 100
    static let compactRowHeight: CGFloat = 56

    private static let coverHeight: CGFloat = 100
    private static let compactCoverHeight: CGFloat = 46

    private var identifier: MangaIdentifier?
    private var url: String?
    private var imageTask: ImageTask?

    private var isEditing = false
    private var hasSubtitle = false
    private var hasTags = false

    /// Shrinks the cell down to a single line of text next to a small cover, separated by a hairline.
    var compact = false {
        didSet {
            guard oldValue != compact else { return }
            applyCompactState()
        }
    }

    var badgeNumber: Int {
        get { badgeView.badgeNumber }
        set {
            badgeView.badgeNumber = newValue
            if newValue > 0 {
                setBadgeVisible(!isEditing)
            } else if badgeNumber2 <= 0 {
                setBadgeVisible(false)
            }
            badgeWidthConstraint?.constant = badgeView.intrinsicContentSize.width
        }
    }
    var badgeNumber2: Int {
        get { badgeView.badgeNumber2 }
        set {
            badgeView.badgeNumber2 = newValue
            if newValue > 0 {
                setBadgeVisible(!isEditing)
            } else if badgeNumber <= 0 {
                setBadgeVisible(false)
            }
            badgeWidthConstraint?.constant = badgeView.intrinsicContentSize.width
        }
    }

    lazy var coverImageView = {
        let imageView = GIFImageView()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 5
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        return imageView
    }()

    private lazy var bookmarkImageView = {
        let bookmarkImageView = UIImageView()
        bookmarkImageView.contentMode = .scaleAspectFit
        return bookmarkImageView
    }()

    private lazy var titleStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        return stackView
    }()

    private lazy var titleLabel = {
        let titleLabel = UILabel()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        return titleLabel
    }()

    private lazy var subtitleLabel  = {
        let subtitleLabel = UILabel()
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.textAlignment = .left
        return subtitleLabel
    }()

    private lazy var tagScrollView = TagScrollView()
    private lazy var selectionView = SelectionCheckView()
    private lazy var badgeView = DoubleBadgeView()

    private lazy var separatorView = {
        let separatorView = UIView()
        separatorView.backgroundColor = .separator
        separatorView.isHidden = true
        return separatorView
    }()

    private var coverLeadingConstraint: NSLayoutConstraint?
    private var coverWidthConstraint: NSLayoutConstraint?
    private var coverHeightConstraint: NSLayoutConstraint?
    private var textLeadingConstraint: NSLayoutConstraint?
    private var textTrailingConstraint: NSLayoutConstraint?
    private var badgeWidthConstraint: NSLayoutConstraint?
    private var bookmarkWidthConstraint: NSLayoutConstraint?
    private var bookmarkHeightConstraint: NSLayoutConstraint?
    private var separatorHeightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        selectionView.isHidden = true // not editing by default

        coverImageView.addSubview(bookmarkImageView)

        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(tagScrollView)

        contentView.addSubview(selectionView)
        contentView.addSubview(coverImageView)
        contentView.addSubview(titleStackView)
        contentView.addSubview(badgeView)
        contentView.addSubview(separatorView)
    }

    func constrain() {
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        coverLeadingConstraint = coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        coverWidthConstraint = coverImageView.widthAnchor.constraint(equalToConstant: Self.coverHeight * 2/3)
        coverHeightConstraint = coverImageView.heightAnchor.constraint(equalToConstant: Self.coverHeight)
        textLeadingConstraint = titleStackView.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12)
        textTrailingConstraint = titleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        badgeWidthConstraint = badgeView.widthAnchor.constraint(equalToConstant: badgeView.intrinsicContentSize.width)
        bookmarkWidthConstraint = bookmarkImageView.widthAnchor.constraint(equalToConstant: 17)
        bookmarkHeightConstraint = bookmarkImageView.heightAnchor.constraint(equalToConstant: 27)
        separatorHeightConstraint = separatorView.heightAnchor.constraint(equalToConstant: hairlineHeight)

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionView.widthAnchor.constraint(equalToConstant: 21),
            selectionView.heightAnchor.constraint(equalToConstant: 21),

            coverLeadingConstraint!,
            coverImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverWidthConstraint!,
            coverHeightConstraint!,

            bookmarkImageView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -8),
            bookmarkImageView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            bookmarkWidthConstraint!,
            bookmarkHeightConstraint!,

            textLeadingConstraint!,
            textTrailingConstraint!,
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            badgeWidthConstraint!,
            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            badgeView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separatorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorHeightConstraint!
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.displayScale != previousTraitCollection?.displayScale {
            separatorHeightConstraint?.constant = hairlineHeight
        }
    }

    private var hairlineHeight: CGFloat {
        1 / max(traitCollection.displayScale, 1)
    }

    private func applyCompactState() {
        let coverHeight = compact ? Self.compactCoverHeight : Self.coverHeight
        coverHeightConstraint?.constant = coverHeight
        // compact covers are square, cropped to the center of the artwork
        coverWidthConstraint?.constant = compact ? coverHeight : coverHeight * 2/3
        coverImageView.layer.cornerRadius = compact ? 3 : 5

        bookmarkWidthConstraint?.constant = compact ? 11 : 17
        bookmarkHeightConstraint?.constant = compact ? 17 : 27

        textLeadingConstraint?.constant = compact ? 10 : 12
        titleLabel.font = if compact {
            // compact rows have a fixed height, so the title can't grow indefinitely
            UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15),
                maximumPointSize: 19
            )
        } else {
            UIFont.preferredFont(forTextStyle: .body)
        }
        titleLabel.numberOfLines = compact ? 1 : 2

        separatorView.isHidden = !compact
        updateDetailVisibility()
    }

    // the subtitle and tags are only shown in the regular layout
    private func updateDetailVisibility() {
        subtitleLabel.isHidden = compact || !hasSubtitle
        tagScrollView.isHidden = compact || !hasTags
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = UIImage(named: "MangaPlaceholder")
        imageTask?.cancel()
        imageTask = nil
        setBadgeVisible(false)
        hasSubtitle = false
        hasTags = false
        updateDetailVisibility()
        alpha = 1
    }

    private func setBadgeVisible(_ visible: Bool) {
        badgeView.isHidden = !visible
        if visible {
            textTrailingConstraint?.isActive = false
            textTrailingConstraint = titleStackView.trailingAnchor.constraint(lessThanOrEqualTo: badgeView.leadingAnchor, constant: -10)
            textTrailingConstraint?.isActive = true
        } else {
            textTrailingConstraint?.isActive = false
            textTrailingConstraint = titleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            textTrailingConstraint?.isActive = true
        }
    }
}

extension MangaListCell {
    func highlight() {
        alpha = 0.5
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? CATransaction.animationDuration() : 0) {
            self.alpha = 1
        }
    }

    func setEditing(_ editing: Bool, animated: Bool = true) {
        guard isEditing != editing else { return }
        isEditing = editing
        if editing {
            selectionView.setSelected(false, animated: false)
        }
        let shouldShowBadge = editing ? false : badgeView.badgeNumber > 0 || badgeView.badgeNumber2 > 0
        let coverOffset: CGFloat = editing ? (compact ? 32 : 40) : 0
        if animated {
            if editing {
                self.selectionView.isHidden = false
            }
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.setBadgeVisible(shouldShowBadge)
                self.coverImageView.alpha = editing ? 0.5 : 1
                self.coverLeadingConstraint?.constant = coverOffset
                self.layoutIfNeeded()
            } completion: { _ in
                if !editing {
                    self.selectionView.isHidden = true
                }
            }
        } else {
            self.setBadgeVisible(shouldShowBadge)
            self.coverImageView.alpha = editing ? 0.5 : 1
            self.coverLeadingConstraint?.constant = coverOffset
            self.selectionView.isHidden = !editing
        }
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        guard isEditing else { return }
        selectionView.setSelected(selected, animated: animated)
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.coverImageView.alpha = selected ? 1 : 0.5
            }
        } else {
            self.coverImageView.alpha = selected ? 1 : 0.5
        }
    }
}

extension MangaListCell {
    func configure(with manga: AidokuRunner.Manga, isBookmarked: Bool = false) {
        identifier = MangaIdentifier(sourceKey: manga.sourceKey, mangaKey: manga.key)
        titleLabel.text = manga.title
        subtitleLabel.text = manga.authors?.joined(separator: ", ")
        hasSubtitle = !(subtitleLabel.text?.isEmpty ?? true)
        bookmarkImageView.image = isBookmarked ? UIImage(systemName: "bookmark.fill") : nil

        if let tags = manga.tags, !tags.isEmpty {
            tagScrollView.tags = tags
            hasTags = true
        } else {
            hasTags = false
        }
        updateDetailVisibility()

        Task {
            await loadImage(url: manga.cover.flatMap { URL(string: $0) })
        }
    }

    func configure(with info: MangaInfo) {
        identifier = MangaIdentifier(sourceKey: info.sourceId, mangaKey: info.mangaId)
        titleLabel.text = info.title
        subtitleLabel.text = info.author
        hasSubtitle = !(subtitleLabel.text?.isEmpty ?? true)
        updateDetailVisibility()

        Task {
            await loadImage(url: info.coverUrl)
        }
    }
}

extension MangaListCell {
    private func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.coverImageView.stopAnimatingGIF()

        var urlRequest = URLRequest(url: url)
        var cached = ImagePipeline.shared.cache.containsCachedImage(for: .init(urlRequest: urlRequest))

        if !cached {
            if let fileUrl = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: fileUrl)
            } else if let sourceId = identifier?.sourceKey {
                // ensure sources are loaded so we can get the modified image request
                await SourceManager.shared.waitForSourcesLoad()
                if let source = SourceManager.shared.source(for: sourceId) {
                    urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
                }
            }
        }

        self.url = (urlRequest.url ?? url).absoluteString

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        cached = cached || ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageID != self.url {
                        return
                    }
                    Task { @MainActor in
                        if cached {
                            self.coverImageView.image = response.image
                        } else {
                            UIView.transition(
                                with: self.coverImageView,
                                duration: CATransaction.animationDuration(),
                                options: .transitionCrossDissolve
                            ) {
                                self.coverImageView.image = response.image
                            }
                        }
                        if response.container.type == .gif, let data = response.container.data {
                            self.coverImageView.animate(withGIFData: data)
                        }
                    }
                case .failure(let error):
                    imageTask = nil
                    guard let identifier else { return }
                    Task { @MainActor [weak self] in
                        guard
                            let newUrl = await CoverRecovery.recover(from: error, identifier: identifier),
                            self?.identifier == identifier
                        else { return }
                        await self?.loadImage(url: newUrl)
                    }
            }
        }
    }
}

private class TagScrollView: UIView {
    var tags: [String] = [] {
        didSet {
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for text in tags {
                let labelView = TagLabelView(text: text)
                labelView.isUserInteractionEnabled = false
                stackView.addArrangedSubview(labelView)
            }
        }
    }

    private let stackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .leading
        return stackView
    }()

    private lazy var scrollView = {
        let scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        return scrollView
    }()

    private let fadeView = {
        let fadeView = FadeView()
        fadeView.isUserInteractionEnabled = false
        return fadeView
    }()

    override var intrinsicContentSize: CGSize {
        stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        scrollView.addSubview(stackView)
        addSubview(scrollView)
        addSubview(fadeView)
    }

    func constrain() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: 32)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stackView.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        updateFadeVisibility()
    }

    private func updateFadeVisibility() {
        let maxOffset = scrollView.contentSize.width - scrollView.bounds.width
        let isAtEnd = scrollView.contentOffset.x >= maxOffset - 1
        fadeView.isHidden = isAtEnd || maxOffset <= 0
    }
}

extension TagScrollView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeVisibility()
    }
}

private class FadeView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            configure()
        }
    }

    func configure() {
        guard let gradient = self.layer as? CAGradientLayer else { return }
        let backgroundColor = UIColor.systemBackground.resolvedColor(with: self.traitCollection)
        gradient.colors = [
            backgroundColor.withAlphaComponent(0).cgColor,
            backgroundColor.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }
}

private class TagLabelView: UIView {
    private lazy var label = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    init(text: String) {
        super.init(frame: .zero)
        label.text = text
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 6
        layer.masksToBounds = true

        addSubview(label)
    }

    func constrain() {
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}
