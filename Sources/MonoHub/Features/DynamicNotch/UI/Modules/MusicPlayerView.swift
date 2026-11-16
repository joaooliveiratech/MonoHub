import SwiftUI
import AppKit

struct MusicPlayerView: View {
    private let playbackManager = MediaPlaybackManager.shared
    private let volumeManager = AudioVolumeManager.shared
    private let preferences = NotchPreferences.shared
    @State private var scrubProgress: Double?
    @State private var isHoveringScrubber = false
    @State private var isHoveringArtwork = false

    init() {}

    private var themeColor: Color {
        switch playbackManager.currentTrack.playerType {
        case .appleMusic: return Color(red: 0.98, green: 0.22, blue: 0.38)
        case .spotify: return Color(red: 0.11, green: 0.84, blue: 0.38)
        case .youtube: return Color(red: 1.0, green: 0.2, blue: 0.2)
        case .video: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .appleTV: return Color.white
        case .quickTime: return Color.blue
        case .podcasts: return Color.purple
        case .system: return Color.pink
        }
    }

    var body: some View {
        let track = playbackManager.currentTrack

        Group {
            if !playbackManager.isAvailable || track.isEmpty {
                emptyStateView
            } else {
                activePlayerView(track: track)
            }
        }
        .onAppear {
            playbackManager.refreshIfStale()
            volumeManager.fetchVolume()
            AudioDeviceManager.shared.refreshDevices()
            AudioDeviceManager.shared.startMetering(consumer: "MusicPlayerView")
        }
        .onDisappear {
            AudioDeviceManager.shared.stopMetering(consumer: "MusicPlayerView")
        }
    }

    @ViewBuilder
    private func activePlayerView(track: MusicTrack) -> some View {
        HStack(spacing: 20) {
            ZStack {
                if preferences.musicShowArtworkGlow {
                    if let img = playbackManager.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .blur(radius: 16)
                            .opacity(track.isPlaying ? 0.60 : 0.22)
                            .drawingGroup()
                    } else {
                        Circle()
                            .fill(themeColor.opacity(track.isPlaying ? 0.32 : 0.10))
                            .frame(width: 90, height: 90)
                            .blur(radius: 14)
                            .drawingGroup()
                    }
                }

                NotchArtworkView(
                    image: playbackManager.artwork,
                    size: 102,
                    cornerRadius: 14
                )
                .shadow(color: .black.opacity(0.55), radius: 12, y: 5)
                .scaleEffect(isHoveringArtwork ? 1.03 : (track.isPlaying ? 1.0 : 0.96))
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: track.isPlaying)
                .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHoveringArtwork)
            }
            .frame(width: 102, height: 102)
            .onHover { hovering in
                isHoveringArtwork = hovering
            }
            .onTapGesture {
                openActivePlayerApp(for: track)
            }
            .help(String(format: localized("Open %@"), track.appName))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Button {
                        openActivePlayerApp(for: track)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: track.playerType.iconName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(themeColor)

                            Text(track.appName.uppercased())
                                .font(NotchTheme.eyebrow)
                                .tracking(0.4)
                                .foregroundStyle(NotchTheme.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if preferences.musicShowVisualizer {
                        EqualizerAnimationView(
                            isAnimating: track.isPlaying,
                            tint: themeColor,
                            maxHeight: 12
                        )
                    }
                }

                Text(track.title)
                    .font(NotchTheme.largeTitle)
                    .foregroundStyle(NotchTheme.primaryText)
                    .lineLimit(1)

                Text(track.artist + (track.album.isEmpty ? "" : " • \(track.album)"))
                    .font(NotchTheme.body)
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)

                Spacer().frame(height: 1)

                PlaybackTimeline(isPlaying: track.isPlaying && scrubProgress == nil) { date in
                    progressSection(track: track, date: date)
                }

                HStack(spacing: 16) {
                    Button {
                        NotchHaptics.tap()
                        playbackManager.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(NotchPlainIconButtonStyle(size: 15))

                    Button {
                        NotchHaptics.tap()
                        playbackManager.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .offset(x: track.isPlaying ? 0 : 1)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(NotchCircleButtonStyle(size: 34, fill: .white, foreground: .black))

                    Button {
                        NotchHaptics.tap()
                        playbackManager.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(NotchPlainIconButtonStyle(size: 15))

                    Spacer(minLength: 8)

                    HStack(spacing: 7) {
                        Button {
                            NotchHaptics.tap()
                            volumeManager.toggleMute()
                        } label: {
                            Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : (volumeManager.currentVolume < 0.35 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(volumeManager.isMuted ? Color.red : NotchTheme.secondaryText)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)

                        NotchCapsuleSlider(
                            value: Binding(
                                get: { Double(volumeManager.isMuted ? 0 : volumeManager.currentVolume) },
                                set: { volumeManager.setVolume(Float($0)) }
                            ),
                            range: 0...1,
                            tint: .white.opacity(0.92),
                            trackHeight: 5,
                            expandedHeight: 8
                        )
                        .frame(width: 88)
                    }
                }

                if preferences.musicShowAudioRouteSelector {
                    AudioRouteBar()
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .notchModule()
    }

    private func progressSection(track: MusicTrack, date: Date) -> some View {
        let liveProgress = scrubProgress ?? playbackManager.progress(at: date)
        let elapsed = scrubProgress.map { $0 * track.duration } ?? playbackManager.elapsed(at: date)
        let isScrubActive = scrubProgress != nil || isHoveringScrubber
        let barHeight: CGFloat = isScrubActive ? 7 : 4.5

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isScrubActive ? 0.18 : 0.12))
                        .frame(height: barHeight)

                    Capsule(style: .continuous)
                        .fill(isScrubActive ? Color.white : themeColor)
                        .frame(width: max(barHeight * 0.5, width * CGFloat(liveProgress)), height: barHeight)
                        .shadow(color: (isScrubActive ? Color.white : themeColor).opacity(isScrubActive ? 0.4 : 0), radius: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard track.duration > 0, width > 0 else { return }
                            scrubProgress = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { value in
                            guard track.duration > 0, width > 0 else {
                                scrubProgress = nil
                                return
                            }
                            NotchHaptics.tap()
                            playbackManager.seek(to: min(max(value.location.x / width, 0), 1))
                            scrubProgress = nil
                        }
                )
            }
            .frame(height: 10)
            .onHover { hovering in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.76)) {
                    isHoveringScrubber = hovering
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isScrubActive)

            if preferences.musicShowElapsedTimes {
                HStack {
                    Text(MusicTrack.format(elapsed))
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isScrubActive ? NotchTheme.secondaryText : NotchTheme.tertiaryText)
                    Spacer()
                    Text(track.duration > 0 ? "-\(MusicTrack.format(max(0, track.duration - elapsed)))" : "")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isScrubActive ? NotchTheme.secondaryText : NotchTheme.tertiaryText)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 50, height: 50)

                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.pink.opacity(0.85))
            }

            VStack(spacing: 3) {
                Text(localized("Nothing playing"))
                    .font(NotchTheme.title)
                    .foregroundStyle(NotchTheme.primaryText)

                Text(localized("Play music or video in any app to control it from the notch."))
                    .font(NotchTheme.body)
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            HStack(spacing: 10) {
                Button {
                    NotchHaptics.tap()
                    launchApp(bundleID: "com.apple.Music")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "apple.logo")
                        Text("Apple Music")
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())

                Button {
                    NotchHaptics.tap()
                    launchApp(bundleID: "com.spotify.client")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("Spotify")
                    }
                }
                .buttonStyle(NotchSecondaryButtonStyle())
            }
            .padding(.top, 2)

            if preferences.musicShowAudioRouteSelector {
                AudioRouteBar()
                    .frame(maxWidth: 360)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchModule(alignment: .top)
    }

    private func openActivePlayerApp(for track: MusicTrack) {
        NotchHaptics.tap()
        switch track.playerType {
        case .appleMusic:
            launchApp(bundleID: "com.apple.Music")
        case .spotify:
            launchApp(bundleID: "com.spotify.client")
        case .podcasts:
            launchApp(bundleID: "com.apple.podcasts")
        case .appleTV:
            launchApp(bundleID: "com.apple.TV")
        case .quickTime:
            launchApp(bundleID: "com.apple.QuickTimePlayerX")
        default:
            break
        }
    }

    private func launchApp(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }
}
