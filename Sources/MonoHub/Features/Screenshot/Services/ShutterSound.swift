import AppKit

enum ShutterSound {
    private static let candidatePaths = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
        "/System/Library/Sounds/Tink.aiff"
    ]

    private static let sound: NSSound? = {
        for path in candidatePaths {
            if let sound = NSSound(contentsOfFile: path, byReference: true) {
                return sound
            }
        }
        return nil
    }()

    static func play() {
        guard let sound else { return }
        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }
}
