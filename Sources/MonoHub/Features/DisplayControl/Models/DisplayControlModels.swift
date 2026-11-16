import AppKit
import CoreGraphics
import Foundation

nonisolated enum DisplayConnectionType: String, Sendable, CaseIterable, Codable {
    case hdmi = "HDMI"
    case displayPort = "DisplayPort"
    case thunderbolt = "Thunderbolt"
    case usbC = "USB-C"
    case internalDisplay = "Built-in"
    case virtualDisplay = "Virtual"
    case sidecarAirPlay = "AirPlay / Sidecar"
    case unknown = "Display"

    var localizedTitle: String {
        switch self {
        case .hdmi: return "HDMI"
        case .displayPort: return "DisplayPort"
        case .thunderbolt: return "Thunderbolt"
        case .usbC: return "USB-C"
        case .internalDisplay: return localized("Internal Display")
        case .virtualDisplay: return localized("Virtual Screen")
        case .sidecarAirPlay: return "AirPlay / Sidecar"
        case .unknown: return localized("External Display")
        }
    }

    var systemImage: String {
        switch self {
        case .hdmi: return "cable.connector"
        case .displayPort: return "display"
        case .thunderbolt: return "bolt.horizontal.fill"
        case .usbC: return "cable.connector.horizontal"
        case .internalDisplay: return "laptopcomputer"
        case .virtualDisplay: return "rectangle.on.rectangle.dashed"
        case .sidecarAirPlay: return "ipad.and.iphone"
        case .unknown: return "display.2"
        }
    }
}

nonisolated enum DisplayDimmingMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case combined = "combined"
    case hardwareOnly = "hardwareOnly"
    case softwareOnly = "softwareOnly"
    case overlayOnly = "overlayOnly"
    case disabled = "disabled"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combined: return localized("Combined (Hardware + Gamma + Sub-Zero)")
        case .hardwareOnly: return localized("Hardware Only (DDC)")
        case .softwareOnly: return localized("Software Only (Gamma)")
        case .overlayOnly: return localized("Overlay Only (Dim to Black)")
        case .disabled: return localized("Disabled")
        }
    }

    var description: String {
        switch self {
        case .combined:
            return localized("Uses hardware DDC down to the minimum backlight level, then seamlessly engages software gamma and overlay dimming down to absolute black (0%).")
        case .hardwareOnly:
            return localized("Directly modifies the physical backlight of the monitor via DDC/CI commands.")
        case .softwareOnly:
            return localized("Adjusts brightness via ColorSync/Gamma tables. Ideal for monitors without DDC or TVs.")
        case .overlayOnly:
            return localized("Uses a click-through full-screen dark overlay window. Preserves ColorSync LUT tables and reaches 100% pitch black.")
        case .disabled:
            return localized("Does not intercept or modify brightness for this display.")
        }
    }

    var systemImage: String {
        switch self {
        case .combined: return "sun.max.trianglebadge.exclamationmark"
        case .hardwareOnly: return "sun.max.fill"
        case .softwareOnly: return "moon.stars.fill"
        case .overlayOnly: return "circle.lefthalf.filled.inverse"
        case .disabled: return "slash.circle"
        }
    }
}

nonisolated enum DDCTargetMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case cursor = "cursor"
    case focusedWindow = "focusedWindow"
    case allDisplays = "allDisplays"
    case syncWithBuiltIn = "syncWithBuiltIn"
    case customSingle = "customSingle"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .cursor: return localized("Follow Mouse Cursor")
        case .focusedWindow: return localized("Active Window Display")
        case .allDisplays: return localized("All External Displays")
        case .syncWithBuiltIn: return localized("Sync with Built-in Screen")
        case .customSingle: return localized("Selected Primary Display")
        }
    }

    var subtitle: String {
        switch self {
        case .cursor:
            return localized("Controls the display where the cursor is currently pointing.")
        case .focusedWindow:
            return localized("Controls the display containing the active frontmost window.")
        case .allDisplays:
            return localized("Applies brightness and volume adjustments to all connected external displays.")
        case .syncWithBuiltIn:
            return localized("Synchronizes the brightness of external monitors with the MacBook display.")
        case .customSingle:
            return localized("Always directs controls to the primary external display selected in settings.")
        }
    }

    var systemImage: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .focusedWindow: return "macwindow.on.rectangle"
        case .allDisplays: return "display.2"
        case .syncWithBuiltIn: return "arrow.triangle.2.circlepath"
        case .customSingle: return "display"
        }
    }
}

nonisolated enum BrightnessCurve: String, Sendable, CaseIterable, Identifiable, Codable {
    case linear = "linear"
    case perceptual = "perceptual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: return localized("Linear")
        case .perceptual: return localized("Perceptual (Gamma 2.2)")
        }
    }

    var description: String {
        switch self {
        case .linear:
            return localized("Values map 1:1 proportionally to the monitor scale.")
        case .perceptual:
            return localized("Compensates for human eye perception for smoother adjustment in low light.")
        }
    }

    func transform(value: Float) -> Float {
        let clamped = max(0.0, min(1.0, value))
        switch self {
        case .linear:
            return clamped
        case .perceptual:
            return pow(clamped, 2.2)
        }
    }

    func invert(value: Float) -> Float {
        let clamped = max(0.0, min(1.0, value))
        switch self {
        case .linear:
            return clamped
        case .perceptual:
            return pow(clamped, 1.0 / 2.2)
        }
    }
}

nonisolated enum DisplayRotation: Int, Sendable, CaseIterable, Identifiable, Codable {
    case degree0 = 0
    case degree90 = 90
    case degree180 = 180
    case degree270 = 270

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .degree0: return localized("0° (Standard Landscape)")
        case .degree90: return localized("90° (Portrait Right)")
        case .degree180: return localized("180° (Inverted Landscape)")
        case .degree270: return localized("270° (Portrait Left)")
        }
    }

    var shortTitle: String {
        "\(rawValue)°"
    }

    var systemImage: String {
        switch self {
        case .degree0: return "display"
        case .degree90: return "rectangle.portrait"
        case .degree180: return "display.trianglebadge.exclamationmark"
        case .degree270: return "rectangle.portrait.fill"
        }
    }
}

nonisolated struct DisplayModeItem: Identifiable, Sendable, Equatable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool
    let isNative: Bool
    let isCurrent: Bool
    let scalePercentage: Int

    var resolutionLabel: String {
        "\(width) × \(height)"
    }

    var framebufferLabel: String {
        "\(pixelWidth) × \(pixelHeight) px"
    }

    var refreshRateLabel: String {
        if abs(refreshRate.rounded() - refreshRate) < 0.05 {
            return "\(Int(refreshRate.rounded())) Hz"
        }
        return String(format: "%.2f Hz", refreshRate)
    }

    var aspectRatioString: String {
        guard width > 0 && height > 0 else { return "16:9" }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 16.0 / 9.0) < 0.04 { return "16:9" }
        if abs(ratio - 16.0 / 10.0) < 0.04 { return "16:10" }
        if abs(ratio - 21.0 / 9.0) < 0.08 { return "21:9" }
        if abs(ratio - 32.0 / 9.0) < 0.08 { return "32:9" }
        if abs(ratio - 4.0 / 3.0) < 0.04 { return "4:3" }
        if abs(ratio - 3.0 / 2.0) < 0.04 { return "3:2" }
        if abs(ratio - 9.0 / 16.0) < 0.04 { return "9:16" }
        if abs(ratio - 10.0 / 16.0) < 0.04 { return "10:16" }
        return String(format: "%.2f:1", ratio)
    }
}

nonisolated struct CustomScaledResolutionSpec: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id: String { "\(logicalWidth)x\(logicalHeight)@\(hiDPI ? "2x" : "1x")" }
    let logicalWidth: Int
    let logicalHeight: Int
    let hiDPI: Bool
    let label: String

    var backingPixelWidth: Int { hiDPI ? logicalWidth * 2 : logicalWidth }
    var backingPixelHeight: Int { hiDPI ? logicalHeight * 2 : logicalHeight }

    static let standardPresets: [CustomScaledResolutionSpec] = [
        CustomScaledResolutionSpec(logicalWidth: 1600, logicalHeight: 900, hiDPI: true, label: "1600 × 900 HiDPI (3200×1800)"),
        CustomScaledResolutionSpec(logicalWidth: 1920, logicalHeight: 1080, hiDPI: true, label: "1920 × 1080 HiDPI (3840×2160 4K)"),
        CustomScaledResolutionSpec(logicalWidth: 2048, logicalHeight: 1152, hiDPI: true, label: "2048 × 1152 HiDPI (4096×2304)"),
        CustomScaledResolutionSpec(logicalWidth: 2304, logicalHeight: 1296, hiDPI: true, label: "2304 × 1296 HiDPI (4608×2592)"),
        CustomScaledResolutionSpec(logicalWidth: 2560, logicalHeight: 1440, hiDPI: true, label: "2560 × 1440 HiDPI (5120×2880 5K)"),
        CustomScaledResolutionSpec(logicalWidth: 3008, logicalHeight: 1692, hiDPI: true, label: "3008 × 1692 HiDPI (6016×3384 6K)"),
        CustomScaledResolutionSpec(logicalWidth: 2560, logicalHeight: 1080, hiDPI: true, label: "2560 × 1080 Ultrawide HiDPI (5120×2160)"),
        CustomScaledResolutionSpec(logicalWidth: 3440, logicalHeight: 1440, hiDPI: true, label: "3440 × 1440 Ultrawide HiDPI (6880×2880)")
    ]
}

nonisolated struct DisplayColorAdjustment: Codable, Sendable, Equatable {
    var temperatureKelvin: Float = 6500.0
    var redGain: Float = 1.0
    var greenGain: Float = 1.0
    var blueGain: Float = 1.0
    var gammaOffset: Float = 0.0
    var softwareContrast: Float = 1.0
    var isGrayscale: Bool = false
    var isInverted: Bool = false

    var isIdentity: Bool {
        abs(temperatureKelvin - 6500.0) < 10.0 &&
        abs(redGain - 1.0) < 0.005 &&
        abs(greenGain - 1.0) < 0.005 &&
        abs(blueGain - 1.0) < 0.005 &&
        abs(gammaOffset) < 0.005 &&
        abs(softwareContrast - 1.0) < 0.005 &&
        !isGrayscale &&
        !isInverted
    }

    static func kelvinToRGB(kelvin: Float) -> (r: Float, g: Float, b: Float) {
        let clamped = max(1500.0, min(15000.0, kelvin))
        if abs(clamped - 6500.0) < 15.0 {
            return (1.0, 1.0, 1.0)
        }

        let temp = Double(clamped) / 100.0
        let r: Double
        let g: Double
        let b: Double

        if temp <= 66.0 {
            r = 255.0
        } else {
            let v = 329.698727446 * pow(temp - 60.0, -0.1332047592)
            r = max(0.0, min(255.0, v))
        }

        if temp <= 66.0 {
            let v = 99.4708025861 * log(temp) - 161.1195681661
            g = max(0.0, min(255.0, v))
        } else {
            let v = 288.1221695283 * pow(temp - 60.0, -0.0755148492)
            g = max(0.0, min(255.0, v))
        }

        if temp >= 66.0 {
            b = 255.0
        } else if temp <= 19.0 {
            b = 0.0
        } else {
            let v = 138.5177312231 * log(temp - 10.0) - 305.0447927307
            b = max(0.0, min(255.0, v))
        }

        return (Float(r / 255.0), Float(g / 255.0), Float(b / 255.0))
    }
}

nonisolated struct XDRUpscalingConfig: Codable, Sendable, Equatable {
    var isEnabled: Bool = false

    var boostFactor: Float = 1.0

    var boostPercentage: Int {
        Int(round(boostFactor * 100.0))
    }

    var estimatedNits: Int {
        Int(round(500.0 * Double(max(1.0, boostFactor)) * 1.6))
    }
}

nonisolated enum VirtualAspectRatio: String, Sendable, CaseIterable, Identifiable, Codable {
    case ratio16x9 = "16:9"
    case ratio16x10 = "16:10"
    case ratio21x9 = "21:9"
    case ratio32x9 = "32:9"
    case ratio4x3 = "4:3"
    case ratio3x2 = "3:2"
    case ratio9x16 = "9:16"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ratio16x9: return localized("16:9 Widescreen (4K / 5K / 1080p)")
        case .ratio16x10: return localized("16:10 MacBook / Studio")
        case .ratio21x9: return localized("21:9 Ultrawide Cinema")
        case .ratio32x9: return localized("32:9 Super Ultrawide")
        case .ratio4x3: return localized("4:3 iPad / Sidecar Classic")
        case .ratio3x2: return localized("3:2 Productivity Surface")
        case .ratio9x16: return localized("9:16 Portrait Vertical / Teleprompter")
        }
    }

    var defaultMaxResolution: (width: Int, height: Int) {
        switch self {
        case .ratio16x9: return (3840, 2160)
        case .ratio16x10: return (3840, 2400)
        case .ratio21x9: return (5120, 2160)
        case .ratio32x9: return (5120, 1440)
        case .ratio4x3: return (2880, 2160)
        case .ratio3x2: return (3240, 2160)
        case .ratio9x16: return (2160, 3840)
        }
    }

    var baseResolutions: [(width: Int, height: Int)] {
        switch self {
        case .ratio16x9:
            return [(1280, 720), (1600, 900), (1920, 1080), (2560, 1440), (3008, 1692), (3840, 2160)]
        case .ratio16x10:
            return [(1280, 800), (1440, 900), (1680, 1050), (1920, 1200), (2560, 1600), (3840, 2400)]
        case .ratio21x9:
            return [(2560, 1080), (3440, 1440), (3840, 1600), (5120, 2160)]
        case .ratio32x9:
            return [(3840, 1080), (5120, 1440)]
        case .ratio4x3:
            return [(1024, 768), (1400, 1050), (1600, 1200), (2048, 1536), (2880, 2160)]
        case .ratio3x2:
            return [(1440, 960), (1920, 1280), (2256, 1504), (3240, 2160)]
        case .ratio9x16:
            return [(1080, 1920), (1440, 2560), (2160, 3840)]
        }
    }
}

nonisolated enum TeleprompterFlipMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case none = "none"
    case horizontal = "horizontal"
    case vertical = "vertical"
    case both = "both"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return localized("Normal (No Flip)")
        case .horizontal: return localized("Horizontal Flip (Teleprompter Mirror)")
        case .vertical: return localized("Vertical Flip")
        case .both: return localized("Flip Both (180°)")
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "rectangle"
        case .horizontal: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .vertical: return "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .both: return "arrow.triangle.2.circlepath"
        }
    }
}

nonisolated struct VirtualScreenConfig: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var name: String
    var aspectRatio: VirtualAspectRatio
    var maxWidth: Int
    var maxHeight: Int
    var refreshRate: Double = 60.0
    var hiDPIEnabled: Bool = true
    var isConnected: Bool = false
    var autoConnectOnStartup: Bool = false
    var associatedDisplayUUID: String?
    var flipMode: TeleprompterFlipMode = .none
    var activeDisplayID: CGDirectDisplayID?

    enum CodingKeys: String, CodingKey {
        case id, name, aspectRatio, maxWidth, maxHeight, refreshRate, hiDPIEnabled, isConnected, autoConnectOnStartup, associatedDisplayUUID, flipMode
    }

    init(
        id: UUID = UUID(),
        name: String,
        aspectRatio: VirtualAspectRatio = .ratio16x9,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        refreshRate: Double = 60.0,
        hiDPIEnabled: Bool = true,
        isConnected: Bool = false,
        autoConnectOnStartup: Bool = false,
        associatedDisplayUUID: String? = nil,
        flipMode: TeleprompterFlipMode = .none,
        activeDisplayID: CGDirectDisplayID? = nil
    ) {
        self.id = id
        self.name = name
        self.aspectRatio = aspectRatio
        let def = aspectRatio.defaultMaxResolution
        self.maxWidth = maxWidth ?? def.width
        self.maxHeight = maxHeight ?? def.height
        self.refreshRate = refreshRate
        self.hiDPIEnabled = hiDPIEnabled
        self.isConnected = isConnected
        self.autoConnectOnStartup = autoConnectOnStartup
        self.associatedDisplayUUID = associatedDisplayUUID
        self.flipMode = flipMode
        self.activeDisplayID = activeDisplayID
    }
}

nonisolated enum PiPCropPreset: String, Sendable, CaseIterable, Identifiable, Codable {
    case full = "full"
    case centerZoom = "centerZoom"
    case leftHalf = "leftHalf"
    case rightHalf = "rightHalf"
    case topHalf = "topHalf"
    case bottomHalf = "bottomHalf"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return localized("Full Screen")
        case .centerZoom: return localized("Center 50% Zoom")
        case .leftHalf: return localized("Left Half")
        case .rightHalf: return localized("Right Half")
        case .topHalf: return localized("Top Half")
        case .bottomHalf: return localized("Bottom Half")
        }
    }

    var normalizedRect: CGRect {
        switch self {
        case .full: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .centerZoom: return CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1.0)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1.0)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1.0, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1.0, height: 0.5)
        }
    }
}

nonisolated struct PiPStreamConfig: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var sourceDisplayID: CGDirectDisplayID
    var sourceName: String
    var width: Double = 480
    var height: Double = 270
    var opacity: Double = 1.0
    var isClickThrough: Bool = false
    var alwaysOnTop: Bool = true
    var flipMode: TeleprompterFlipMode = .none
    var cropPreset: PiPCropPreset = .full
    var isGrayscale: Bool = false
    var targetFPS: Int = 60
}

nonisolated struct DisplayLayoutEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String { displayUUID }
    let displayUUID: String
    let displayName: String
    let originX: Int32
    let originY: Int32
    let width: Int
    let height: Int
    let isHiDPI: Bool
    let refreshRate: Double
    let rotation: Int
    let isMainDisplay: Bool
    let mirrorOfUUID: String?
}

nonisolated struct DisplayLayoutAnchor: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var name: String
    var entries: [DisplayLayoutEntry]
}

nonisolated struct EDIDDiagnosticInfo: Sendable, Equatable {
    let manufacturerCode: String
    let manufacturerName: String
    let productCode: UInt16
    let serialNumber: UInt32
    let serialString: String?
    let monitorDescriptorName: String?
    let manufactureWeek: Int
    let manufactureYear: Int
    let edidVersion: String
    let isDigitalInput: Bool
    let bitDepthPerColor: Int
    let videoInterface: String
    let horizontalSizeCm: Int
    let verticalSizeCm: Int
    let diagonalInches: Double
    let nativePPI: Double
    let gamma: Double
    let supportsHDR: Bool
    let maxEDRNits: Double
    let maxPotentialEDRNits: Double
    let checksumValid: Bool
    let rawHexDump: String
    let byteCount: Int
}

nonisolated enum EDIDParser {
    private static let vendorLookup: [String: String] = [
        "APP": "Apple Inc.",
        "DEL": "Dell Inc.",
        "GSM": "LG Electronics",
        "SAM": "Samsung Electric",
        "BNQ": "BenQ Corporation",
        "ACI": "ASUS (ASUSTeK)",
        "AUS": "ASUS (ASUSTeK)",
        "ACR": "Acer Inc.",
        "SNY": "Sony Corporation",
        "LEN": "Lenovo Group",
        "HWP": "Hewlett-Packard (HP)",
        "PHL": "Philips Consumer Electronics",
        "MSI": "Micro-Star International (MSI)",
        "GBT": "Gigabyte Technology",
        "AOC": "AOC International",
        "VSC": "ViewSonic Corporation",
        "EIZ": "EIZO Nanao Corporation",
        "NEC": "NEC Corporation",
        "IVM": "Iiyama North America",
        "HSD": "HannStar Display",
        "CMN": "Innolux / Chimei",
        "BOE": "BOE Technology"
    ]

    static func parse(
        bytes: [UInt8],
        nativePixelWidth: Int = 3840,
        nativePixelHeight: Int = 2160,
        maxEDRFactor: Double = 1.0,
        maxPotentialEDRFactor: Double = 1.0
    ) -> EDIDDiagnosticInfo? {
        guard bytes.count >= 128 else { return nil }

        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard Array(bytes[0..<8]) == header else { return nil }

        let mfgWord = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        let c1 = UInt8(((mfgWord >> 10) & 0x1F) + 64)
        let c2 = UInt8(((mfgWord >> 5) & 0x1F) + 64)
        let c3 = UInt8((mfgWord & 0x1F) + 64)
        let mfgCode = String(bytes: [c1, c2, c3], encoding: .ascii) ?? "UNK"
        let mfgName = vendorLookup[mfgCode] ?? mfgCode

        let productCode = UInt16(bytes[10]) | (UInt16(bytes[11]) << 8)

        let serialNum = UInt32(bytes[12])
            | (UInt32(bytes[13]) << 8)
            | (UInt32(bytes[14]) << 16)
            | (UInt32(bytes[15]) << 24)

        let week = Int(bytes[16])
        let year = 1990 + Int(bytes[17])
        let version = "\(bytes[18]).\(bytes[19])"

        let inputByte = bytes[20]
        let isDigital = (inputByte & 0x80) != 0
        var bitDepth = 8
        var interfaceName = "DisplayPort / Digital"

        if isDigital {
            let depthBits = (inputByte >> 4) & 0x07
            switch depthBits {
            case 1: bitDepth = 6
            case 2: bitDepth = 8
            case 3: bitDepth = 10
            case 4: bitDepth = 12
            case 5: bitDepth = 14
            case 6: bitDepth = 16
            default: bitDepth = 8
            }

            let ifaceBits = inputByte & 0x0F
            switch ifaceBits {
            case 1: interfaceName = "DVI"
            case 2: interfaceName = "HDMI-a"
            case 3: interfaceName = "HDMI-b"
            case 4: interfaceName = "MDDI"
            case 5: interfaceName = "DisplayPort"
            default: interfaceName = "Digital (DP / HDMI / TB)"
            }
        } else {
            interfaceName = "Analog VGA"
        }

        let widthCm = Int(bytes[21])
        let heightCm = Int(bytes[22])

        let diagCm = sqrt(Double(widthCm * widthCm + heightCm * heightCm))
        let diagInches = (diagCm / 2.54 * 10.0).rounded() / 10.0

        var ppi = 110.0
        if widthCm > 0 && nativePixelWidth > 0 {
            let widthInches = Double(widthCm) / 2.54
            ppi = (Double(nativePixelWidth) / widthInches * 10.0).rounded() / 10.0
        }

        let gammaVal = bytes[23] == 0xFF ? 2.2 : Double(Int(bytes[23]) + 100) / 100.0

        var descriptorName: String?
        var descriptorSerial: String?

        for blockIndex in 0..<4 {
            let base = 54 + blockIndex * 18
            guard base + 18 <= bytes.count else { break }
            if bytes[base] == 0x00 && bytes[base + 1] == 0x00 && bytes[base + 2] == 0x00 {
                let tag = bytes[base + 3]
                let textBytes = Array(bytes[(base + 5)..<(base + 18)])
                let cleaned = String(bytes: textBytes, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                if tag == 0xFC, let cleaned, !cleaned.isEmpty {
                    descriptorName = cleaned
                } else if tag == 0xFF, let cleaned, !cleaned.isEmpty {
                    descriptorSerial = cleaned
                }
            }
        }

        let sum = bytes[0..<128].reduce(0) { ($0 + Int($1)) & 0xFF }
        let checksumValid = (sum == 0)

        var hexLines: [String] = []
        for rowStart in stride(from: 0, to: min(bytes.count, 256), by: 16) {
            let rowEnd = min(rowStart + 16, bytes.count)
            let hexRow = bytes[rowStart..<rowEnd].map { String(format: "%02X", $0) }.joined(separator: " ")
            hexLines.append(String(format: "%04X: %@", rowStart, hexRow))
        }

        let supportsHDR = maxPotentialEDRFactor > 1.05 || bytes.count >= 256
        let maxNits = (maxEDRFactor * 500.0).rounded()
        let maxPotentialNits = (maxPotentialEDRFactor * 500.0).rounded()

        return EDIDDiagnosticInfo(
            manufacturerCode: mfgCode,
            manufacturerName: mfgName,
            productCode: productCode,
            serialNumber: serialNum,
            serialString: descriptorSerial,
            monitorDescriptorName: descriptorName,
            manufactureWeek: week,
            manufactureYear: year,
            edidVersion: version,
            isDigitalInput: isDigital,
            bitDepthPerColor: bitDepth,
            videoInterface: interfaceName,
            horizontalSizeCm: widthCm,
            verticalSizeCm: heightCm,
            diagonalInches: diagInches,
            nativePPI: ppi,
            gamma: gammaVal,
            supportsHDR: supportsHDR,
            maxEDRNits: maxNits,
            maxPotentialEDRNits: maxPotentialNits,
            checksumValid: checksumValid,
            rawHexDump: hexLines.joined(separator: "\n"),
            byteCount: bytes.count
        )
    }

    static func generateOverridePlist(
        vendorID: UInt32,
        productID: UInt32,
        displayName: String,
        forceFullRGB: Bool = true,
        unlockNightShift: Bool = true,
        customResolutions: [CustomScaledResolutionSpec] = CustomScaledResolutionSpec.standardPresets
    ) -> String {
        var scaleEntries: [String] = []
        for spec in customResolutions {
            var bytes = [UInt8](repeating: 0, count: 16)
            let w = UInt32(spec.backingPixelWidth).bigEndian
            let h = UInt32(spec.backingPixelHeight).bigEndian
            let flags: UInt32 = (spec.hiDPI ? UInt32(0x00000001) : UInt32(0x00000000)).bigEndian
            withUnsafeBytes(of: w) { bytes.replaceSubrange(0..<4, with: $0) }
            withUnsafeBytes(of: h) { bytes.replaceSubrange(4..<8, with: $0) }
            withUnsafeBytes(of: flags) { bytes.replaceSubrange(8..<12, with: $0) }
            let base64 = Data(bytes).base64EncodedString()
            scaleEntries.append("        <data>\(base64)</data>")
        }

        let scaleXml = scaleEntries.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DisplayProductName</key>
            <string>\(displayName) (MonoHub Pro Override)</string>
            <key>DisplayVendorID</key>
            <integer>\(vendorID)</integer>
            <key>DisplayProductID</key>
            <integer>\(productID)</integer>
            \(forceFullRGB ? "<key>DisplayPixelEncoding</key>\n    <integer>0</integer>" : "")
            \(unlockNightShift ? "<key>DisplaySupportsNightShift</key>\n    <true/>" : "")
            <key>scale-resolutions</key>
            <array>
        \(scaleXml)
            </array>
        </dict>
        </plist>
        """
    }
}

nonisolated struct ExternalDisplayDevice: Identifiable, Sendable, Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let connectionType: DisplayConnectionType
    let isBuiltIn: Bool
    let isVirtual: Bool
    var brightness: Float
    var volume: Float
    var contrast: Float
    var sharpness: Float
    var redGainDDC: Float
    var greenGainDDC: Float
    var blueGainDDC: Float
    var isMuted: Bool
    var inputSource: DDCProtocol.InputSource?
    var colorPreset: DDCProtocol.ColorPreset?
    var powerState: DDCProtocol.PowerState?
    var rotation: DisplayRotation
    var isMainDisplay: Bool
    var mirrorMasterDisplayID: CGDirectDisplayID?
    var isBlackedOut: Bool
    var supportsDDC: Bool
    var supportsVolume: Bool
    var supportsPower: Bool
    var supportsInputSwitch: Bool
    var supportsXDRBoost: Bool
    var maxPotentialEDR: Double
    var currentEDR: Double
    var origin: CGPoint
    var logicalSize: CGSize
    var pixelSize: CGSize
    var refreshRate: Double
    var isHiDPI: Bool

    init(
        id: CGDirectDisplayID,
        uuid: String,
        name: String,
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        connectionType: DisplayConnectionType,
        isBuiltIn: Bool,
        isVirtual: Bool = false,
        brightness: Float,
        volume: Float,
        contrast: Float,
        sharpness: Float = 0.5,
        redGainDDC: Float = 0.5,
        greenGainDDC: Float = 0.5,
        blueGainDDC: Float = 0.5,
        isMuted: Bool,
        inputSource: DDCProtocol.InputSource? = nil,
        colorPreset: DDCProtocol.ColorPreset? = nil,
        powerState: DDCProtocol.PowerState? = .on,
        rotation: DisplayRotation = .degree0,
        isMainDisplay: Bool = false,
        mirrorMasterDisplayID: CGDirectDisplayID? = nil,
        isBlackedOut: Bool = false,
        supportsDDC: Bool = false,
        supportsVolume: Bool = false,
        supportsPower: Bool = false,
        supportsInputSwitch: Bool = false,
        supportsXDRBoost: Bool = false,
        maxPotentialEDR: Double = 1.0,
        currentEDR: Double = 1.0,
        origin: CGPoint = .zero,
        logicalSize: CGSize = .zero,
        pixelSize: CGSize = .zero,
        refreshRate: Double = 60.0,
        isHiDPI: Bool = false
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.connectionType = connectionType
        self.isBuiltIn = isBuiltIn
        self.isVirtual = isVirtual
        self.brightness = brightness
        self.volume = volume
        self.contrast = contrast
        self.sharpness = sharpness
        self.redGainDDC = redGainDDC
        self.greenGainDDC = greenGainDDC
        self.blueGainDDC = blueGainDDC
        self.isMuted = isMuted
        self.inputSource = inputSource
        self.colorPreset = colorPreset
        self.powerState = powerState
        self.rotation = rotation
        self.isMainDisplay = isMainDisplay
        self.mirrorMasterDisplayID = mirrorMasterDisplayID
        self.isBlackedOut = isBlackedOut
        self.supportsDDC = supportsDDC
        self.supportsVolume = supportsVolume
        self.supportsPower = supportsPower
        self.supportsInputSwitch = supportsInputSwitch
        self.supportsXDRBoost = supportsXDRBoost
        self.maxPotentialEDR = maxPotentialEDR
        self.currentEDR = currentEDR
        self.origin = origin
        self.logicalSize = logicalSize
        self.pixelSize = pixelSize
        self.refreshRate = refreshRate
        self.isHiDPI = isHiDPI
    }

    var resolutionString: String {
        if logicalSize.width > 0 && logicalSize.height > 0 {
            return "\(Int(logicalSize.width)) × \(Int(logicalSize.height))"
        }
        let mode = CGDisplayCopyDisplayMode(id)
        let w = mode?.width ?? 0
        let h = mode?.height ?? 0
        return "\(w) × \(h)"
    }
}
