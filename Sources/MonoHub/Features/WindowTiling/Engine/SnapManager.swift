import AppKit
import CoreGraphics
import Foundation

@MainActor
final class SnapManager {
    static let shared = SnapManager()

    private enum DragState {
        case idle
        case pressed(origin: CGPoint)
        case candidate(window: AXUIElement, initialFrame: CGRect, origin: CGPoint, lastSample: CGPoint)
        case movingWindow(window: AXUIElement, layouts: [ScreenLayout])
        case ignored
    }

    private struct SnapTarget: Equatable {
        let action: WindowAction
        let screen: ScreenLayout
    }

    private let moveConfirmationDistance: CGFloat = 8
    private let maxUnconfirmedDragDistance: CGFloat = 24
    private let sampleStride: CGFloat = 4
    private let evaluationStride: CGFloat = 3

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
            if case .movingWindow(let window, _) = state, let snapTarget {
                WindowManager.shared.perform(action: snapTarget.action, on: window)
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
            guard point.distance(to: origin) >= moveConfirmationDistance else { return }
            guard let window = windows.window(at: origin),
                  windows.isManageable(window),
                  let frame = windows.frame(of: window) else {
                state = .ignored
                return
            }

            let isNearTitlebar = origin.y >= frame.minY - 4 && origin.y <= frame.minY + 56
            guard isNearTitlebar else {
                state = .ignored
                return
            }
            state = .candidate(window: window, initialFrame: frame, origin: origin, lastSample: origin)

        case .candidate(let window, let initialFrame, let origin, let lastSample):
            let distance = point.distance(to: origin)
            guard distance >= moveConfirmationDistance, point.distance(to: lastSample) >= sampleStride else { return }
            guard let frame = windows.frame(of: window), frame.size.equalTo(initialFrame.size) else {
                state = .ignored
                return
            }
            if !frame.origin.equalTo(initialFrame.origin) {
                state = .movingWindow(window: window, layouts: windows.screenLayouts())
                if TilePreferencesManager.shared.restoresSizeOnDrag {
                    windows.restoreSizeIfTiled(window, initialFrame: initialFrame, cursor: point)
                }
                updateSnapTarget(at: point)
            } else if distance > maxUnconfirmedDragDistance {
                state = .ignored
            } else {
                state = .candidate(window: window, initialFrame: initialFrame, origin: origin, lastSample: point)
            }

        case .movingWindow:
            updateSnapTarget(at: point)

        case .ignored:
            break
        }
    }

    private func updateSnapTarget(at point: CGPoint) {
        let prefs = TilePreferencesManager.shared
        guard prefs.isSnapEnabled, case .movingWindow(_, let layouts) = state else { return }
        if let lastEvaluatedPoint, point.distance(to: lastEvaluatedPoint) < evaluationStride {
            return
        }
        lastEvaluatedPoint = point

        guard let screen = ScreenLayout.screen(containing: point, in: layouts),
              let area = SnapArea.evaluate(
                  mousePoint: point,
                  screen: screen,
                  threshold: prefs.snapThreshold,
                  bottomEdge: prefs.bottomEdgeBehavior
              ) else {
            clearSnapTarget()
            return
        }

        let target = SnapTarget(action: area.action, screen: screen)
        guard target != snapTarget else { return }
        if target.action != snapTarget?.action && prefs.isSnapHapticEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        snapTarget = target

        guard prefs.isSnapPreviewEnabled else { return }
        let frame = TileCalculation.calculate(
            action: area.action,
            screen: screen,
            currentFrame: .zero,
            options: prefs.tileOptions
        )
        SnapPreviewPanel.shared.show(frame, on: screen, primaryScreenHeight: WindowManager.shared.primaryScreenHeight)
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
