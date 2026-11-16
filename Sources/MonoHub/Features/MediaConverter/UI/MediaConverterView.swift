import SwiftUI
import AppKit

enum MediaStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case pending
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return localized("All")
        case .pending: return localized("Pending")
        case .completed: return localized("Completed")
        case .failed: return localized("Failed")
        }
    }
}

struct MediaConverterView: View {
    @Bindable private var queue = ConversionQueueManager.shared
    @State private var searchText = ""
    @State private var statusFilter: MediaStatusFilter = .all
    @State private var isDropTargeted = false
    @State private var isSettingsExpanded = false

    init() {}

    private var activeItems: [MediaItem] {
        let items = queue.items(for: queue.selectedTab)
        let filteredByStatus: [MediaItem]
        switch statusFilter {
        case .all:
            filteredByStatus = items
        case .pending:
            filteredByStatus = items.filter {
                if case .pending = $0.status { return true }
                return false
            }
        case .completed:
            filteredByStatus = items.filter {
                if case .completed = $0.status { return true }
                return false
            }
        case .failed:
            filteredByStatus = items.filter {
                switch $0.status {
                case .failed, .cancelled: return true
                default: return false
                }
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return filteredByStatus }
        return filteredByStatus.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HubMetrics.sectionSpacing) {

                headerBanner

                modeSelectorBar

                settingsSection

                if queue.currentTabItems.isEmpty {
                    emptyDropZone
                } else {
                    queueListSection
                }
            }
            .padding(HubMetrics.pagePadding)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !queue.currentTabItems.isEmpty {
                pinnedActionBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarActionsMenu

                AccordionExpandToolbarButton(allExpanded: isSettingsExpanded) {
                    isSettingsExpanded.toggle()
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: localized("Filter media by name…"))
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                let prevVideos = queue.items(for: .videos).count
                let prevImages = queue.items(for: .images).count

                await queue.addFiles(urls: urls, expectedKind: nil)

                let addedVideos = queue.items(for: .videos).count - prevVideos
                let addedImages = queue.items(for: .images).count - prevImages

                if addedImages > 0 && addedVideos == 0 {
                    withAnimation(.snappy(duration: 0.2)) {
                        queue.selectedTab = .images
                    }
                } else if addedVideos > 0 && addedImages == 0 {
                    withAnimation(.snappy(duration: 0.2)) {
                        queue.selectedTab = .videos
                    }
                }
            }
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var headerBanner: some View {
        let isVideo = queue.selectedTab == .videos
        let accentColor: Color = isVideo ? .indigo : .teal

        return HubPageHeader(
            title: localized("Media Converter"),
            subtitle: localized("Hardware-accelerated conversion and compression (Apple Silicon ARM64)"),
            systemImage: "arrow.triangle.2.circlepath",
            tint: accentColor
        ) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                Text(localized("Apple Silicon Media Engine"))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(accentColor.opacity(0.12))
            )
            .foregroundStyle(accentColor)
        }
    }

    private var modeSelectorBar: some View {
        HStack(spacing: 12) {
            Picker(localized("Mode"), selection: $queue.selectedTab) {
                Label {
                    Text(localized("Videos (%d)", queue.items(for: .videos).count))
                } icon: {
                    Image(systemName: "film.stack")
                }
                .tag(MediaConverterTab.videos)

                Label {
                    Text(localized("Images (%d)", queue.items(for: .images).count))
                } icon: {
                    Image(systemName: "photo.stack")
                }
                .tag(MediaConverterTab.images)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(maxWidth: 380)

            Spacer()

            destinationLocationSelector
        }
    }

    private var toolbarActionsMenu: some View {
        Menu {
            Button {
                queue.openFilePicker(for: queue.selectedTab)
            } label: {
                Label(localized("Add Files…"), systemImage: "doc.badge.plus")
            }

            Button {
                queue.openFolderPicker(for: queue.selectedTab)
            } label: {
                Label(localized("Add Folder…"), systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                queue.chooseCustomOutputFolder()
            } label: {
                Label(localized("Choose Output Folder…"), systemImage: "folder")
            }

            if queue.completedCount(for: queue.selectedTab) > 0 {
                Divider()
                Button {
                    queue.clearCompleted(for: queue.selectedTab)
                } label: {
                    Label(localized("Clear Completed"), systemImage: "checkmark.circle")
                }
            }

            if !queue.currentTabItems.isEmpty {
                Button(role: .destructive) {
                    queue.clearAll(for: queue.selectedTab)
                } label: {
                    Label(localized("Clear Queue"), systemImage: "trash")
                }
            }
        } label: {
            Label(localized("Add Media"), systemImage: "plus")
        }
        .help(localized("Add media files or folders to queue"))
    }

    private var settingsSection: some View {
        let isVideo = queue.selectedTab == .videos
        let badge = isVideo
            ? "\(queue.defaultVideoPreset.badgeText)\(queue.defaultFastStart ? " • +faststart" : "")"
            : "\(queue.defaultImageFormat.shortName)\(queue.defaultImageFormat != .png && queue.defaultImageFormat != .tiff ? " • \(Int(queue.defaultImageQuality * 100))%" : "")"

        return HubAccordionSection(
            title: isVideo ? localized("Video Profile & Settings") : localized("Image Format & Settings"),
            subtitle: isVideo ? queue.defaultVideoPreset.subtitle : queue.defaultImageFormat.subtitle,
            badgeText: badge,
            badgeColor: isVideo ? .indigo : .teal,
            systemImage: isVideo ? "film.stack.fill" : "photo.stack.fill",
            tint: isVideo ? .indigo : .teal,
            isExpanded: $isSettingsExpanded
        ) {
            if isVideo {
                videoSettingsContent
            } else {
                imageSettingsContent
            }
        }
    }

    private var videoSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text(localized("Profile:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(localized("Profile"), selection: $queue.defaultVideoPreset) {
                            ForEach(VideoPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 340)

                        Text(queue.defaultVideoPreset.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text(localized("Options:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(localized("Fast Start (+faststart)"), isOn: $queue.defaultFastStart)
                            .font(.callout)

                        Text(localized("Optimizes the MP4 header so videos begin playing instantly in browsers without waiting for full download."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text(localized("Save to:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    destinationLocationSelector
                }
            }
        }
        .padding(.top, 4)
    }

    private var imageSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text(localized("Format:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(localized("Format"), selection: $queue.defaultImageFormat) {
                            ForEach(ImageFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)

                        Text(queue.defaultImageFormat.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if queue.defaultImageFormat != .png && queue.defaultImageFormat != .tiff {
                    GridRow {
                        Text(localized("Quality:"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Slider(value: $queue.defaultImageQuality, in: 0.1...1.0, step: 0.05)
                                .frame(maxWidth: 220)

                            Text("\(Int(queue.defaultImageQuality * 100))%")
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .frame(width: 44, alignment: .leading)

                            HStack(spacing: 4) {
                                Button(localized("Maximum (95%)")) { queue.defaultImageQuality = 0.95 }
                                    .controlSize(.mini)
                                Button(localized("Balanced (80%)")) { queue.defaultImageQuality = 0.80 }
                                    .controlSize(.mini)
                                Button(localized("Compact (60%)")) { queue.defaultImageQuality = 0.60 }
                                    .controlSize(.mini)
                            }
                        }
                    }
                }

                GridRow {
                    Text(localized("Privacy:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(localized("Strip EXIF and GPS metadata"), isOn: $queue.defaultStripEXIF)
                            .font(.callout)

                        Text(localized("Removes camera serial, location coordinates, and metadata while preserving image pixels."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text(localized("Resolution:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(localized("Resolution"), selection: $queue.defaultMaxDimensionPreset) {
                        ForEach(MaxDimensionPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }

                GridRow {
                    Text(localized("Save to:"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)

                    destinationLocationSelector
                }
            }
        }
        .padding(.top, 4)
    }

    private var destinationLocationSelector: some View {
        HStack(spacing: 8) {
            Picker(localized("Destination"), selection: $queue.locationMode) {
                ForEach(OutputLocationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()

            if queue.locationMode == .customFolder {
                Button {
                    queue.chooseCustomOutputFolder()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(queue.customOutputFolder?.lastPathComponent ?? localized("Choose…"))
                            .lineLimit(1)
                    }
                }
                .controlSize(.small)

                if let folder = queue.customOutputFolder {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .help(localized("Reveal in Finder"))
                }
            }
        }
    }

    private var emptyDropZone: some View {
        let isVideo = queue.selectedTab == .videos
        let accentColor: Color = isVideo ? .indigo : .teal

        return ContentUnavailableView {
            Label {
                Text(isVideo ? localized("No Videos in Queue") : localized("No Images in Queue"))
                    .font(.title2.weight(.bold))
            } icon: {
                Image(systemName: isVideo ? "film.stack.fill" : "photo.stack.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(accentColor.gradient)
            }
        } description: {
            VStack(spacing: 12) {
                Text(isVideo
                    ? localized("Drag and drop video files or folders to convert and compress with zero quality loss.")
                    : localized("Drag and drop images or folders to convert and optimize using ImageIO.")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

                HStack(spacing: 6) {
                    let formats = isVideo
                        ? ["MP4", "MOV", "MKV", "WebM", "HEVC", "ProRes", "M4V", "AVI"]
                        : ["HEIC", "AVIF", "WebP", "JPEG", "PNG", "TIFF", "GIF"]

                    ForEach(formats, id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } actions: {
            HStack(spacing: 12) {
                Button {
                    queue.openFilePicker(for: queue.selectedTab)
                } label: {
                    Label(localized("Select Files…"), systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .controlSize(.regular)

                Button {
                    queue.openFolderPicker(for: queue.selectedTab)
                } label: {
                    Label(localized("Select Folder…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280)
        .background(
            RoundedRectangle(cornerRadius: HubMetrics.cardCornerRadius, style: .continuous)
                .fill(isDropTargeted ? accentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HubMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [7])
                )
        )
        .padding(.vertical, 8)
    }

    private var queueListSection: some View {
        let tab = queue.selectedTab
        let items = activeItems
        let allTabItems = queue.items(for: tab)
        let completed = queue.completedCount(for: tab)
        let pending = queue.pendingCount(for: tab)

        return VStack(alignment: .leading, spacing: HubMetrics.itemSpacing) {

            HStack(spacing: 8) {

                HStack(spacing: 4) {
                    ForEach(MediaStatusFilter.allCases) { filter in
                        let count: Int = {
                            switch filter {
                            case .all: return allTabItems.count
                            case .pending: return pending
                            case .completed: return completed
                            case .failed:
                                return allTabItems.filter {
                                    if case .failed = $0.status { return true }
                                    if case .cancelled = $0.status { return true }
                                    return false
                                }.count
                            }
                        }()

                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                statusFilter = filter
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filter.title)
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(statusFilter == filter ? Color.primary.opacity(0.16) : Color.secondary.opacity(0.12), in: Capsule())
                            }
                            .font(.system(size: 11.5, weight: statusFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusFilter == filter ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(statusFilter == filter ? Color.primary : Color.secondary)
                    }
                }

                Spacer()

                Button {
                    queue.openFilePicker(for: tab)
                } label: {
                    Label(localized("Add Files…"), systemImage: "plus")
                }
                .controlSize(.small)

                if completed > 0 {
                    Button(localized("Clear Completed")) {
                        queue.clearCompleted(for: tab)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }

                Button(localized("Clear All")) {
                    queue.clearAll(for: tab)
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }

            if items.isEmpty {
                VStack(spacing: 8) {
                    Text(localized("No media matching criteria."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        MediaItemRowView(item: item) {
                            queue.remove(id: item.id)
                        } onRetry: {
                            queue.retry(id: item.id)
                        }
                    }
                }
            }
        }
    }

    private var pinnedActionBar: some View {
        let tab = queue.selectedTab
        let isVideo = tab == .videos
        let pending = queue.pendingCount(for: tab)
        let saved = queue.savedBytes(for: tab)
        let savingsPct = queue.savingsPercentage(for: tab)
        let origBytes = queue.originalBytes(for: tab)
        let itemsCount = queue.items(for: tab).count
        let completed = queue.completedCount(for: tab)

        return VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 16) {

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isVideo ? localized("Videos in Queue (%d)", itemsCount) : localized("Images in Queue (%d)", itemsCount))
                            .font(.system(size: 13, weight: .semibold))

                        if completed > 0 {
                            Text(localized("• %d processed", completed))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if saved > 0 {
                        HStack(spacing: 4) {
                            Text(localized("Space saved:"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Formatting.bytes(saved))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                            Text(String(format: "(-%.1f%%)", savingsPct))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text(localized("Total size: %@", Formatting.bytes(origBytes)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(queue.locationMode == .sameFolder ? localized("Same source folder") : (queue.customOutputFolder?.lastPathComponent ?? localized("Custom folder…")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1), in: Capsule())

                Spacer()

                HStack(spacing: 10) {
                    if queue.isConverting {
                        Button(localized("Cancel")) {
                            queue.cancelAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    Button {
                        if pending > 0 {
                            queue.startConversion(for: tab)
                        } else if completed > 0 {
                            queue.reconvertAll(for: tab)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if queue.isConverting {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localized("Processing…"))
                            } else {
                                if pending > 0 {
                                    Image(systemName: "bolt.fill")
                                    Text(isVideo ? localized("Convert %d Videos", pending) : localized("Compress %d Images", pending))
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                    Text(localized("Reconvert All"))
                                }
                            }
                        }
                        .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isVideo ? Color.indigo : Color.teal)
                    .controlSize(.large)
                    .disabled(itemsCount == 0 || (pending == 0 && completed == 0 && !queue.isConverting))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, HubMetrics.pagePadding)
            .padding(.vertical, 12)
            .hubFloatingBar()
        }
    }
}

private struct MediaItemRowView: View {
    @Bindable var item: MediaItem
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            fileIconThumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(item.originalExtension.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(Formatting.bytes(item.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let meta = item.metadata {
                        if !meta.resolutionDescription.isEmpty {
                            Text("• \(meta.resolutionDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !meta.durationDescription.isEmpty {
                            Text("• \(meta.durationDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !meta.videoCodec.isEmpty {
                            Text("• \(meta.videoCodec)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            targetProfileSelector

            statusView

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(localized("Remove from Queue"))
        }
        .hubCard(cornerRadius: 10, padding: 10)
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            } label: {
                Label(localized("Reveal Original in Finder"), systemImage: "folder")
            }

            Button {
                NSWorkspace.shared.open(item.fileURL)
            } label: {
                Label(localized("Open Original File"), systemImage: "arrow.up.right.square")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.fileURL.path, forType: .string)
            } label: {
                Label(localized("Copy File Path"), systemImage: "doc.on.doc")
            }

            Divider()

            if case .completed(let result) = item.status {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Label(localized("Reveal Converted File in Finder"), systemImage: "magnifyingglass")
                }

                Button {
                    NSWorkspace.shared.open(result.outputURL)
                } label: {
                    Label(localized("Open Converted File"), systemImage: "play.circle")
                }

                Divider()
            }

            if case .failed = item.status {
                Button {
                    onRetry()
                } label: {
                    Label(localized("Retry"), systemImage: "arrow.clockwise")
                }

                Divider()
            }

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label(localized("Remove from Queue"), systemImage: "trash")
            }
        }
    }

    private var fileIconThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)

            Image(systemName: item.kind == .video ? "film.fill" : "photo.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .padding(2.5)
                .background(item.kind.tintColor, in: Circle())
                .offset(x: 2, y: 2)
        }
        .frame(width: 36, height: 36)
    }

    private var targetProfileSelector: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            switch item.kind {
            case .video:
                Menu {
                    ForEach(VideoPreset.allCases) { preset in
                        Button {
                            item.videoOptions.preset = preset
                            item.isCustomized = true
                        } label: {
                            if item.videoOptions.preset == preset {
                                Label(preset.title, systemImage: "checkmark")
                            } else {
                                Text(preset.title)
                            }
                        }
                    }
                } label: {
                    StatusBadge(item.videoOptions.preset.badgeText, color: .indigo)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(localized("Change Preset"))

            case .image:
                Menu {
                    ForEach(ImageFormat.allCases) { format in
                        Button {
                            item.imageOptions.format = format
                            item.isCustomized = true
                        } label: {
                            if item.imageOptions.format == format {
                                Label(format.title, systemImage: "checkmark")
                            } else {
                                Text(format.title)
                            }
                        }
                    }
                } label: {
                    StatusBadge(item.imageOptions.format.shortName, color: .teal)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(localized("Change Preset"))
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending:
            StatusBadge(localized("Waiting"), icon: "hourglass", color: .secondary)

        case .converting(let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .frame(width: 70)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

        case .completed(let result):
            HStack(spacing: 6) {
                StatusBadge(result.savingsText, icon: "arrow.down.right", color: .green)

                Text(Formatting.bytes(result.convertedSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localized("Reveal in Finder"))

                Button {
                    NSWorkspace.shared.open(result.outputURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localized("Open Converted File"))
            }

        case .failed(let error):
            HStack(spacing: 6) {
                StatusBadge(localized("Failed"), icon: "exclamationmark.triangle.fill", color: .red)

                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localized("Retry"))
            }
            .help(error)

        case .cancelled:
            HStack(spacing: 6) {
                StatusBadge(localized("Cancelled"), icon: "xmark.circle", color: .orange)

                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localized("Retry"))
            }
        }
    }
}
