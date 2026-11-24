import AppKit
import CoreGraphics
import Foundation

@MainActor
final class SnapManager {
    static let shared = SnapManager()

    private struct DragSessionContext {
        let window: AXUIElement
        let layouts: [ScreenLayout]
        let options: TileOptions
        let primaryScreenHeight: CGFloat
        let snapThreshold: CGFloat
        let bottomEdge: BottomEdgeBehavior
        let isSnapEnabled: Bool
        let isSnapPreviewEnabled: Bool
        let isSnapHapticEnabled: Bool
    }

    private enum DragState {
        case idle
        case pressed(origin: CGPoint)
        case candidate(window: AXUIElement, initialFrame: CGRect, origin: CGPoint, lastSample: CGPoint)
        case movingWindow(DragSessionContext)
        case ignored
    }

    private struct SnapTarget: Equatable {
        let action: WindowAction
        let screen: ScreenLayout
    }

    private let moveConfirmationDistanceSquared: CGFloat = 8 * 8
    private let maxUnconfirmedDragDistanceSquared: CGFloat = 24 * 24
    private let sampleStrideSquared: CGFloat = 4 * 4
    private let evaluationStrideSquared: CGFloat = 3 * 3

    private var pressMonitor: Any?
    private var dragMonitor: Any?
    private var state: DragState = .idle
    private var snapTarget: SnapTarget?
    private var lastEvaluatedPoint: CGPoint?

    private init() {}

    func reload() {
        let isNeeded = TilePreferencesManager.shared.isMouseTrackingNeeded && AXIsProcessTrusted()
        guard isNeeded != (pressMonitor != nil) else { return }
        stop()
        guard isNeeded else { return }
        pressMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.beginPress()
        }
    }

    func stop() {
        if let pressMonitor {
            NSEvent.removeMonitor(pressMonitor)
            self.pressMonitor = nil
        }
        endPress()
    }

    private func beginPress() {
        reset()
        state = .pressed(origin: mouseLocation())
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    private func endPress() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged:
            handleDrag(to: mouseLocation())
            if case .ignored = state { endPress() }
        case .leftMouseUp:
            if case .movingWindow(let context) = state, let snapTarget {
                WindowManager.shared.perform(action: snapTarget.action, on: context.window)
            }
            endPress()
        default:
            break
        }
    }

    private func mouseLocation() -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: WindowManager.shared.primaryScreenHeight - location.y)
    }

    private func handleDrag(to point: CGPoint) {
        let windows = WindowManager.shared

        switch state {
        case .idle:
            state = .pressed(origin: point)

        case .pressed(let origin):
            guard point.distanceSquared(to: origin) >= moveConfirmationDistanceSquared else { return }
            guard let window = windows.window(at: origin),
                  let inspection = windows.inspectWindow(window),
                  !inspection.isFullScreen else {
                state = .ignored
                return
            }

            let frame = inspection.frame
            let isNearTitlebar = origin.y >= frame.minY - 4 && origin.y <= frame.minY + 56
            guard isNearTitlebar else {
                state = .ignored
                return
            }
            state = .candidate(window: window, initialFrame: frame, origin: origin, lastSample: origin)

        case .candidate(let window, let initialFrame, let origin, let lastSample):
            let distanceSq = point.distanceSquared(to: origin)
            guard distanceSq >= moveConfirmationDistanceSquared,
                  point.distanceSquared(to: lastSample) >= sampleStrideSquared else { return }
            guard let frame = windows.frame(of: window), frame.size.equalTo(initialFrame.size) else {
                state = .ignored
                return
            }
            if !frame.origin.equalTo(initialFrame.origin) {
                let prefs = TilePreferencesManager.shared
                let context = DragSessionContext(
                    window: window,
                    layouts: windows.screenLayouts(),
                    options: prefs.tileOptions,
                    primaryScreenHeight: windows.primaryScreenHeight,
                    snapThreshold: prefs.snapThreshold,
                    bottomEdge: prefs.bottomEdgeBehavior,
                    isSnapEnabled: prefs.isSnapEnabled,
                    isSnapPreviewEnabled: prefs.isSnapPreviewEnabled,
                    isSnapHapticEnabled: prefs.isSnapHapticEnabled
                )
                state = .movingWindow(context)
                if prefs.restoresSizeOnDrag {
                    windows.restoreSizeIfTiled(window, initialFrame: initialFrame, cursor: point)
                }
                updateSnapTarget(at: point, context: context)
            } else if distanceSq > maxUnconfirmedDragDistanceSquared {
                state = .ignored
            } else {
                state = .candidate(window: window, initialFrame: initialFrame, origin: origin, lastSample: point)
            }

        case .movingWindow(let context):
            updateSnapTarget(at: point, context: context)

        case .ignored:
            break
        }
    }

    private func updateSnapTarget(at point: CGPoint, context: DragSessionContext) {
        guard context.isSnapEnabled else { return }
        if let lastEvaluatedPoint, point.distanceSquared(to: lastEvaluatedPoint) < evaluationStrideSquared {
            return
        }
        lastEvaluatedPoint = point

        guard let screen = ScreenLayout.screen(containing: point, in: context.layouts),
              let area = SnapArea.evaluate(
                  mousePoint: point,
                  screen: screen,
                  threshold: context.snapThreshold,
                  bottomEdge: context.bottomEdge
              ) else {
            clearSnapTarget()
            return
        }

        let target = SnapTarget(action: area.action, screen: screen)
        guard target != snapTarget else { return }
        if target.action != snapTarget?.action && context.isSnapHapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        snapTarget = target

        guard context.isSnapPreviewEnabled else { return }
        let frame = TileCalculation.calculate(
            action: area.action,
            screen: screen,
            currentFrame: .zero,
            options: context.options
        )
        SnapPreviewPanel.shared.show(
            frame,
            action: area.action,
            on: screen,
            primaryScreenHeight: context.primaryScreenHeight
        )
    }

    private func clearSnapTarget() {
        guard snapTarget != nil else { return }
        snapTarget = nil
        SnapPreviewPanel.shared.hide()
    }

    private func reset() {
        clearSnapTarget()
        state = .idle
        lastEvaluatedPoint = nil
    }
}
