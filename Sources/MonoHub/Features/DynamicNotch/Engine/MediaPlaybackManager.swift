import AppKit
import Foundation
import ImageIO
import Observation

nonisolated struct NowPlayingSnapshot: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isPlaying: Bool
    var artworkData: Data?
    var bundleID: String?
    var appName: String?
    var pid: Int32?
    var playerHint: MusicPlayerType?

    init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        isPlaying: Bool = false,
        artworkData: Data? = nil,
        bundleID: String? = nil,
        appName: String? = nil,
        pid: Int32? = nil,
        playerHint: MusicPlayerType? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.artworkData = artworkData
        self.bundleID = bundleID
        self.appName = appName
        self.pid = pid
        self.playerHint = playerHint
    }

    static func parseScriptResult(_ result: String, playerHint: MusicPlayerType, durationDivisor: Double = 1) -> NowPlayingSnapshot? {
        guard result != "NONE" else { return nil }
        let parts = result.components(separatedBy: ":::")
        guard parts.count >= 6 else { return nil }
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = trimmed[0]
        guard !title.isEmpty else { return nil }
        var duration = parseNumber(trimmed[3]) / durationDivisor
        if duration == 0 {
            duration = parseClock(trimmed[3])
        }
        return NowPlayingSnapshot(
            title: title,
            artist: trimmed[1],
            album: trimmed[2],
            duration: duration,
            elapsed: parseNumber(trimmed[4]),
            isPlaying: trimmed[5].lowercased() == "true",
            bundleID: playerHint == .spotify ? MediaPlayerApps.spotify : MediaPlayerApps.music,
            appName: playerHint == .spotify ? "Spotify" : "Apple Music",
            playerHint: playerHint
        )
    }

    static func parseNumber(_ raw: String) -> Double {
        Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    static func parseClock(_ raw: String) -> Double {
        let parts = raw.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }
}

nonisolated enum MediaPlayerApps {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func defaultName(for bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Google Chrome"
        case "company.thebrowser.Browser": return "Arc"
        case "com.brave.Browser": return "Brave"
        case "org.mozilla.firefox": return "Firefox"
        case "org.videolan.vlc": return "VLC"
        case "com.colliderli.iina": return "IINA"
        case "com.apple.QuickTimePlayerX": return "QuickTime Player"
        case "com.apple.podcasts": return "Podcasts"
        case "com.apple.TV": return "Apple TV"
        default: return localized("Media")
        }
    }

    static let fallbackCandidates: [(bundleID: String, type: MusicPlayerType, name: String)] = [
        ("com.apple.Music", .appleMusic, "Apple Music"),
        ("com.spotify.client", .spotify, "Spotify"),
        ("com.apple.Safari", .youtube, "Safari"),
        ("com.google.Chrome", .youtube, "Google Chrome"),
        ("company.thebrowser.Browser", .youtube, "Arc"),
        ("org.videolan.vlc", .video, "VLC"),
        ("com.colliderli.iina", .video, "IINA"),
        ("com.apple.QuickTimePlayerX", .quickTime, "QuickTime Player"),
        ("com.apple.podcasts", .podcasts, "Podcasts"),
        ("com.apple.TV", .appleTV, "Apple TV")
    ]
}

nonisolated final class MediaRemoteBridge: @unchecked Sendable {
    static let shared = MediaRemoteBridge()

    private typealias MRGetInfoBlock = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRGetClientBlock = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias MRRegisterNotificationsBlock = @convention(c) (DispatchQueue) -> Void
    private typealias MRUnregisterNotificationsBlock = @convention(c) () -> Void
    private typealias MRSendCommandBlock = @convention(c) (Int32, AnyObject?) -> Bool
    private typealias MRSetElapsedTimeBlock = @convention(c) (Double) -> Void
    private typealias MRClientGetBundleIDBlock = @convention(c) (AnyObject) -> CFString?
    private typealias MRClientGetDisplayNameBlock = @convention(c) (AnyObject) -> CFString?
    private typealias MRClientGetPIDBlock = @convention(c) (AnyObject) -> Int32

    enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private let getNowPlayingInfo: MRGetInfoBlock?
    private let getNowPlayingClient: MRGetClientBlock?
    private let registerNotifications: MRRegisterNotificationsBlock?
    private let unregisterNotifications: MRUnregisterNotificationsBlock?
    private let sendCommandFn: MRSendCommandBlock?
    private let setElapsedTimeFn: MRSetElapsedTimeBlock?
    private let clientBundleID: MRClientGetBundleIDBlock?
    private let clientDisplayName: MRClientGetDisplayNameBlock?
    private let clientPID: MRClientGetPIDBlock?
    private let queue = DispatchQueue(label: "com.antigravity.monohub.mediaremote", qos: .utility)

    private init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let bundle, let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        getNowPlayingInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: MRGetInfoBlock.self)
        getNowPlayingClient = symbol("MRMediaRemoteGetNowPlayingClient", as: MRGetClientBlock.self)
        registerNotifications = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: MRRegisterNotificationsBlock.self)
        unregisterNotifications = symbol("MRMediaRemoteUnregisterForNowPlayingNotifications", as: MRUnregisterNotificationsBlock.self)
        sendCommandFn = symbol("MRMediaRemoteSendCommand", as: MRSendCommandBlock.self)
        setElapsedTimeFn = symbol("MRMediaRemoteSetElapsedTime", as: MRSetElapsedTimeBlock.self)
        clientBundleID = symbol("MRNowPlayingClientGetBundleIdentifier", as: MRClientGetBundleIDBlock.self)
        clientDisplayName = symbol("MRNowPlayingClientGetDisplayName", as: MRClientGetDisplayNameBlock.self)
        clientPID = symbol("MRNowPlayingClientGetProcessIdentifier", as: MRClientGetPIDBlock.self)
    }

    static let notificationNames: [Notification.Name] = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
    ].map { Notification.Name($0) }

    func register() {
        registerNotifications?(queue)
    }

    func unregister() {
        unregisterNotifications?()
    }

    @discardableResult
    func send(_ command: Command) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }

    func setElapsedTime(_ seconds: Double) -> Bool {
        guard let setElapsedTimeFn else { return false }
        setElapsedTimeFn(seconds)
        return true
    }

    func nowPlaying() async -> NowPlayingSnapshot? {
        guard let getNowPlayingInfo else { return nil }
        let info: NowPlayingSnapshot? = await withCheckedContinuation { continuation in
            getNowPlayingInfo(queue) { dict in
                continuation.resume(returning: Self.parse(dict))
            }
        }
        guard var info else { return nil }
        if let client = await nowPlayingClient() {
            info.bundleID = client.bundleID
            info.appName = client.name
            info.pid = client.pid
        }
        return info
    }

    private func nowPlayingClient() async -> (bundleID: String?, name: String?, pid: Int32?)? {
        guard let getNowPlayingClient else { return nil }
        let getBundleID = clientBundleID
        let getName = clientDisplayName
        let getPID = clientPID
        return await withCheckedContinuation { continuation in
            getNowPlayingClient(queue) { client in
                guard let client else {
                    continuation.resume(returning: nil)
                    return
                }
                let bundleID = getBundleID.flatMap { $0(client) as String? }
                let name = getName.flatMap { $0(client) as String? }
                let pid = getPID.map { $0(client) }
                continuation.resume(returning: (
                    bundleID: bundleID?.isEmpty == false ? bundleID : nil,
                    name: name?.isEmpty == false ? name : nil,
                    pid: (pid ?? 0) > 0 ? pid : nil
                ))
            }
        }
    }

    private static func parse(_ dict: [String: Any]) -> NowPlayingSnapshot? {
        func number(_ key: String) -> Double {
            (dict[key] as? Double) ?? (dict[key] as? NSNumber)?.doubleValue ?? 0
        }
        let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? ""
        guard !title.isEmpty else { return nil }
        return NowPlayingSnapshot(
            title: title,
            artist: (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? "",
            album: (dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? "",
            duration: number("kMRMediaRemoteNowPlayingInfoDuration"),
            elapsed: number("kMRMediaRemoteNowPlayingInfoElapsedTime"),
            isPlaying: number("kMRMediaRemoteNowPlayingInfoPlaybackRate") > 0,
            artworkData: dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        )
    }
}

actor MediaScriptRunner {
    static let shared = MediaScriptRunner()

    private var compiled: [String: NSAppleScript] = [:]

    private static let musicStateScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            if player state is playing or player state is paused then
                set trackTitle to ""
                try
                    set trackTitle to name of current track
                end try
                set trackArtist to ""
                try
                    set trackArtist to artist of current track
                end try
                set trackAlbum to ""
                try
                    set trackAlbum to album of current track
                end try
                set trackDuration to 0
                try
                    set trackDuration to duration of current track
                end try
                set trackPosition to 0
                try
                    set trackPosition to player position
                end try
                set isPlaying to (player state is playing)
                return trackTitle & ":::" & trackArtist & ":::" & trackAlbum & ":::" & trackDuration & ":::" & trackPosition & ":::" & isPlaying
            end if
        end tell
    end if
    return "NONE"
    """

    private static let musicArtworkScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            try
                tell current track
                    if (count of artworks) > 0 then
                        return raw data of artwork 1
                    end if
                end tell
            end try
        end tell
    end if
    return missing value
    """

    private static let spotifyStateScript = """
    if application id "com.spotify.client" is running then
        tell application id "com.spotify.client"
            if player state is playing or player state is paused then
                set trackTitle to ""
                try
                    set trackTitle to name of current track
                end try
                set trackArtist to ""
                try
                    set trackArtist to artist of current track
                end try
                set trackAlbum to ""
                try
                    set trackAlbum to album of current track
                end try
                set trackDuration to 0
                try
                    set trackDuration to duration of current track
                end try
                set trackPosition to 0
                try
                    set trackPosition to player position
                end try
                set isPlaying to (player state is playing)
                return trackTitle & ":::" & trackArtist & ":::" & trackAlbum & ":::" & trackDuration & ":::" & trackPosition & ":::" & isPlaying
            end if
        end tell
    end if
    return "NONE"
    """

    func musicSnapshot() -> NowPlayingSnapshot? {
        guard let result = run(Self.musicStateScript)?.stringValue else { return nil }
        return NowPlayingSnapshot.parseScriptResult(result, playerHint: .appleMusic)
    }

    func spotifySnapshot() -> NowPlayingSnapshot? {
        guard let result = run(Self.spotifyStateScript)?.stringValue else { return nil }
        return NowPlayingSnapshot.parseScriptResult(result, playerHint: .spotify, durationDivisor: 1000)
    }

    func musicArtwork() -> Data? {
        guard let descriptor = run(Self.musicArtworkScript) else { return nil }
        let data = descriptor.data
        return data.isEmpty ? nil : data
    }

    func perform(_ command: String, onBundleID bundleID: String) {
        let source = """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)" to \(command)
        end if
        """
        _ = run(source, cache: false)
    }

    func clearCache() {
        compiled.removeAll()
    }

    private func run(_ source: String, cache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if cache, let existing = compiled[source] {
            script = existing
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            script = created
            if cache {
                compiled[source] = created
            }
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        return error == nil ? descriptor : nil
    }
}

@Observable
@MainActor
final class MediaPlaybackManager {
    static let shared = MediaPlaybackManager()

    private(set) var currentTrack: MusicTrack = .empty
    private(set) var isAvailable: Bool = false
    private(set) var artwork: NSImage?
    private(set) var elapsedSampledAt: Date = .distantPast

    @ObservationIgnored private(set) var isRunning = false
    @ObservationIgnored private var observerTokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var artworkCache: [String: NSImage] = [:]
    @ObservationIgnored private var artworkCacheOrder: [String] = []
    @ObservationIgnored private var artworkMisses: Set<String> = []
    @ObservationIgnored private var activeClientBundleID: String?
    @ObservationIgnored private var activeClientPID: Int32?
    @ObservationIgnored private var lastSeenAt: Date = .distantPast

    private static let artworkCacheLimit = 12
    private static let staleInterval: TimeInterval = 20

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true
        MediaRemoteBridge.shared.register()
        installObservers()
        scheduleRefresh(after: .zero)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        MediaRemoteBridge.shared.unregister()
        refreshTask?.cancel()
        refreshTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        refreshGeneration += 1
        resetToEmpty()
        artworkCache.removeAll()
        artworkCacheOrder.removeAll()
        artworkMisses.removeAll()
        Task { await MediaScriptRunner.shared.clearCache() }
    }

    func refreshIfStale() {
        guard isRunning, !NotchWindowController.shared.isDisplayAsleep, Date().timeIntervalSince(lastSeenAt) > Self.staleInterval else { return }
        scheduleRefresh(after: .zero)
    }

    func handleDisplayWake() {
        guard isRunning else { return }
        scheduleRefresh(after: .milliseconds(250))
    }

    func elapsed(at date: Date) -> TimeInterval {
        let track = currentTrack
        guard track.isPlaying else { return track.elapsed }
        let value = track.elapsed + max(0, date.timeIntervalSince(elapsedSampledAt))
        return track.duration > 0 ? min(value, track.duration) : value
    }

    func progress(at date: Date) -> Double {
        let duration = currentTrack.duration
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }

    private func installObservers() {
        let local = NotificationCenter.default
        for name in MediaRemoteBridge.notificationNames {
            observe(local, name: name)
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: Notification.Name("com.apple.Music.playerInfo"))
        observe(distributed, name: Notification.Name("com.spotify.client.PlaybackStateChanged"))

        let workspace = NSWorkspace.shared.notificationCenter
        let token = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                self?.handleApplicationTerminated(bundleID: bundleID, pid: pid)
            }
        }
        observerTokens.append((workspace, token))
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }
        observerTokens.append((center, token))
    }

    private func removeObservers() {
        for entry in observerTokens {
            entry.center.removeObserver(entry.token)
        }
        observerTokens.removeAll()
    }

    private func handleApplicationTerminated(bundleID: String?, pid: Int32?) {
        let isKnownPlayer = bundleID == MediaPlayerApps.music || bundleID == MediaPlayerApps.spotify
        let isActiveClient = (pid != nil && pid == activeClientPID) || (bundleID != nil && bundleID == activeClientBundleID)
        guard isActiveClient || isKnownPlayer else { return }
        if isActiveClient || currentTrack.playerType == MusicPlayerType.from(bundleIdentifier: bundleID, appName: nil) {
            resetToEmpty()
        }
        scheduleRefresh(after: .milliseconds(300))
    }

    func scheduleRefresh(after delay: Duration = .milliseconds(150)) {
        guard isRunning, !NotchWindowController.shared.isDisplayAsleep else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let snapshot = await Self.loadSnapshot()
        guard isRunning, generation == refreshGeneration else { return }
        lastSeenAt = Date()
        apply(snapshot)
    }

    nonisolated private static func loadSnapshot() async -> NowPlayingSnapshot? {
        if let remote = await MediaRemoteBridge.shared.nowPlaying() {
            return remote
        }
        if MediaPlayerApps.isRunning(MediaPlayerApps.music), let music = await MediaScriptRunner.shared.musicSnapshot() {
            return music
        }
        if MediaPlayerApps.isRunning(MediaPlayerApps.spotify), let spotify = await MediaScriptRunner.shared.spotifySnapshot() {
            return spotify
        }
        return nil
    }

    private func apply(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot else {
            resetToEmpty()
            return
        }

        if let pid = snapshot.pid, let app = NSRunningApplication(processIdentifier: pid), app.isTerminated {
            resetToEmpty()
            return
        }

        let (playerType, appName) = resolvePlayer(for: snapshot)
        if playerType == .appleMusic && !MediaPlayerApps.isRunning(MediaPlayerApps.music) {
            resetToEmpty()
            return
        }
        if playerType == .spotify && !MediaPlayerApps.isRunning(MediaPlayerApps.spotify) {
            resetToEmpty()
            return
        }

        activeClientBundleID = snapshot.bundleID
        activeClientPID = snapshot.pid

        let previous = currentTrack
        let artist: String
        if !snapshot.artist.isEmpty {
            artist = snapshot.artist
        } else if previous.title == snapshot.title && !previous.artist.isEmpty && previous.artist != appName {
            artist = previous.artist
        } else {
            artist = appName
        }

        let track = MusicTrack(
            title: snapshot.title,
            artist: artist,
            album: snapshot.album,
            duration: snapshot.duration,
            elapsed: snapshot.elapsed,
            isPlaying: snapshot.isPlaying,
            playerType: playerType,
            appName: appName,
            artworkData: nil
        )

        let key = Self.artworkKey(title: track.title, artist: track.artist)
        updateArtwork(for: key, rawData: snapshot.artworkData, playerType: playerType)

        elapsedSampledAt = Date()
        if track != currentTrack {
            currentTrack = track
        }
        if !isAvailable {
            isAvailable = true
        }

        if track.isPlaying && track.title != previous.title {
            LiveActivityCenter.shared.trackDidChange(track)
        }
    }

    private func resolvePlayer(for snapshot: NowPlayingSnapshot) -> (MusicPlayerType, String) {
        if let hint = snapshot.playerHint {
            return (hint, snapshot.appName ?? hint.rawValue)
        }
        if let bundleID = snapshot.bundleID {
            let type = MusicPlayerType.from(bundleIdentifier: bundleID, appName: snapshot.appName)
            return (type, snapshot.appName ?? MediaPlayerApps.defaultName(for: bundleID))
        }
        if let pid = snapshot.pid, let app = NSRunningApplication(processIdentifier: pid) {
            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? MediaPlayerApps.defaultName(for: bundleID)
            return (MusicPlayerType.from(bundleIdentifier: bundleID, appName: name), name)
        }
        for candidate in MediaPlayerApps.fallbackCandidates where MediaPlayerApps.isRunning(candidate.bundleID) {
            return (candidate.type, candidate.name)
        }
        return (.system, localized("Media"))
    }

    private func resetToEmpty() {
        if currentTrack != .empty {
            currentTrack = .empty
        }
        if isAvailable {
            isAvailable = false
        }
        if artwork != nil {
            artwork = nil
        }
        activeClientPID = nil
        activeClientBundleID = nil
    }

    nonisolated static func artworkKey(title: String, artist: String) -> String {
        "\(title):::\(artist)"
    }

    private func updateArtwork(for key: String, rawData: Data?, playerType: MusicPlayerType) {
        if let cached = artworkCache[key] {
            setArtwork(cached)
            return
        }
        if let rawData {
            artworkTask?.cancel()
            artworkTask = Task { [weak self] in
                let decoded = await Self.decodeDownsampledImage(rawData)
                guard !Task.isCancelled, let self, self.isRunning else { return }
                guard let image = decoded else {
                    self.setArtwork(nil)
                    return
                }
                self.cacheArtwork(image, for: key)
                if Self.artworkKey(title: self.currentTrack.title, artist: self.currentTrack.artist) == key {
                    self.setArtwork(image)
                }
            }
            return
        }
        setArtwork(nil)
        guard playerType == .appleMusic, !artworkMisses.contains(key) else { return }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let data = await MediaScriptRunner.shared.musicArtwork()
            guard !Task.isCancelled, let self, self.isRunning else { return }
            guard let data, let image = await Self.decodeDownsampledImage(data) else {
                self.artworkMisses.insert(key)
                return
            }
            self.cacheArtwork(image, for: key)
            if Self.artworkKey(title: self.currentTrack.title, artist: self.currentTrack.artist) == key {
                self.setArtwork(image)
            }
        }
    }

    private func setArtwork(_ image: NSImage?) {
        if artwork !== image {
            artwork = image
        }
    }

    private func cacheArtwork(_ image: NSImage, for key: String) {
        artworkCache[key] = image
        artworkCacheOrder.removeAll { $0 == key }
        artworkCacheOrder.append(key)
        while artworkCacheOrder.count > Self.artworkCacheLimit {
            let evicted = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: evicted)
        }
    }

    @concurrent
    nonisolated private static func decodeDownsampledImage(_ rawData: Data) async -> NSImage? {
        decodeImage(rawData)
    }

    nonisolated static func decodeImage(_ rawData: Data) -> NSImage? {
        if let thumb = downsampleImageData(rawData, maxPixelSize: 256) {
            return thumb
        }
        if let image = NSImage(data: rawData) {
            return image
        }
        for magic in [Data([0xFF, 0xD8, 0xFF]), Data([0x89, 0x50, 0x4E, 0x47])] {
            if let range = rawData.range(of: magic) {
                let slice = rawData.subdata(in: range.lowerBound..<rawData.count)
                if let thumb = downsampleImageData(slice, maxPixelSize: 256) {
                    return thumb
                }
                if let image = NSImage(data: slice) {
                    return image
                }
            }
        }
        return nil
    }

    nonisolated private static func downsampleImageData(_ data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func togglePlayPause() {
        guard isAvailable && !currentTrack.isEmpty else {
            if MediaPlayerApps.isRunning(MediaPlayerApps.music) {
                runScript("playpause", on: MediaPlayerApps.music)
            } else if MediaPlayerApps.isRunning(MediaPlayerApps.spotify) {
                runScript("playpause", on: MediaPlayerApps.spotify)
            }
            scheduleRefresh(after: .milliseconds(400))
            return
        }

        if !MediaRemoteBridge.shared.send(.togglePlayPause) {
            runScriptForCurrentPlayer("playpause")
        }

        let now = Date()
        let track = currentTrack
        currentTrack = MusicTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            elapsed: elapsed(at: now),
            isPlaying: !track.isPlaying,
            playerType: track.playerType,
            appName: track.appName,
            artworkData: nil
        )
        elapsedSampledAt = now
        scheduleRefresh(after: .milliseconds(400))
    }

    func nextTrack() {
        guard isAvailable && !currentTrack.isEmpty else { return }
        if !MediaRemoteBridge.shared.send(.nextTrack) {
            runScriptForCurrentPlayer("next track")
        }
        scheduleRefresh(after: .milliseconds(400))
    }

    func previousTrack() {
        guard isAvailable && !currentTrack.isEmpty else { return }
        if !MediaRemoteBridge.shared.send(.previousTrack) {
            runScriptForCurrentPlayer("previous track")
        }
        scheduleRefresh(after: .milliseconds(400))
    }

    func seek(to progress: Double) {
        let track = currentTrack
        guard track.duration > 0 else { return }
        let target = max(0, min(track.duration, track.duration * progress))

        switch track.playerType {
        case .appleMusic:
            runScript("set player position to \(Int(target))", on: MediaPlayerApps.music)
        case .spotify:
            runScript("set player position to \(Int(target))", on: MediaPlayerApps.spotify)
        default:
            _ = MediaRemoteBridge.shared.setElapsedTime(target)
        }

        currentTrack = MusicTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            elapsed: target,
            isPlaying: track.isPlaying,
            playerType: track.playerType,
            appName: track.appName,
            artworkData: nil
        )
        elapsedSampledAt = Date()
    }

    private func runScriptForCurrentPlayer(_ command: String) {
        switch currentTrack.playerType {
        case .appleMusic:
            runScript(command, on: MediaPlayerApps.music)
        case .spotify:
            runScript(command, on: MediaPlayerApps.spotify)
        default:
            break
        }
    }

    private func runScript(_ command: String, on bundleID: String) {
        Task {
            await MediaScriptRunner.shared.perform(command, onBundleID: bundleID)
        }
    }
}
