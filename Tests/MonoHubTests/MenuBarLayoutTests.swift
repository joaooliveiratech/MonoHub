import AppKit
import Foundation
import Testing
@testable import MonoHub

@Suite("Menu bar layout and stacked styles")
@MainActor
struct MenuBarLayoutTests {
    private let battery = BatteryGlyphState(percent: 80, isCharging: false, isConnected: true, isLowPowerMode: false, dynamicColors: true)

    @Test("Symbol over value is narrower than symbol beside value")
    func stackedIsNarrower() {
        let side = MenuBarRenderer.image(for: .symbolWithValue(symbol: "cpu", value: "46%", tint: .normal))
        let stacked = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "46%", tint: .normal))
        #expect(stacked.size.width < side.size.width * 0.75)
        #expect(stacked.size.height == MenuBarRenderer.height)

        let low = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "2%", tint: .normal))
        let mid = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "64%", tint: .warning))
        #expect(low.size.width == mid.size.width)
        #expect(low.size.width <= 24)

        let batteryStacked = MenuBarRenderer.image(for: .batteryStacked(battery, value: "80%"))
        let batteryBeside = MenuBarRenderer.image(for: .batteryWithPercent(battery, value: "80%"))
        #expect(batteryStacked.size.width < batteryBeside.size.width)
    }

    @Test("Stacked modules share one column width so the bar looks uniform")
    func uniformColumns() {
        let widths = [
            MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "6%", tint: .normal)),
            MenuBarRenderer.image(for: .symbolStacked(symbol: "memorychip", value: "45%", tint: .normal)),
            MenuBarRenderer.image(for: .symbolStacked(symbol: "thermometer.medium", value: "37°", tint: .normal)),
            MenuBarRenderer.image(for: .symbolStacked(symbol: "internaldrive", value: "58%", tint: .normal))
        ].map(\.size.width)
        #expect(Set(widths).count == 1)
        let full = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "100%", tint: .critical))
        #expect(full.size.width > widths[0])
    }

    @Test("Monochrome content renders as a template image for native menu bar tinting")
    func templateImages() {
        let normal = MenuBarContent.symbolStacked(symbol: "cpu", value: "6%", tint: .normal)
        let critical = MenuBarContent.symbolStacked(symbol: "cpu", value: "96%", tint: .critical)
        let charging = MenuBarContent.battery(BatteryGlyphState(percent: 50, isCharging: true, isConnected: true, isLowPowerMode: false, dynamicColors: true))
        #expect(MenuBarRenderer.image(for: normal).isTemplate)
        #expect(MenuBarRenderer.image(for: .battery(battery)).isTemplate)
        #expect(!MenuBarRenderer.image(for: critical).isTemplate)
        #expect(!MenuBarRenderer.image(for: charging).isTemplate)
        #expect(MenuBarContent.network(download: "1K", upload: "0K", downloadActive: false, uploadActive: false).isMonochrome)
    }

    @Test("Symbol over value style is offered where it fits")
    func styleAvailability() {
        for module in [ModuleType.cpu, .ram, .gpu, .disk, .battery, .sensors] {
            #expect(module.availableStyles.contains(.symbolStacked))
            let content = MenuBarContentFactory.content(for: module, style: .symbolStacked)
            switch content {
            case .symbolStacked, .batteryStacked: break
            default: Issue.record("\(module) did not render stacked: \(content)")
            }
        }
        #expect(!ModuleType.network.availableStyles.contains(.symbolStacked))
        #expect(DisplayStyle(rawValue: "symbol_stacked") == .symbolStacked)
    }

    @Test("Rendering height adapts to the menu bar and stays clamped")
    func adaptiveHeight() {
        defer { _ = MenuBarRenderer.updateAvailableHeight(MenuBarRenderer.baseHeight) }
        _ = MenuBarRenderer.updateAvailableHeight(MenuBarRenderer.baseHeight)
        let regularBattery = MenuBarRenderer.image(for: .battery(battery))
        let regularStacked = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "45%", tint: .normal))
        #expect(regularBattery.size.height == MenuBarRenderer.baseHeight)

        #expect(MenuBarRenderer.updateAvailableHeight(28))
        #expect(MenuBarRenderer.height == MenuBarRenderer.maximumHeight)
        #expect(!MenuBarRenderer.updateAvailableHeight(40))
        let tallBattery = MenuBarRenderer.image(for: .battery(battery))
        let tallStacked = MenuBarRenderer.image(for: .symbolStacked(symbol: "cpu", value: "45%", tint: .normal))
        #expect(tallBattery.size.height == MenuBarRenderer.maximumHeight)
        #expect(tallBattery.size.width > regularBattery.size.width)
        #expect(tallStacked.size.width > regularStacked.size.width)

        #expect(MenuBarRenderer.updateAvailableHeight(10))
        #expect(MenuBarRenderer.height == MenuBarRenderer.baseHeight)
    }

    @Test("Every module symbol renders visible pixels inside the image")
    func symbolsHaveInk() throws {
        for symbol in ["cpu", "memorychip", "cube.transparent", "internaldrive", "thermometer.medium"] {
            let image = MenuBarRenderer.image(for: .symbolStacked(symbol: symbol, value: "45%", tint: .normal))
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            var inkInTopHalf = 0
            for y in 0..<(rep.pixelsHigh / 2) {
                for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 {
                    inkInTopHalf += 1
                }
            }
            #expect(inkInTopHalf > 20, "\(symbol) has no visible glyph")
        }
    }

    @Test("Stacked layouts stay vertically centered in the menu bar")
    func stackedBlocksAreCentered() throws {
        let contents: [MenuBarContent] = [
            .symbolStacked(symbol: "cpu", value: "46%", tint: .normal),
            .symbolStacked(symbol: "internaldrive", value: "58%", tint: .normal),
            .stacked(label: "CPU", value: "46%", tint: .normal, prominent: false, labelSymbol: nil),
            .network(download: "1.2M", upload: "34K", downloadActive: true, uploadActive: false),
            .batteryStacked(battery, value: "80%")
        ]
        for content in contents {
            let (top, bottom) = try inkMargins(of: MenuBarRenderer.image(for: content))
            #expect(abs(top - bottom) <= 2, "\(content) margins top=\(top) bottom=\(bottom)")
        }
    }

    @Test("Identical content reuses the rendered image until the height changes")
    func imageCache() {
        defer { _ = MenuBarRenderer.updateAvailableHeight(MenuBarRenderer.baseHeight) }
        let content = MenuBarContent.symbolStacked(symbol: "cpu", value: "12%", tint: .normal)
        let first = MenuBarRenderer.image(for: content)
        #expect(MenuBarRenderer.image(for: content) === first)
        _ = MenuBarRenderer.updateAvailableHeight(MenuBarRenderer.maximumHeight)
        #expect(MenuBarRenderer.image(for: content) !== first)
    }

    private func inkMargins(of image: NSImage) throws -> (top: Int, bottom: Int) {
        let scale = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width) * scale,
            pixelsHigh: Int(image.size.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = image.size
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var first = rep.pixelsHigh
        var last = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.25 {
                first = min(first, y)
                last = max(last, y)
            }
        }
        return (first, rep.pixelsHigh - 1 - last)
    }
}

@Suite("Drag to reorder")
struct ReorderTests {
    @Test("Moving onto a later row lands after it, onto an earlier row lands before it")
    func movesOntoTarget() {
        let items = ["a", "b", "c", "d"]
        #expect(items.moving("a", onto: "c") == ["b", "c", "a", "d"])
        #expect(items.moving("d", onto: "b") == ["a", "d", "b", "c"])
        #expect(items.moving("b", onto: "b") == items)
        #expect(items.moving("x", onto: "b") == items)
    }

    @Test("Menu bar modules and AI providers persist the dragged order")
    @MainActor
    func preferencesReorder() {
        let prefs = MonitorPreferences.shared
        let original = prefs.moduleOrder
        defer { prefs.moduleOrder = original }
        prefs.moduleOrder = ModuleType.allCases.sorted { $0.defaultOrder < $1.defaultOrder }

        prefs.moveModule(.sensors, onto: .cpu)
        #expect(prefs.moduleOrder.first == .sensors)
        prefs.moveModule(.sensors, onto: .battery)
        #expect(prefs.moduleOrder.last == .sensors)
        #expect(Set(prefs.moduleOrder) == Set(ModuleType.allCases))
    }
}
