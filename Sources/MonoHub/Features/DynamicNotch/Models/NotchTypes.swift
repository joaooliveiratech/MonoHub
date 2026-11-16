import Foundation
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case home = "Home"
    case music = "Music"
    case audio = "Audio"
    case timer = "Timer"
    case calendar = "Calendar"
    case reminders = "Reminders"
    case mirror = "Mirror"
    case battery = "Battery"
    case bluetooth = "Bluetooth"
    case shelf = "Shelf"
    case clipboard = "Clipboard"
    case teleprompter = "Teleprompter"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .music: return "music.note"
        case .audio: return "slider.horizontal.below.square.and.square.filled"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .mirror: return "camera.fill"
        case .battery: return "battery.100.bolt"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .shelf: return "tray.and.arrow.down.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .teleprompter: return "text.viewfinder"
        }
    }

    var title: String {
        switch self {
        case .home: return localized("Home")
        case .music: return localized("Music")
        case .audio: return localized("Sound")
        case .timer: return localized("Timer")
        case .calendar: return localized("Calendar")
        case .reminders: return localized("Reminders")
        case .mirror: return localized("Mirror")
        case .battery: return localized("Battery")
        case .bluetooth: return localized("Bluetooth")
        case .shelf: return localized("Shelf")
        case .clipboard: return localized("Clipboard")
        case .teleprompter: return localized("Teleprompter")
        }
    }

    var accentColor: Color {
        switch self {
        case .home: return .indigo
        case .music: return .pink
        case .audio: return .orange
        case .timer: return .orange
        case .calendar: return .red
        case .reminders: return .blue
        case .mirror: return .purple
        case .battery: return .green
        case .bluetooth: return .cyan
        case .shelf: return .teal
        case .clipboard: return .orange
        case .teleprompter: return .mint
        }
    }

    var order: Int {
        NotchTab.allCases.firstIndex(of: self) ?? 0
    }
}

enum ScrollAction: Int, CaseIterable, Identifiable, Codable, Sendable {
    case adjustVolume = 0
    case adjustBrightness = 1
    case disabled = 2

    var id: Int { rawValue }

    var description: String {
        switch self {
        case .adjustVolume: return localized("Adjust volume")
        case .adjustBrightness: return localized("Adjust brightness")
        case .disabled: return localized("Disabled")
        }
    }
}

enum DisplayTargetMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case allDisplays = "allDisplays"
    case mainOnly = "mainOnly"
    case builtinOnly = "builtinOnly"
    case externalOnly = "externalOnly"
    case custom = "custom"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .allDisplays:
            return localized("All displays")
        case .mainOnly:
            return localized("Main display only")
        case .builtinOnly:
            return localized("Built-in display only")
        case .externalOnly:
            return localized("External displays only")
        case .custom:
            return localized("Custom selection")
        }
    }
}

enum HomeCard: String, CaseIterable, Identifiable, Codable, Sendable {
    case music
    case calendar
    case timer
    case battery
    case bluetooth
    case clipboard
    case teleprompter
    case aiQuota
    case heavyProcess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return localized("Music")
        case .calendar: return localized("Calendar")
        case .timer: return localized("Timer")
        case .battery: return localized("Battery")
        case .bluetooth: return localized("Bluetooth")
        case .clipboard: return localized("Clipboard")
        case .teleprompter: return localized("Teleprompter")
        case .aiQuota: return localized("AI Quotas")
        case .heavyProcess: return localized("Heavy Processes & Thermal")
        }
    }

    var subtitle: String {
        switch self {
        case .music: return localized("Artwork, current track, and play/pause")
        case .calendar: return localized("Next event and meeting link")
        case .timer: return localized("Current countdown or quick presets")
        case .battery: return localized("Charge and power status of the Mac")
        case .bluetooth: return localized("Connected accessories and battery")
        case .clipboard: return localized("Latest copied item and quick access")
        case .teleprompter: return localized("Script and notes in camera line of sight")
        case .aiQuota: return localized("Claude, Codex, Antigravity usage and limits")
        case .heavyProcess: return localized("Top CPU processes and SoC thermal pressure")
        }
    }

    var iconName: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .battery: return "battery.100.bolt"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .clipboard: return "doc.on.clipboard.fill"
        case .teleprompter: return "text.viewfinder"
        case .aiQuota: return AIQuotaStyle.symbol
        case .heavyProcess: return "cpu"
        }
    }

    var tint: Color {
        switch self {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        case .battery: return .green
        case .bluetooth: return .indigo
        case .clipboard: return .orange
        case .teleprompter: return .mint
        case .aiQuota: return AIQuotaStyle.tint
        case .heavyProcess: return .orange
        }
    }

    var destinationTab: NotchTab {
        switch self {
        case .music: return .music
        case .calendar: return .calendar
        case .timer: return .timer
        case .battery: return .battery
        case .bluetooth: return .bluetooth
        case .clipboard: return .clipboard
        case .teleprompter: return .teleprompter
        case .aiQuota, .heavyProcess: return .home
        }
    }
}

enum LiveActivityKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case timer
    case music
    case calendar
    case battery
    case aiQuota
    case heavyProcess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: return localized("Timer and stopwatch")
        case .music: return localized("Music playing")
        case .calendar: return localized("Meeting in progress")
        case .battery: return localized("Battery (charging or low)")
        case .aiQuota: return localized("AI Quota usage")
        case .heavyProcess: return localized("Heavy processes and thermal alert")
        }
    }

    var subtitle: String {
        switch self {
        case .timer: return localized("Progress ring and remaining time")
        case .music: return localized("Album artwork and animated equalizer")
        case .calendar: return localized("Timed events happening now")
        case .battery: return localized("Appears when connecting cable or below 20%")
        case .aiQuota: return localized("Real-time Claude, Codex, and Antigravity consumption")
        case .heavyProcess: return localized("Warns when a process spikes CPU or SoC heats up")
        }
    }

    var iconName: String {
        switch self {
        case .timer: return "timer"
        case .music: return "waveform"
        case .calendar: return "calendar.badge.clock"
        case .battery: return "bolt.fill"
        case .aiQuota: return AIQuotaStyle.symbol
        case .heavyProcess: return "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .timer: return .orange
        case .music: return .pink
        case .calendar: return .red
        case .battery: return .green
        case .aiQuota: return AIQuotaStyle.tint
        case .heavyProcess: return .red
        }
    }

    var destinationTab: NotchTab {
        switch self {
        case .timer: return .timer
        case .music: return .music
        case .calendar: return .calendar
        case .battery: return .battery
        case .aiQuota, .heavyProcess: return .home
        }
    }
}

enum LiveActivityLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case combined
    case split
    case single

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return localized("Side by side in notch")
        case .split: return localized("Detached bubble (iPhone style)")
        case .single: return localized("Primary only")
        }
    }
}

enum TabLabelStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case selectedOnly
    case always
    case iconsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedOnly: return localized("Selected tab only")
        case .always: return localized("Always")
        case .iconsOnly: return localized("Icons only")
        }
    }
}

enum HardwareNotchTabBarStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case unifiedBelow
    case splitEars

    static var belowNotch: Self { .unifiedBelow }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unifiedBelow: return localized("Unified bar below camera (Recommended)")
        case .splitEars: return localized("Split across camera ears")
        }
    }

    var subtitle: String {
        switch self {
        case .unifiedBelow: return localized("Shows active module and controls on camera sides with a full tab bar right below.")
        case .splitEars: return localized("Splits tab icons across both ear sides around the physical camera.")
        }
    }
}

enum ShelfClickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case revealInFinder
    case openFile
    case copyPath

    var id: String { rawValue }

    var title: String {
        switch self {
        case .revealInFinder: return localized("Reveal in Finder")
        case .openFile: return localized("Open file")
        case .copyPath: return localized("Copy full path")
        }
    }
}

enum NotchIdleAnimation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case bongoCat
    case lordOfTheRings
    case samurai
    case starWars
    case pokemon
    case pacman
    case matrix
    case nyanCat
    case dinoRunner
    case spaceInvaders
    case random

    var id: String { rawValue }

    static func fromStored(_ raw: String) -> NotchIdleAnimation {
        if let exact = NotchIdleAnimation(rawValue: raw) {
            return exact
        }
        switch raw {
        case "kittScanner": return .lordOfTheRings
        case "hal9000": return .samurai
        case "codingTerminal": return .pokemon
        default: return .bongoCat
        }
    }

    var title: String {
        switch self {
        case .none: return localized("None (Discreet)")
        case .bongoCat: return localized("Bongo Cat (Typing Cat)")
        case .lordOfTheRings: return localized("Lord of the Rings (Sauron & One Ring)")
        case .samurai: return localized("Samurai Ronin (Katana & Sakura)")
        case .starWars: return localized("Star Wars (X-Wing vs TIE Fighter)")
        case .pokemon: return localized("Pokémon (Pikachu & Pokéball)")
        case .pacman: return localized("Pac-Man Arcade")
        case .matrix: return localized("Matrix Digital Rain")
        case .nyanCat: return localized("Nyan Cat Rainbow")
        case .dinoRunner: return localized("Chrome Dino Runner (T-Rex)")
        case .spaceInvaders: return localized("Space Invaders 8-Bit")
        case .random: return localized("Random (Auto Rotate)")
        }
    }

    var subtitle: String {
        switch self {
        case .none: return localized("Keeps notch unanimated when idle")
        case .bongoCat: return localized("Kitty tapping mechanical keyboard with code in terminal")
        case .lordOfTheRings: return localized("Flaming Eye of Sauron in Barad-dûr and One Ring pulsing with runes")
        case .samurai: return localized("Ronin striking quick Iaido katana slashes under cherry blossom petals")
        case .starWars: return localized("X-Wing fighter chasing TIE Fighter with lasers crossing the notch")
        case .pokemon: return localized("Pikachu casting Thunderbolt toward trembling Pokéball")
        case .pacman: return localized("Pac-Man chomping dots while escaping colorful ghosts")
        case .matrix: return localized("Cybernetic cascade of neon glyphs")
        case .nyanCat: return localized("Pop-Tart space cat flying with rainbow trail and stars")
        case .dinoRunner: return localized("Pixel art T-Rex sprinting across desert jumping over cacti")
        case .spaceInvaders: return localized("Classic arcade aliens marching under cannon fire")
        case .random: return localized("Automatically rotates through all nerd animations every minute")
        }
    }

    var iconName: String {
        switch self {
        case .none: return "moon.zzz.fill"
        case .bongoCat: return "cat.fill"
        case .lordOfTheRings: return "flame.circle.fill"
        case .samurai: return "bolt.slash.fill"
        case .starWars: return "sparkles"
        case .pokemon: return "bolt.circle.fill"
        case .pacman: return "arcade.stick.console.fill"
        case .matrix: return "chevron.left.forwardslash.chevron.right"
        case .nyanCat: return "rainbow"
        case .dinoRunner: return "figure.run"
        case .spaceInvaders: return "gamecontroller.fill"
        case .random: return "shuffle"
        }
    }

    var tint: Color {
        switch self {
        case .none: return .secondary
        case .bongoCat: return .pink
        case .lordOfTheRings: return .orange
        case .samurai: return .red
        case .starWars: return .cyan
        case .pokemon: return .yellow
        case .pacman: return .yellow
        case .matrix: return .green
        case .nyanCat: return .purple
        case .dinoRunner: return .orange
        case .spaceInvaders: return .mint
        case .random: return .indigo
        }
    }

    var accentColor: Color { tint }

    static let concreteStyles: [NotchIdleAnimation] = [
        .bongoCat, .lordOfTheRings, .samurai, .starWars, .pokemon,
        .pacman, .matrix, .nyanCat, .dinoRunner, .spaceInvaders
    ]

    func resolved(at date: Date = Date()) -> NotchIdleAnimation {
        guard self == .random else { return self }
        let styles = Self.concreteStyles
        guard !styles.isEmpty else { return .bongoCat }
        let bucket = Int(date.timeIntervalSince1970 / 45.0)
        return styles[abs(bucket) % styles.count]
    }

    func resolved(for date: Date) -> NotchIdleAnimation {
        resolved(at: date)
    }
}

enum NotchIdleWithActivityMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case sideBySide
    case detachedBubble
    case whenIdleOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: return localized("Split in Notch (Activity + Animation)")
        case .detachedBubble: return localized("Detached Side Bubble")
        case .whenIdleOnly: return localized("Hide During Activities")
        }
    }

    var shortTitle: String {
        switch self {
        case .sideBySide: return localized("Split Side by Side")
        case .detachedBubble: return localized("Side Bubble")
        case .whenIdleOnly: return localized("Idle Only")
        }
    }

    var subtitle: String {
        switch self {
        case .sideBySide:
            return localized("Displays Music or Timer on the left side of the notch and keeps interactive animation on the right.")
        case .detachedBubble:
            return localized("Keeps live activity in the main notch and places animation in a floating side bubble.")
        case .whenIdleOnly:
            return localized("Shows animation only when there is no active music, timer, or meeting in the notch.")
        }
    }

    var iconName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1.fill"
        case .detachedBubble: return "circle.grid.2x1.right.filled"
        case .whenIdleOnly: return "eye.slash.fill"
        }
    }
}

enum NotchIdleInteractionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case interactive
    case alwaysActive
    case onlyWhenTyping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interactive: return localized("Interactive (Reacts to Typing and Clicks)")
        case .alwaysActive: return localized("Always Active (Continuous)")
        case .onlyWhenTyping: return localized("Only When Typing / Using Mac")
        }
    }

    var shortTitle: String {
        switch self {
        case .interactive: return localized("Interactive")
        case .alwaysActive: return localized("Always Active")
        case .onlyWhenTyping: return localized("When Typing")
        }
    }

    var subtitle: String {
        switch self {
        case .interactive:
            return localized("Stays calm at rest and springs into action with every keystroke, click, or scroll.")
        case .alwaysActive:
            return localized("Animation runs continuously at a steady pace even without keyboard input.")
        case .onlyWhenTyping:
            return localized("Appears and animates while you type or interact, gently tucking away when idle.")
        }
    }

    var iconName: String {
        switch self {
        case .interactive: return "keyboard.fill"
        case .alwaysActive: return "infinity"
        case .onlyWhenTyping: return "bolt.horizontal.fill"
        }
    }
}
