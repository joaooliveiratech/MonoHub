import Foundation
import Testing
@testable import MonoHub

@Suite("Window Pacing Tests")
struct PacingTests {
    @Test("Ahead of pace calculation")
    func testAheadOfPace() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let limitWindowSeconds: Int64 = 18000

        let pacing = WindowPacing.calculate(
            usedPercent: 85.0,
            resetsAt: resetsAt,
            limitWindowSeconds: limitWindowSeconds,
            now: now,
            tolerance: 5.0
        )

        #expect(pacing != nil)
        #expect(pacing?.pace == .ahead)
        #expect(pacing?.pace.glyph == "↑")
        #expect(pacing?.paceLabel.contains("ahead") == true)
        #expect(pacing?.paceNote?.contains("Limit") == true)
    }

    @Test("Under pace calculation")
    func testUnderPace() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(14400)
        let limitWindowSeconds: Int64 = 18000

        let pacing = WindowPacing.calculate(
            usedPercent: 5.0,
            resetsAt: resetsAt,
            limitWindowSeconds: limitWindowSeconds,
            now: now,
            tolerance: 5.0
        )

        #expect(pacing != nil)
        #expect(pacing?.pace == .under)
        #expect(pacing?.pace.glyph == "↓")
        #expect(pacing?.paceLabel.contains("under") == true)
        #expect(pacing?.paceNote?.contains("left at reset") == true)
    }

    @Test("On track calculation within tolerance")
    func testOnTrack() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let limitWindowSeconds: Int64 = 18000

        let pacing = WindowPacing.calculate(
            usedPercent: 51.0,
            resetsAt: resetsAt,
            limitWindowSeconds: limitWindowSeconds,
            now: now,
            tolerance: 5.0
        )

        #expect(pacing != nil)
        #expect(pacing?.pace == .onTrack)
        #expect(pacing?.pace.glyph == "→")
        #expect(pacing?.paceLabel == "on track")
    }

    @Test("Limit reached note when usedPercent >= 100")
    func testLimitReached() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(1800)

        let pacing = WindowPacing.calculate(
            usedPercent: 100.0,
            resetsAt: resetsAt,
            limitWindowSeconds: 18000,
            now: now
        )

        #expect(pacing?.paceNote == "Limit reached")
    }

    @Test("Nil result when resetsAt is in the past")
    func testPastReset() {
        let now = Date()
        let past = now.addingTimeInterval(-100)

        let pacing = WindowPacing.calculate(
            usedPercent: 50.0,
            resetsAt: past,
            limitWindowSeconds: 18000,
            now: now
        )

        #expect(pacing == nil)
    }
}
