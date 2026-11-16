import CoreGraphics

nonisolated struct SwitcherLayout: Equatable, Sendable {
    let columns: Int
    let thumbnail: CGSize
    let card: CGSize
    let gridHeight: CGFloat
    let isScrollable: Bool
    let panelSize: CGSize
}

nonisolated enum SwitcherMetrics {
    static let minThumbnailWidth: CGFloat = 160

    static let cardPadding: CGFloat = 8
    static let captionSpacing: CGFloat = 8
    static let captionHeight: CGFloat = 30

    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let gridHorizontalPadding: CGFloat = 16
    static let gridVerticalPadding: CGFloat = 8

    static let panelCornerRadius: CGFloat = 28
    static let cardCornerRadius: CGFloat = 18
    static let thumbnailCornerRadius: CGFloat = cardCornerRadius - cardPadding

    static let headerControlHeight: CGFloat = 32
    static let headerHeight: CGFloat = 14 + headerControlHeight + 8
    static let bannerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 36

    static let screenMargin: CGFloat = 40
    static let minPanelWidth: CGFloat = 640

    static let helpSize = CGSize(width: 560, height: 600)
    static let previewSize = CGSize(width: 960, height: 700)
    static let previewImageSize = CGSize(width: 920, height: 560)

    private static let cardChromeHeight = captionSpacing + captionHeight + cardPadding * 2

    static func card(around thumbnail: CGSize) -> CGSize {
        CGSize(width: thumbnail.width + cardPadding * 2, height: thumbnail.height + cardChromeHeight)
    }

    static func contentWidth(columns: Int, card: CGSize) -> CGFloat {
        let gaps = CGFloat(max(0, columns - 1)) * columnSpacing
        return CGFloat(columns) * card.width + gaps + gridHorizontalPadding * 2
    }

    static func gridHeight(rows: Int, card: CGSize) -> CGFloat {
        let gaps = CGFloat(max(0, rows - 1)) * rowSpacing
        return CGFloat(rows) * card.height + gaps + gridVerticalPadding * 2
    }

    static func rowCount(items: Int, columns: Int) -> Int {
        let columns = max(1, columns)
        return max(1, (items + columns - 1) / columns)
    }

    static func preferredColumns(items: Int) -> Int {
        switch items {
        case ...4: max(1, items)
        case ...8: (items + 1) / 2
        default: .max
        }
    }

    static func chromeHeight(showsBanner: Bool) -> CGFloat {
        headerHeight + footerHeight + (showsBanner ? bannerHeight : 0)
    }

    static func layout(items: Int, maxThumbnail: CGSize, showsBanner: Bool, available: CGSize) -> SwitcherLayout {
        let count = max(1, items)
        let aspect = maxThumbnail.width / maxThumbnail.height
        let chrome = chromeHeight(showsBanner: showsBanner)
        let gridAvailable = available.height - chrome
        let floor = min(minThumbnailWidth, maxThumbnail.width)

        var columns = 1
        var thumbnailWidth: CGFloat = 0
        for candidate in 1...count {
            let rows = CGFloat(rowCount(items: count, columns: candidate))
            let spanX = available.width - gridHorizontalPadding * 2 - CGFloat(candidate - 1) * columnSpacing
            let spanY = gridAvailable - gridVerticalPadding * 2 - (rows - 1) * rowSpacing
            let byWidth = spanX / CGFloat(candidate) - cardPadding * 2
            let byHeight = (spanY / rows - cardChromeHeight) * aspect
            let width = min(maxThumbnail.width, byWidth, byHeight).rounded(.down)

            let isLarger = width > thumbnailWidth + 0.5
            let isTiePreferringMoreColumns = abs(width - thumbnailWidth) <= 0.5 && candidate <= preferredColumns(items: count)
            if isLarger || isTiePreferringMoreColumns {
                columns = candidate
                thumbnailWidth = width
            }
            if byWidth < floor { break }
        }

        if thumbnailWidth < floor {
            thumbnailWidth = floor
            let fitting = (available.width - gridHorizontalPadding * 2 + columnSpacing) / (floor + cardPadding * 2 + columnSpacing)
            columns = max(1, min(count, Int(fitting)))
        }

        let thumbnail = CGSize(width: thumbnailWidth, height: (thumbnailWidth / aspect).rounded(.down))
        let card = card(around: thumbnail)
        let fullHeight = gridHeight(rows: rowCount(items: count, columns: columns), card: card)
        let grid = max(gridHeight(rows: 1, card: card), min(fullHeight, gridAvailable))
        let width = min(available.width, max(minPanelWidth, contentWidth(columns: columns, card: card)))

        return SwitcherLayout(
            columns: columns,
            thumbnail: thumbnail,
            card: card,
            gridHeight: grid.rounded(.up),
            isScrollable: fullHeight > grid + 0.5,
            panelSize: CGSize(width: width.rounded(), height: (grid + chrome).rounded(.up))
        )
    }
}
