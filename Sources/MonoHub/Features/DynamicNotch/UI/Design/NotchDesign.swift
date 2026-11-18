import SwiftUI
import AppKit

enum NotchTheme {

    static let expand = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let collapse = Animation.spring(response: 0.26, dampingFraction: 0.92)
    static let content = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let activity = Animation.spring(response: 0.32, dampingFraction: 0.84)
    static let islandBounce = Animation.spring(response: 0.26, dampingFraction: 0.74)

    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 15
    static let cardPadding: CGFloat = 11
    static let cardPaddingHorizontal: CGFloat = 12
    static let cardPaddingVertical: CGFloat = 9
    static let cardHeight: CGFloat = 84
    static let artworkRadius: CGFloat = 10
    static let expandedEarRadius: CGFloat = 10

    static let notchFill = Color.black
    static let cardFill = Color.white.opacity(0.068)
    static let cardFillHover = Color.white.opacity(0.108)
    static let cardStroke = Color.white.opacity(0.08)
    static let controlFill = Color.white.opacity(0.115)
    static let controlFillHover = Color.white.opacity(0.20)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.44)

    static let eyebrow = Font.system(size: 10, weight: .semibold)
    static let title = Font.system(size: 13, weight: .semibold)
    static let largeTitle = Font.system(size: 17, weight: .bold)
    static let body = Font.system(size: 11, weight: .regular)
    static let caption = Font.system(size: 10, weight: .medium)
    static let monoDigits = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
}

extension AnyTransition {

    static var expandedNotchMorph: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
        )
    }

    static var closedNotchMorph: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .opacity
        )
    }

    static var notchMorph: AnyTransition {
        expandedNotchMorph
    }

    static func notchTab(direction: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: 18 * direction).combined(with: .opacity),
            removal: .offset(x: -18 * direction).combined(with: .opacity)
        )
    }

    static var notchActivity: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.85, anchor: .center))
    }
}

extension View {

    func notchModule(alignment: Alignment = .topLeading) -> some View {
        self
            .padding(.horizontal, NotchTheme.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    func notchCardSurface(
        radius: CGFloat = NotchTheme.cardRadius,
        isHovered: Bool = false,
        tint: Color? = nil
    ) -> some View {
        self.background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                isHovered ? NotchTheme.cardFillHover : Color.white.opacity(0.095),
                                isHovered ? Color.white.opacity(0.075) : NotchTheme.cardFill
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                if let tint {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    tint.opacity(isHovered ? 0.14 : 0.08),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 4,
                                endRadius: 150
                            )
                        )
                }

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.24 : 0.15),
                                (tint ?? .white).opacity(isHovered ? 0.12 : 0.05),
                                Color.white.opacity(isHovered ? 0.08 : 0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
        )
    }
}

enum NotchHaptics {
    static func tap() {
        guard NotchPreferences.shared.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func level() {
        guard NotchPreferences.shared.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func success() {
        guard NotchPreferences.shared.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

struct NotchSectionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(NotchTheme.eyebrow)
                .tracking(0.35)
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct NotchCard<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let destination: NotchTab?
    let content: Content
    let accessory: Accessory
    var onCardTapped: (() -> Void)? = nil

    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        tint: Color,
        destination: NotchTab? = nil,
        onCardTapped: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.destination = destination
        self.onCardTapped = onCardTapped
        self.accessory = accessory()
        self.content = content()
    }

    private func handleNavigate() {
        guard let destination else { return }
        NotchHaptics.tap()
        onCardTapped?()
        let homeHeight = NotchPreferences.shared.effectiveExpandedHeight(for: .home)
        NotchWindowController.shared.recordNavigationFromExpanded(previousHeight: homeHeight)
        withAnimation(NotchTheme.content) {
            if !NotchPreferences.shared.isTabEnabled(destination) {
                NotchPreferences.shared.setTab(destination, enabled: true)
            }
            NotchPreferences.shared.selectTab(destination)
        }
    }

    var body: some View {
        ZStack {
            if destination != nil || onCardTapped != nil {
                Button(action: handleNavigate) {
                    RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    NotchSectionLabel(title, systemImage: systemImage, tint: tint)
                    Spacer(minLength: 4)
                    accessory
                    if destination != nil || onCardTapped != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isHovering ? NotchTheme.secondaryText : NotchTheme.tertiaryText)
                            .offset(x: isHovering ? 1.5 : 0)
                    }
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, NotchTheme.cardPaddingHorizontal)
            .padding(.vertical, NotchTheme.cardPaddingVertical)
        }
        .frame(maxWidth: .infinity, minHeight: NotchTheme.cardHeight, alignment: .topLeading)
        .notchCardSurface(isHovered: isHovering && destination != nil, tint: tint)
        .contentShape(RoundedRectangle(cornerRadius: NotchTheme.cardRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) { isHovering = hovering }
            if destination != nil {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .onTapGesture {
            handleNavigate()
        }
    }
}

struct NotchPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .white
    var foreground: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct NotchSecondaryButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var selectedTint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.92))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? selectedTint : (configuration.isPressed ? NotchTheme.controlFillHover : NotchTheme.controlFill))
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct NotchCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    var fill: Color = NotchTheme.controlFill
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct NotchPlainIconButtonStyle: ButtonStyle {
    var size: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        let hitSize = max(30, size * 2)
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.55 : 0.90))
            .frame(width: hitSize, height: hitSize)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.001))
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct NotchEmptyState: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String,
        tint: Color = .white,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint.opacity(tint == .white ? 0.35 : 0.9))
                .padding(.bottom, 2)
            Text(title)
                .font(NotchTheme.title)
                .foregroundStyle(NotchTheme.primaryText)
            if let message {
                Text(message)
                    .font(NotchTheme.body)
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(NotchPrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotchProgressBar: View {
    let progress: Double
    var tint: Color = .white
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(progress, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

struct NotchProgressRing: View {
    let progress: Double
    var tint: Color = .orange
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct NotchArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    var cornerRadius: CGFloat = NotchTheme.artworkRadius

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.pink.opacity(0.35), Color.purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: image != nil)
    }
}

struct EqualizerAnimationView: View {
    var isAnimating: Bool = true
    var tint: Color = .pink
    var maxHeight: CGFloat = 14

    var body: some View {
        let controller = NotchWindowController.shared
        let visible = !controller.isDisplayAsleep && !AppExclusionManager.shared.isSuppressed
        let active = isAnimating && controller.isExpanded && visible
        Image(systemName: "waveform")
            .font(.system(size: maxHeight, weight: .semibold))
            .foregroundStyle(tint)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous), isActive: active)
            .opacity(isAnimating && visible ? 1 : 0.55)
            .frame(height: maxHeight)
    }
}

@MainActor
enum NotchFormatters {
    private static let _longDate = DateFormatter()
    private static let _monthAbbrev = DateFormatter()
    private static let _day = DateFormatter()
    private static let _shortTime = DateFormatter()
    private static var lastLanguage: AppLanguage?

    private static func ensureConfigured() {
        if lastLanguage != Localization.language {
            lastLanguage = Localization.language
            _longDate.locale = Localization.locale
            _longDate.dateFormat = (Localization.language == .english) ? "EEEE, MMMM d" : "EEEE, d 'de' MMMM"
            _monthAbbrev.locale = Localization.locale
            _monthAbbrev.dateFormat = "MMM"
            _day.locale = Localization.locale
            _day.dateFormat = "d"
            _shortTime.locale = Localization.locale
            _shortTime.timeStyle = .short
        }
    }

    static var longDate: DateFormatter {
        ensureConfigured()
        return _longDate
    }

    static var monthAbbrev: DateFormatter {
        ensureConfigured()
        return _monthAbbrev
    }

    static var day: DateFormatter {
        ensureConfigured()
        return _day
    }

    static var shortTime: DateFormatter {
        ensureConfigured()
        return _shortTime
    }

    static func capitalizedLongDate(_ date: Date = Date()) -> String {
        let str = longDate.string(from: date)
        return str.prefix(1).capitalized + str.dropFirst()
    }

    static func monthBadge(_ date: Date = Date()) -> String {
        monthAbbrev.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }
}

struct NotchDateBadge: View {
    var date: Date = Date()
    var size: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            Text(NotchFormatters.monthBadge(date))
                .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
            Text(NotchFormatters.day.string(from: date))
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct PlaybackTimeline<Content: View>: View {
    let isPlaying: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        let active = isPlaying && !NotchWindowController.shared.isDisplayAsleep && !AppExclusionManager.shared.isSuppressed
        if active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(Date())
        }
    }
}

struct NotchCapsuleSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = .white
    var trackHeight: CGFloat = 5.5
    var expandedHeight: CGFloat = 8.5
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var isHovering = false
    @State private var isDragging = false

    private var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        let active = isHovering || isDragging
        let currentHeight = active ? expandedHeight : trackHeight

        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fillWidth = max(currentHeight * 0.6, width * CGFloat(normalizedValue))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(active ? 0.18 : 0.13))
                    .frame(height: currentHeight)

                if normalizedValue > 0.005 {
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: min(width, fillWidth), height: currentHeight)
                        .shadow(color: tint.opacity(active ? 0.35 : 0), radius: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                        }
                        let fraction = min(max(Double(gesture.location.x / width), 0), 1)
                        let newValue = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                        if (fraction <= 0.001 || fraction >= 0.999) && abs(newValue - value) > 0.01 {
                            NotchHaptics.level()
                        }
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(height: max(18, expandedHeight + 8))
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: active)
    }
}

struct NotchSegmentedControl<SelectionValue: Hashable>: View {
    struct Option: Identifiable {
        let id: SelectionValue
        let title: String
        var icon: String? = nil
        var tint: Color = .white
    }

    let options: [Option]
    @Binding var selection: SelectionValue
    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isSelected = selection == option.id
                Button {
                    guard !isSelected else { return }
                    NotchHaptics.tap()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = option.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let icon = option.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(option.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.78))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(option.tint)
                                .shadow(color: option.tint.opacity(0.3), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "segment_pill", in: segmentNamespace)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
