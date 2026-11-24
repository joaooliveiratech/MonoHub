import SwiftUI
import AppKit

struct NotchIdleAnimationView: View {
    let style: NotchIdleAnimation
    let speedMultiplier: Double
    let hasHardwareNotch: Bool
    let physicalNotchWidth: CGFloat
    var interactionMode: NotchIdleInteractionMode = NotchPreferences.shared.idleInteractionMode
    var compactSingleWing: Bool = false

    init(
        animation: NotchIdleAnimation,
        speed: Double = 1.0,
        hasHardwareNotch: Bool = false,
        physicalNotchWidth: CGFloat = 185,
        interactionMode: NotchIdleInteractionMode = NotchPreferences.shared.idleInteractionMode,
        compactSingleWing: Bool = false
    ) {
        self.style = animation
        self.speedMultiplier = speed
        self.hasHardwareNotch = hasHardwareNotch
        self.physicalNotchWidth = physicalNotchWidth
        self.interactionMode = interactionMode
        self.compactSingleWing = compactSingleWing
    }

    private static let matrixGlyphs: [String] = [
        "0", "1", "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ｶ", "ｷ", "ｸ", "ｹ", "ｺ", "ｻ", "ｼ", "ｽ", "ｾ", "ｿ",
        "ﾀ", "ﾁ", "ﾂ", "ﾃ", "ﾄ", "ﾅ", "ﾆ", "ﾇ", "ﾈ", "ﾉ", "ﾊ", "ﾋ", "ﾌ", "ﾍ", "ﾎ", "ﾏ", "ﾐ",
        "ﾑ", "ﾒ", "ﾓ", "ﾔ", "ﾕ", "ﾖ", "ﾗ", "ﾘ", "ﾙ", "ﾚ", "ﾛ", "ﾜ", "ﾝ", "Z", "X", "7", "9", "4"
    ]

    private static let terminalCommands: [String] = [
        "git push origin main",
        "swift test ✓ 312/312",
        "make install-clean",
        "docker compose up -d",
        "nvim src/main.swift",
        "cargo build --release",
        "kubectl get pods -A",
        "ssh prod@cluster-01",
        "brew upgrade --greedy"
    ]

    private static let elvishRunes: [String] = ["◈", "⌇", "⟡", "⟠", "❖", "✧"]

    var body: some View {
        let controller = NotchWindowController.shared
        let monitor = IdleInteractionMonitor.shared
        let isInteracting = monitor.isInteracting
        let shouldPause = style == .none
            || controller.isDisplayAsleep
            || AppExclusionManager.shared.isSuppressed
            || controller.isExpanded
            || (interactionMode != .alwaysActive && !isInteracting)
        let renderDate = shouldPause ? Date() : monitor.tickDate

        GeometryReader { geo in
            renderedContent(at: renderDate, size: geo.size)
        }
        .onAppear {
            guard NotchFeature.isRunning else { return }
            monitor.ensureStarted()
            monitor.registerActiveView()
        }
        .onDisappear {
            monitor.unregisterActiveView()
        }
        .onChange(of: style) { _, newStyle in
            guard NotchFeature.isRunning else { return }
            if newStyle != .none {
                monitor.ensureStarted()
            }
            monitor.syncRenderTimer()
        }
        .onChange(of: interactionMode) { _, _ in
            monitor.syncRenderTimer()
        }
    }

    @ViewBuilder
    private func renderedContent(at date: Date, size: CGSize) -> some View {
        let snapshot = IdleInteractionMonitor.shared.snapshot(
            at: date,
            mode: interactionMode,
            speedMultiplier: speedMultiplier
        )
        let t = snapshot.phase
        let activeStyle = style.resolved(at: date)

        Group {
            if compactSingleWing {
                compactWingCanvas(style: activeStyle, t: t, snapshot: snapshot, size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
            } else if hasHardwareNotch && physicalNotchWidth > 0 {
                let wingW = max(24, (size.width - physicalNotchWidth) / 2)
                HStack(spacing: 0) {
                    wingContainer(width: wingW, height: size.height, alignment: .center) {
                        leftWingCanvas(
                            style: activeStyle,
                            t: t,
                            snapshot: snapshot,
                            size: CGSize(width: wingW, height: size.height)
                        )
                    }

                    Color.clear
                        .frame(width: physicalNotchWidth, height: size.height)

                    wingContainer(width: wingW, height: size.height, alignment: .center) {
                        rightWingCanvas(
                            style: activeStyle,
                            t: t,
                            snapshot: snapshot,
                            size: CGSize(width: wingW, height: size.height)
                        )
                    }
                }
            } else {
                fullWidthCanvas(
                    style: activeStyle,
                    t: t,
                    snapshot: snapshot,
                    size: CGSize(width: max(40, size.width - 20), height: size.height)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
            }
        }
        .opacity(snapshot.isVisible ? 1.0 : 0.0)
    }

    private func wingContainer<Content: View>(
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: max(10, width - 8), height: height, alignment: alignment)
            .padding(.horizontal, 4)
            .clipped()
    }

    @ViewBuilder
    private func compactWingCanvas(
        style: NotchIdleAnimation,
        t: Double,
        snapshot: IdleInteractionSnapshot,
        size: CGSize
    ) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .bongoCat, .random:
            if size.width >= 56 {
                HStack(spacing: 4) {
                    bongoCatTerminalLeft(t: t, snapshot: snapshot)
                        .frame(maxWidth: 36, alignment: .leading)
                    bongoCatPawRight(t: t, snapshot: snapshot)
                        .frame(width: 40)
                }
            } else {
                bongoCatPawRight(t: t, snapshot: snapshot)
            }
        case .lordOfTheRings:
            HStack(spacing: 5) {
                sauronEyeCanvas(t: t, snapshot: snapshot, compact: true)
                    .frame(width: 24, height: 22)
                if size.width >= 52 {
                    oneRingCanvas(t: t, snapshot: snapshot, compact: true)
                        .frame(width: 24, height: 22)
                }
            }
        case .samurai:
            if size.width >= 56 {
                HStack(spacing: 4) {
                    samuraiSakuraLeft(t: t, snapshot: snapshot)
                        .frame(width: 26)
                    samuraiRoninRight(t: t, snapshot: snapshot, includeMoon: false)
                        .frame(width: 34)
                }
            } else {
                samuraiRoninRight(t: t, snapshot: snapshot, includeMoon: true)
            }
        case .starWars:
            if size.width >= 56 {
                starWarsFullScene(t: t, snapshot: snapshot)
            } else {
                starWarsRightWing(t: t, snapshot: snapshot, size: size)
            }
        case .pokemon:
            HStack(spacing: 4) {
                if size.width >= 52 {
                    pikachuCanvas(t: t, snapshot: snapshot, compact: true)
                        .frame(width: 26, height: 22)
                }
                pokeballCanvas(t: t, snapshot: snapshot, compact: true)
                    .frame(width: 24, height: 22)
            }
        case .pacman:
            if size.width >= 56 {
                pacmanFullScene(t: t, snapshot: snapshot)
            } else {
                pacmanWing(t: t, snapshot: snapshot, size: size, isRightWing: false)
            }
        case .matrix:
            matrixRainCanvas(t: t, snapshot: snapshot, seedOffset: 7)
        case .nyanCat:
            if size.width >= 56 {
                nyanCatFullScene(t: t, snapshot: snapshot)
            } else {
                nyanCatTrailWing(t: t, snapshot: snapshot, isRightWing: true)
            }
        case .dinoRunner:
            dinoRunnerScene(t: t, snapshot: snapshot)
        case .spaceInvaders:
            if size.width >= 56 {
                HStack(spacing: 4) {
                    spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: false)
                    spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: true)
                }
            } else {
                spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: true)
            }
        }
    }

    @ViewBuilder
    private func leftWingCanvas(
        style: NotchIdleAnimation,
        t: Double,
        snapshot: IdleInteractionSnapshot,
        size: CGSize
    ) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .bongoCat, .random:
            bongoCatTerminalLeft(t: t, snapshot: snapshot)
        case .lordOfTheRings:
            sauronEyeCanvas(t: t, snapshot: snapshot, compact: false)
        case .samurai:
            samuraiSakuraLeft(t: t, snapshot: snapshot)
        case .starWars:
            starWarsLeftWing(t: t, snapshot: snapshot, size: size)
        case .pokemon:
            pikachuCanvas(t: t, snapshot: snapshot, compact: false)
        case .pacman:
            pacmanWing(t: t, snapshot: snapshot, size: size, isRightWing: false)
        case .matrix:
            matrixRainCanvas(t: t, snapshot: snapshot, seedOffset: 0)
        case .nyanCat:
            nyanCatTrailWing(t: t, snapshot: snapshot, isRightWing: false)
        case .dinoRunner:
            dinoRunnerScene(t: t, snapshot: snapshot)
        case .spaceInvaders:
            spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: false)
        }
    }

    @ViewBuilder
    private func rightWingCanvas(
        style: NotchIdleAnimation,
        t: Double,
        snapshot: IdleInteractionSnapshot,
        size: CGSize
    ) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .bongoCat, .random:
            bongoCatPawRight(t: t, snapshot: snapshot)
        case .lordOfTheRings:
            oneRingCanvas(t: t, snapshot: snapshot, compact: false)
        case .samurai:
            samuraiRoninRight(t: t, snapshot: snapshot, includeMoon: false)
        case .starWars:
            starWarsRightWing(t: t, snapshot: snapshot, size: size)
        case .pokemon:
            pokeballCanvas(t: t, snapshot: snapshot, compact: false)
        case .pacman:
            pacmanWing(t: t, snapshot: snapshot, size: size, isRightWing: true)
        case .matrix:
            matrixRainCanvas(t: t, snapshot: snapshot, seedOffset: 17)
        case .nyanCat:
            nyanCatTrailWing(t: t, snapshot: snapshot, isRightWing: true)
        case .dinoRunner:
            dinoScoreWing(t: t, snapshot: snapshot)
        case .spaceInvaders:
            spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: true)
        }
    }

    @ViewBuilder
    private func fullWidthCanvas(
        style: NotchIdleAnimation,
        t: Double,
        snapshot: IdleInteractionSnapshot,
        size: CGSize
    ) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .bongoCat, .random:
            HStack(spacing: 8) {
                bongoCatTerminalLeft(t: t, snapshot: snapshot)
                Spacer(minLength: 4)
                bongoCatPawRight(t: t, snapshot: snapshot)
            }
        case .lordOfTheRings:
            HStack(spacing: 8) {
                sauronEyeCanvas(t: t, snapshot: snapshot, compact: false)
                oneRingCanvas(t: t, snapshot: snapshot, compact: false)
            }
        case .samurai:
            HStack(spacing: 6) {
                samuraiSakuraLeft(t: t, snapshot: snapshot)
                samuraiRoninRight(t: t, snapshot: snapshot, includeMoon: false)
            }
        case .starWars:
            starWarsFullScene(t: t, snapshot: snapshot)
        case .pokemon:
            HStack(spacing: 6) {
                pikachuCanvas(t: t, snapshot: snapshot, compact: false)
                pokeballCanvas(t: t, snapshot: snapshot, compact: false)
            }
        case .pacman:
            pacmanFullScene(t: t, snapshot: snapshot)
        case .matrix:
            matrixRainCanvas(t: t, snapshot: snapshot, seedOffset: 0)
        case .nyanCat:
            nyanCatFullScene(t: t, snapshot: snapshot)
        case .dinoRunner:
            HStack(spacing: 8) {
                dinoRunnerScene(t: t, snapshot: snapshot)
                dinoScoreWing(t: t, snapshot: snapshot)
            }
        case .spaceInvaders:
            HStack(spacing: 8) {
                spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: false)
                Spacer(minLength: 4)
                spaceInvadersWing(t: t, snapshot: snapshot, isRightWing: true)
            }
        }
    }

    private func bongoCatTerminalLeft(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        let isInteractive = interactionMode != .alwaysActive
        let visibleText: String

        if isInteractive {

            let totalStrokes = max(0, snapshot.strokeCount)
            if totalStrokes == 0 {
                visibleText = ""
            } else {
                let cycleLen = 20
                let cmdIdx = ((totalStrokes - 1) / cycleLen) % Self.terminalCommands.count
                let fullText = Self.terminalCommands[cmdIdx]
                let charPos = ((totalStrokes - 1) % cycleLen) + 1
                let count = min(fullText.count, charPos)
                visibleText = String(fullText.prefix(count))
            }
        } else {
            let cycleDuration = 4.2
            let cmdIdx = Int(t / cycleDuration) % Self.terminalCommands.count
            let fullText = Self.terminalCommands[cmdIdx]
            let localT = t.truncatingRemainder(dividingBy: cycleDuration)
            let typingWindow = 2.8
            let progress = min(1.0, max(0.0, localT / typingWindow))
            let count = max(1, min(fullText.count, Int(Double(fullText.count) * progress)))
            visibleText = String(fullText.prefix(count))
        }

        let cursorBlink = snapshot.isTypingNow || (Int(snapshot.ambientTime * 1.8) % 2 == 0)

        return HStack(spacing: 3) {
            Text("❯")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(snapshot.isTypingNow ? Color.mint : Color.mint.opacity(0.6))

            HStack(spacing: 1.5) {
                Text(visibleText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(snapshot.isTypingNow ? 0.95 : 0.70))
                    .lineLimit(1)

                RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                    .fill(snapshot.isTypingNow ? Color.mint : Color.white.opacity(0.65))
                    .frame(width: 4.5, height: 9.5)
                    .opacity(cursorBlink ? 1.0 : 0.15)
            }
        }
    }

    private func bongoCatPawRight(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        let isTyping = snapshot.isTypingNow
        let step = snapshot.strokeCount
        let leftPawDown = isTyping && (step % 2 == 0)
        let rightPawDown = isTyping && (step % 2 != 0)
        let blink = !isTyping && (Int(snapshot.ambientTime * 2.2) % 11 == 0)
        let noteSymbols = ["{", "}", ";", "⌘", "/", "*"]
        let floatingSymbol = noteSymbols[abs(step) % noteSymbols.count]
        let floatOffset = CGFloat((step % 3) * 2)

        return HStack(spacing: 3) {
            Text(floatingSymbol)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(step % 2 == 0 ? Color.pink : Color.cyan)
                .offset(y: isTyping ? (-3.0 - floatOffset) : 2.0)
                .opacity(isTyping ? min(1.0, snapshot.typingEnergy * 1.2) : 0.0)
                .frame(width: 10)

            Canvas { ctx, size in
                let cx = size.width * 0.5
                let cy = size.height * 0.54

                let deskRect = CGRect(x: cx - 16, y: cy + 5.0, width: 32, height: 3.5)
                let deskColor: Color = isTyping
                    ? (leftPawDown ? .pink.opacity(0.92) : .cyan.opacity(0.92))
                    : .white.opacity(0.28)
                ctx.fill(Path(roundedRect: deskRect, cornerRadius: 1.5), with: .color(deskColor))

                for k in 0..<4 {
                    let kx = cx - 12.0 + CGFloat(k) * 6.5
                    let isPressedKey = (leftPawDown && k < 2) || (rightPawDown && k >= 2)
                    let ky = isPressedKey ? (cy + 4.2) : (cy + 3.2)
                    let keyRect = CGRect(x: kx, y: ky, width: 4.5, height: 2.0)
                    let keyColor: Color = isPressedKey
                        ? (leftPawDown ? .pink : .cyan)
                        : .white.opacity(0.45)
                    ctx.fill(Path(roundedRect: keyRect, cornerRadius: 0.6), with: .color(keyColor))
                }

                let headBob: CGFloat = isTyping ? (step % 2 == 0 ? 0.6 : -0.4) : 0.0
                let headY = cy + 3.2 + headBob

                var head = Path()
                head.addArc(
                    center: CGPoint(x: cx, y: headY),
                    radius: 10.2,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false
                )
                head.closeSubpath()
                ctx.fill(head, with: .color(.white))

                var leftEar = Path()
                leftEar.move(to: CGPoint(x: cx - 8.8, y: headY - 4.5))
                leftEar.addLine(to: CGPoint(x: cx - 10.2, y: headY - 12.8))
                leftEar.addLine(to: CGPoint(x: cx - 3.2, y: headY - 8.2))
                leftEar.closeSubpath()
                ctx.fill(leftEar, with: .color(.white))

                var rightEar = Path()
                rightEar.move(to: CGPoint(x: cx + 8.8, y: headY - 4.5))
                rightEar.addLine(to: CGPoint(x: cx + 10.2, y: headY - 12.8))
                rightEar.addLine(to: CGPoint(x: cx + 3.2, y: headY - 8.2))
                rightEar.closeSubpath()
                ctx.fill(rightEar, with: .color(.white))

                let leftInner = CGRect(x: cx - 8.2, y: headY - 10.2, width: 2.4, height: 2.8)
                let rightInner = CGRect(x: cx + 5.8, y: headY - 10.2, width: 2.4, height: 2.8)
                ctx.fill(Path(ellipseIn: leftInner), with: .color(.pink.opacity(0.78)))
                ctx.fill(Path(ellipseIn: rightInner), with: .color(.pink.opacity(0.78)))

                if blink {
                    let lEye = CGRect(x: cx - 5.5, y: headY - 4.5, width: 3.0, height: 1.0)
                    let rEye = CGRect(x: cx + 2.5, y: headY - 4.5, width: 3.0, height: 1.0)
                    ctx.fill(Path(lEye), with: .color(.black))
                    ctx.fill(Path(rEye), with: .color(.black))
                } else {
                    let lEye = CGRect(x: cx - 5.0, y: headY - 5.4, width: 2.3, height: 2.3)
                    let rEye = CGRect(x: cx + 2.7, y: headY - 5.4, width: 2.3, height: 2.3)
                    ctx.fill(Path(ellipseIn: lEye), with: .color(.black))
                    ctx.fill(Path(ellipseIn: rEye), with: .color(.black))
                }

                ctx.fill(Path(ellipseIn: CGRect(x: cx - 6.8, y: headY - 3.0, width: 2.2, height: 1.3)), with: .color(.pink.opacity(0.55)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx + 4.6, y: headY - 3.0, width: 2.2, height: 1.3)), with: .color(.pink.opacity(0.55)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.1, y: headY - 3.3, width: 2.2, height: 1.5)), with: .color(.pink))

                let leftPawY: CGFloat = isTyping ? (leftPawDown ? (cy + 4.6) : (cy - 0.5)) : (cy + 3.2)
                let rightPawY: CGFloat = isTyping ? (rightPawDown ? (cy + 4.6) : (cy - 0.5)) : (cy + 3.2)
                let leftPaw = CGRect(x: cx - 12.5, y: leftPawY - 2.0, width: 5.5, height: 4.2)
                let rightPaw = CGRect(x: cx + 7.0, y: rightPawY - 2.0, width: 5.5, height: 4.2)
                ctx.fill(Path(ellipseIn: leftPaw), with: .color(.white))
                ctx.fill(Path(ellipseIn: rightPaw), with: .color(.white))
            }
            .frame(width: 36, height: 24)
        }
    }

    private func sauronEyeCanvas(t: Double, snapshot: IdleInteractionSnapshot, compact: Bool) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cy = h * 0.5
            let eyeX: CGFloat = compact ? (w * 0.5) : min(22, w * 0.42)
            let flare = snapshot.isActiveNow ? (0.85 + 0.15 * sin(t * 6.0)) : (0.55 + 0.15 * sin(snapshot.ambientTime * 2.0))

            let auraRect = CGRect(x: eyeX - 12, y: cy - 8.5, width: 24, height: 17)
            ctx.fill(
                Path(ellipseIn: auraRect),
                with: .color(Color(red: 1.0, green: 0.25, blue: 0.0).opacity(0.32 * flare))
            )

            var leftSpire = Path()
            leftSpire.move(to: CGPoint(x: eyeX - 11.5, y: cy + 9))
            leftSpire.addLine(to: CGPoint(x: eyeX - 9.0, y: cy - 9.5))
            leftSpire.addLine(to: CGPoint(x: eyeX - 6.5, y: cy + 9))
            leftSpire.closeSubpath()
            ctx.fill(leftSpire, with: .color(Color(white: 0.18)))

            var rightSpire = Path()
            rightSpire.move(to: CGPoint(x: eyeX + 6.5, y: cy + 9))
            rightSpire.addLine(to: CGPoint(x: eyeX + 9.0, y: cy - 9.5))
            rightSpire.addLine(to: CGPoint(x: eyeX + 11.5, y: cy + 9))
            rightSpire.closeSubpath()
            ctx.fill(rightSpire, with: .color(Color(white: 0.18)))

            let eyeRect = CGRect(x: eyeX - 8.5, y: cy - 4.5, width: 17, height: 9)
            ctx.fill(Path(ellipseIn: eyeRect), with: .color(Color(red: 1.0, green: 0.48, blue: 0.05)))
            let innerEye = CGRect(x: eyeX - 6.2, y: cy - 3.2, width: 12.4, height: 6.4)
            ctx.fill(Path(ellipseIn: innerEye), with: .color(Color(red: 1.0, green: 0.82, blue: 0.15)))

            let gazeOffset = CGFloat(sin(t * 1.9) * 2.0)
            let slitW: CGFloat = snapshot.isActiveNow ? 1.5 : 2.1
            let slitRect = CGRect(x: eyeX + gazeOffset - slitW * 0.5, y: cy - 4.0, width: slitW, height: 8.0)
            ctx.fill(Path(ellipseIn: slitRect), with: .color(.black))

            if !compact && w > 36 {
                for e in 0..<3 {
                    let phase = (t * (0.8 + Double(e) * 0.25) + Double(e) * 0.33).truncatingRemainder(dividingBy: 1.0)
                    let ex = eyeX + 13 + CGFloat(phase) * max(8, w - eyeX - 16)
                    let ey = cy + CGFloat(sin(t * 3.0 + Double(e) * 2.0) * 4.0)
                    let emberSize: CGFloat = snapshot.isActiveNow ? 2.2 : 1.5
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: ex, y: ey, width: emberSize, height: emberSize)),
                        with: .color(e % 2 == 0 ? .orange : .yellow)
                    )
                }
            }
        }
    }

    private func oneRingCanvas(t: Double, snapshot: IdleInteractionSnapshot, compact: Bool) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let cy = size.height * 0.5
            let rx: CGFloat = compact ? (w * 0.5) : max(16, w - 16)
            let isBlazing = snapshot.isActiveNow

            if !compact && w > 38 {
                let runeCount = min(3, Int((w - 28) / 10))
                for i in 0..<runeCount {
                    let runeIdx = (abs(snapshot.strokeCount) + i) % Self.elvishRunes.count
                    let rune = Self.elvishRunes[runeIdx]
                    let alpha = isBlazing ? (0.75 + 0.25 * sin(t * 5.0 + Double(i))) : 0.28
                    let text = Text(rune)
                        .font(.system(size: 8.5, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 1.0, green: isBlazing ? 0.52 : 0.72, blue: 0.12).opacity(alpha))
                    let tx = rx - 15 - CGFloat(i) * 9.5
                    if tx > 6 {
                        ctx.draw(text, at: CGPoint(x: tx, y: cy))
                    }
                }
            }

            if isBlazing {
                let glowRect = CGRect(x: rx - 10, y: cy - 10, width: 20, height: 20)
                ctx.fill(Path(ellipseIn: glowRect), with: .color(Color.orange.opacity(0.28)))
            }

            let wobble = CGFloat(sin(t * 2.4) * 1.2)
            let ringRect = CGRect(x: rx - 7.5, y: cy - 6.5, width: 15.0, height: 13.0 + wobble * 0.4)
            let ringPath = Path(ellipseIn: ringRect)
            ctx.stroke(
                ringPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.92, blue: 0.42),
                        Color(red: 0.95, green: 0.62, blue: 0.10),
                        Color(red: 1.0, green: 0.85, blue: 0.30)
                    ]),
                    startPoint: CGPoint(x: rx - 7, y: cy - 7),
                    endPoint: CGPoint(x: rx + 7, y: cy + 7)
                ),
                lineWidth: 3.2
            )

            if isBlazing {
                ctx.stroke(
                    Path(ellipseIn: ringRect.insetBy(dx: 1.2, dy: 1.2)),
                    with: .color(Color(red: 1.0, green: 0.32, blue: 0.05).opacity(0.85)),
                    lineWidth: 0.9
                )
            }
        }
    }

    private func samuraiSakuraLeft(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cy = h * 0.5

            let moonX: CGFloat = 14
            let moonRect = CGRect(x: moonX - 7.5, y: cy - 7.5, width: 15, height: 15)
            ctx.fill(
                Path(ellipseIn: moonRect),
                with: .color(Color(red: 0.92, green: 0.16, blue: 0.22).opacity(0.85))
            )

            for p in 0..<4 {
                let speed = 9.0 + Double(p) * 2.5
                let px = CGFloat((t * speed + Double(p * 17)).truncatingRemainder(dividingBy: Double(max(14, w))))
                let py = CGFloat(4 + (p * 5) % Int(max(8, h - 8))) + CGFloat(sin(t * 2.5 + Double(p)) * 1.8)
                let petal = CGRect(x: px - 2.0, y: py - 1.2, width: 3.8, height: 2.2)
                ctx.fill(
                    Path(ellipseIn: petal),
                    with: .color(Color(red: 1.0, green: 0.68, blue: 0.82).opacity(0.90))
                )
            }

            if snapshot.isActiveNow {
                var wind = Path()
                wind.move(to: CGPoint(x: 6, y: cy + 1))
                wind.addLine(to: CGPoint(x: max(18, w - 4), y: cy - 2))
                ctx.stroke(wind, with: .color(.cyan.opacity(0.75)), lineWidth: 1.2)
            }
        }
    }

    private func samuraiRoninRight(t: Double, snapshot: IdleInteractionSnapshot, includeMoon: Bool) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let cy = size.height * 0.5
            let sx = max(16, w - 16)
            let isSlashing = snapshot.isActiveNow
            let slashStep = abs(snapshot.strokeCount) % 2

            if includeMoon {
                let moonRect = CGRect(x: sx - 13, y: cy - 7.5, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: moonRect), with: .color(Color(red: 0.90, green: 0.15, blue: 0.20).opacity(0.65)))
            }

            for p in 0..<2 {
                let px = max(4, sx - 18 - CGFloat(p * 11)) + CGFloat(sin(t * 2.2 + Double(p)) * 2.5)
                let py = cy - 4 + CGFloat(p * 7)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: px, y: py, width: 3.2, height: 1.8)),
                    with: .color(Color(red: 1.0, green: 0.68, blue: 0.82).opacity(0.85))
                )
            }

            var torso = Path()
            torso.move(to: CGPoint(x: sx - 5.0, y: cy + 8.5))
            torso.addLine(to: CGPoint(x: sx - 3.2, y: cy - 1.5))
            torso.addLine(to: CGPoint(x: sx + 3.8, y: cy - 1.5))
            torso.addLine(to: CGPoint(x: sx + 5.5, y: cy + 8.5))
            torso.closeSubpath()
            ctx.fill(torso, with: .color(Color(white: 0.92)))

            let hatTilt: CGFloat = isSlashing ? (slashStep == 0 ? -0.8 : 0.8) : 0.0
            var kasa = Path()
            kasa.move(to: CGPoint(x: sx - 9.5, y: cy - 1.5 + hatTilt))
            kasa.addLine(to: CGPoint(x: sx + 0.2, y: cy - 8.2))
            kasa.addLine(to: CGPoint(x: sx + 9.5, y: cy - 1.5 - hatTilt))
            kasa.closeSubpath()
            ctx.fill(kasa, with: .color(Color(red: 0.95, green: 0.24, blue: 0.28)))

            ctx.fill(Path(CGRect(x: sx - 2.5, y: cy - 1.2, width: 2.2, height: 1.2)), with: .color(.cyan))

            if isSlashing {
                var slashArc = Path()
                let startDeg: Double = slashStep == 0 ? 135 : 210
                let endDeg: Double = slashStep == 0 ? 255 : 330
                slashArc.addArc(
                    center: CGPoint(x: sx - 2, y: cy + 1),
                    radius: 11.5,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(endDeg),
                    clockwise: false
                )
                ctx.stroke(
                    slashArc,
                    with: .color(slashStep == 0 ? .cyan : .white),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )

                var blade = Path()
                blade.move(to: CGPoint(x: sx - 2, y: cy + 2))
                blade.addLine(to: CGPoint(x: sx - 13, y: slashStep == 0 ? (cy - 5) : (cy + 5)))
                ctx.stroke(blade, with: .color(.white), lineWidth: 1.5)
            } else {

                var saya = Path()
                saya.move(to: CGPoint(x: sx - 6.5, y: cy + 2.5))
                saya.addLine(to: CGPoint(x: sx + 6.5, y: cy + 5.5))
                ctx.stroke(saya, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
            }
        }
    }

    private func pikachuCanvas(t: Double, snapshot: IdleInteractionSnapshot, compact: Bool) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let cy = size.height * 0.52
            let px: CGFloat = compact ? (w * 0.5) : 16
            let bob = CGFloat(sin(t * 4.2) * (snapshot.isActiveNow ? 1.5 : 0.6))
            let py = cy + bob
            let pikaYellow = Color(red: 1.0, green: 0.86, blue: 0.12)

            var tail = Path()
            tail.move(to: CGPoint(x: px - 6, y: py + 4))
            tail.addLine(to: CGPoint(x: px - 10, y: py + 1))
            tail.addLine(to: CGPoint(x: px - 8, y: py))
            tail.addLine(to: CGPoint(x: px - 12, y: py - 4))
            ctx.stroke(tail, with: .color(pikaYellow), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

            var lEar = Path()
            lEar.move(to: CGPoint(x: px - 5.0, y: py - 3.5))
            lEar.addLine(to: CGPoint(x: px - 7.5, y: py - 11.0))
            lEar.addLine(to: CGPoint(x: px - 2.0, y: py - 5.5))
            lEar.closeSubpath()
            ctx.fill(lEar, with: .color(pikaYellow))
            ctx.fill(Path(ellipseIn: CGRect(x: px - 7.6, y: py - 11.0, width: 2.4, height: 2.4)), with: .color(.black))

            var rEar = Path()
            rEar.move(to: CGPoint(x: px + 2.0, y: py - 5.5))
            rEar.addLine(to: CGPoint(x: px + 7.5, y: py - 10.5))
            rEar.addLine(to: CGPoint(x: px + 5.5, y: py - 3.0))
            rEar.closeSubpath()
            ctx.fill(rEar, with: .color(pikaYellow))
            ctx.fill(Path(ellipseIn: CGRect(x: px + 5.6, y: py - 10.5, width: 2.4, height: 2.4)), with: .color(.black))

            let headRect = CGRect(x: px - 6.5, y: py - 6.0, width: 13.0, height: 11.5)
            ctx.fill(Path(roundedRect: headRect, cornerRadius: 4.5), with: .color(pikaYellow))

            ctx.fill(Path(ellipseIn: CGRect(x: px - 4.2, y: py - 2.8, width: 2.2, height: 2.2)), with: .color(.black))
            ctx.fill(Path(ellipseIn: CGRect(x: px + 2.0, y: py - 2.8, width: 2.2, height: 2.2)), with: .color(.black))

            let cheekGlow: CGFloat = snapshot.isActiveNow ? 3.0 : 2.3
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5.5, y: py + 0.2, width: cheekGlow, height: cheekGlow)), with: .color(.red))
            ctx.fill(Path(ellipseIn: CGRect(x: px + 2.6, y: py + 0.2, width: cheekGlow, height: cheekGlow)), with: .color(.red))

            if !compact && snapshot.isActiveNow && w > 34 {
                var bolt = Path()
                let startX = px + 8
                let endX = max(startX + 10, w - 4)
                let midX = (startX + endX) * 0.5
                let jitter = CGFloat((abs(snapshot.strokeCount) % 2 == 0) ? -3.2 : 3.2)
                bolt.move(to: CGPoint(x: startX, y: py))
                bolt.addLine(to: CGPoint(x: midX - 2, y: py + jitter))
                bolt.addLine(to: CGPoint(x: midX + 2, y: py - jitter))
                bolt.addLine(to: CGPoint(x: endX, y: py))
                ctx.stroke(bolt, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func pokeballCanvas(t: Double, snapshot: IdleInteractionSnapshot, compact: Bool) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let cy = size.height * 0.5
            let bx: CGFloat = compact ? (w * 0.5) : max(15, w - 15)
            let isShaking = snapshot.isActiveNow
            let wobble = CGFloat(sin(isShaking ? (t * 8.5) : (snapshot.ambientTime * 2.2)) * (isShaking ? 2.2 : 0.6))
            let cx = bx + wobble
            let r: CGFloat = 7.2

            if isShaking {
                for s in 0..<3 {
                    let angle = t * 5.0 + Double(s) * 2.1
                    let sx = cx + CGFloat(cos(angle) * 10.0)
                    let sy = cy + CGFloat(sin(angle) * 8.0)
                    ctx.fill(Path(ellipseIn: CGRect(x: sx - 1.2, y: sy - 1.2, width: 2.4, height: 2.4)), with: .color(.yellow))
                }
            }

            var bottomHalf = Path()
            bottomHalf.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            bottomHalf.closeSubpath()
            ctx.fill(bottomHalf, with: .color(.white))

            var topHalf = Path()
            topHalf.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            topHalf.closeSubpath()
            ctx.fill(topHalf, with: .color(Color(red: 0.95, green: 0.18, blue: 0.20)))

            ctx.fill(Path(CGRect(x: cx - r, y: cy - 1.0, width: r * 2, height: 2.0)), with: .color(.black))

            let btnOuter = CGRect(x: cx - 2.8, y: cy - 2.8, width: 5.6, height: 5.6)
            let btnInner = CGRect(x: cx - 1.8, y: cy - 1.8, width: 3.6, height: 3.6)
            ctx.fill(Path(ellipseIn: btnOuter), with: .color(.black))
            let btnColor: Color = (isShaking && Int(t * 6.0) % 2 == 0) ? .yellow : .white
            ctx.fill(Path(ellipseIn: btnInner), with: .color(btnColor))
        }
    }

    private func starWarsLeftWing(t: Double, snapshot: IdleInteractionSnapshot, size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cy = h * 0.5

            for i in 0..<4 {
                let speed = Double(8 + i * 3)
                let sx = w - CGFloat((t * speed + Double(i * 19)).truncatingRemainder(dividingBy: Double(max(12, w))))
                let sy = CGFloat(5 + (i * 5) % Int(max(8, h - 10)))
                ctx.fill(Path(CGRect(x: sx, y: sy, width: 3.0, height: 1.0)), with: .color(.white.opacity(0.42)))
            }

            let bob = CGFloat(sin(snapshot.ambientTime * 2.4) * 2.0)
            let xwX: CGFloat = 13
            let xwY = cy + bob

            drawXWing(ctx: &ctx, center: CGPoint(x: xwX, y: xwY))

            if snapshot.isActiveNow {
                let phase = (t * 1.15).truncatingRemainder(dividingBy: 1.0)
                let lx = xwX + 9 + CGFloat(phase) * max(10, w - xwX - 12)
                let bolt1 = CGRect(x: lx, y: xwY - 3.5, width: 7, height: 1.5)
                let bolt2 = CGRect(x: lx, y: xwY + 2.0, width: 7, height: 1.5)
                ctx.fill(Path(roundedRect: bolt1, cornerRadius: 0.75), with: .color(.red))
                ctx.fill(Path(roundedRect: bolt2, cornerRadius: 0.75), with: .color(.red))
            }
        }
    }

    private func starWarsRightWing(t: Double, snapshot: IdleInteractionSnapshot, size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cy = h * 0.5

            for i in 0..<4 {
                let speed = Double(9 + i * 3)
                let sx = w - CGFloat((t * speed + Double(i * 13)).truncatingRemainder(dividingBy: Double(max(12, w))))
                let sy = CGFloat(5 + (i * 6) % Int(max(8, h - 10)))
                ctx.fill(Path(CGRect(x: sx, y: sy, width: 3.0, height: 1.0)), with: .color(.white.opacity(0.42)))
            }

            let tieBob = CGFloat(cos(snapshot.ambientTime * 2.6) * 2.2)
            let tx = max(18, w - 14)
            let ty = cy + tieBob

            if snapshot.isActiveNow {
                let phase = (t * 1.15 + 0.45).truncatingRemainder(dividingBy: 1.0)
                let lx = (tx - 10) - CGFloat(phase) * max(10, tx - 14)
                let bolt = CGRect(x: lx, y: ty - 0.8, width: 7, height: 1.6)
                ctx.fill(Path(roundedRect: bolt, cornerRadius: 0.8), with: .color(.green))
            }

            drawTIEFighter(ctx: &ctx, center: CGPoint(x: tx, y: ty))
        }
    }

    private func starWarsFullScene(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cy = h * 0.5

            for i in 0..<7 {
                let speed = Double(10 + i * 3)
                let sx = w - CGFloat((t * speed + Double(i * 23)).truncatingRemainder(dividingBy: Double(max(20, w))))
                let sy = CGFloat(4 + (i * 7) % Int(max(8, h - 8)))
                ctx.fill(Path(CGRect(x: sx, y: sy, width: 3.5, height: 1.0)), with: .color(.white.opacity(0.40)))
            }

            let xwX: CGFloat = 16
            let xwY = cy + CGFloat(sin(snapshot.ambientTime * 2.4) * 2.2)
            let tx: CGFloat = max(40, w - 16)
            let ty = cy + CGFloat(cos(snapshot.ambientTime * 2.6) * 2.2)

            if snapshot.isActiveNow {
                let travel = max(20, tx - xwX - 24)
                let redPhase = CGFloat((t * 0.95).truncatingRemainder(dividingBy: 1.0))
                let redX = xwX + 10 + redPhase * travel
                ctx.fill(Path(roundedRect: CGRect(x: redX, y: xwY - 3.0, width: 8, height: 1.5), cornerRadius: 0.75), with: .color(.red))
                ctx.fill(Path(roundedRect: CGRect(x: redX, y: xwY + 1.5, width: 8, height: 1.5), cornerRadius: 0.75), with: .color(.red))

                let greenPhase = CGFloat((t * 0.95 + 0.5).truncatingRemainder(dividingBy: 1.0))
                let greenX = (tx - 16) - greenPhase * travel
                ctx.fill(Path(roundedRect: CGRect(x: greenX, y: ty - 0.8, width: 8, height: 1.6), cornerRadius: 0.8), with: .color(.green))
            }

            drawXWing(ctx: &ctx, center: CGPoint(x: xwX, y: xwY))
            drawTIEFighter(ctx: &ctx, center: CGPoint(x: tx, y: ty))
        }
    }

    private func drawXWing(ctx: inout GraphicsContext, center: CGPoint) {
        var sFoil1 = Path()
        sFoil1.move(to: CGPoint(x: center.x - 5.5, y: center.y - 4.8))
        sFoil1.addLine(to: CGPoint(x: center.x + 3.5, y: center.y + 4.8))
        var sFoil2 = Path()
        sFoil2.move(to: CGPoint(x: center.x - 5.5, y: center.y + 4.8))
        sFoil2.addLine(to: CGPoint(x: center.x + 3.5, y: center.y - 4.8))
        ctx.stroke(sFoil1, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
        ctx.stroke(sFoil2, with: .color(.white.opacity(0.85)), lineWidth: 1.4)

        let fuselage = CGRect(x: center.x - 6.5, y: center.y - 1.4, width: 13.5, height: 2.8)
        ctx.fill(Path(roundedRect: fuselage, cornerRadius: 1), with: .color(.white))
        let engineGlow = CGRect(x: center.x - 8.5, y: center.y - 1.8, width: 2.6, height: 3.6)
        ctx.fill(Path(ellipseIn: engineGlow), with: .color(.orange))
    }

    private func drawTIEFighter(ctx: inout GraphicsContext, center: CGPoint) {
        let leftWing = CGRect(x: center.x - 6.8, y: center.y - 5.8, width: 1.8, height: 11.6)
        let rightWing = CGRect(x: center.x + 5.0, y: center.y - 5.8, width: 1.8, height: 11.6)
        let strut = CGRect(x: center.x - 5.8, y: center.y - 0.8, width: 11.6, height: 1.6)
        let pod = CGRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)
        ctx.fill(Path(leftWing), with: .color(.cyan.opacity(0.9)))
        ctx.fill(Path(rightWing), with: .color(.cyan.opacity(0.9)))
        ctx.fill(Path(strut), with: .color(.gray))
        ctx.fill(Path(ellipseIn: pod), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 1.7, y: center.y - 1.7, width: 3.4, height: 3.4)), with: .color(.black))
    }

    private func pacmanWing(
        t: Double,
        snapshot: IdleInteractionSnapshot,
        size: CGSize,
        isRightWing: Bool
    ) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let cy = canvasSize.height * 0.5
            let frightened = Int(t / 7.0) % 2 == 1

            if !isRightWing {
                for d in 0..<4 {
                    let dx = CGFloat(8 + d * 11)
                    if dx < w - 18 {
                        let dot = CGRect(x: dx, y: cy - 1.4, width: 2.8, height: 2.8)
                        ctx.fill(Path(ellipseIn: dot), with: .color(.yellow.opacity(0.8)))
                    }
                }
                let mouth = snapshot.isActiveNow ? (abs(sin(t * 5.2)) * 36.0) : 16.0
                let px = max(14, w - 14)
                var pac = Path()
                pac.move(to: CGPoint(x: px, y: cy))
                pac.addArc(
                    center: CGPoint(x: px, y: cy),
                    radius: 6.8,
                    startAngle: .degrees(mouth),
                    endAngle: .degrees(360 - mouth),
                    clockwise: false
                )
                pac.closeSubpath()
                ctx.fill(pac, with: .color(.yellow))
            } else {
                let ghostColors: [Color] = frightened ? [.blue, .blue, .blue] : [.red, .pink, .cyan]
                for (idx, color) in ghostColors.enumerated() {
                    let gx = CGFloat(10 + idx * 16)
                    guard gx + 8 <= w else { continue }
                    let gy = cy + CGFloat(sin(snapshot.ambientTime * 3.0 + Double(idx)) * 1.2)
                    drawGhost(ctx: &ctx, center: CGPoint(x: gx, y: gy), color: color, frightened: frightened)
                }
            }
        }
    }

    private func pacmanFullScene(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        Canvas { ctx, canvasSize in
            let w = canvasSize.width
            let cy = canvasSize.height * 0.5
            let frightened = Int(t / 7.0) % 2 == 1
            let progress = CGFloat((t * 0.16).truncatingRemainder(dividingBy: 1.0))
            let startX: CGFloat = 44
            let endX: CGFloat = max(startX + 20, w - 14)
            let pacX = startX + progress * (endX - startX)

            var dotX: CGFloat = startX + 12
            while dotX < w - 10 {
                if dotX > pacX + 8 {
                    let isPower = Int(dotX) % 44 < 11
                    let r: CGFloat = isPower ? 2.5 : 1.4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: dotX - r, y: cy - r, width: r * 2, height: r * 2)),
                        with: .color(.yellow.opacity(0.85))
                    )
                }
                dotX += 11
            }

            let mouth = snapshot.isActiveNow ? (abs(sin(t * 5.5)) * 36.0) : 16.0
            var pac = Path()
            pac.move(to: CGPoint(x: pacX, y: cy))
            pac.addArc(
                center: CGPoint(x: pacX, y: cy),
                radius: 6.8,
                startAngle: .degrees(mouth),
                endAngle: .degrees(360 - mouth),
                clockwise: false
            )
            pac.closeSubpath()
            ctx.fill(pac, with: .color(.yellow))

            let colors: [Color] = frightened ? [.blue, .blue] : [.red, .pink]
            for (i, c) in colors.enumerated() {
                let gx = pacX - CGFloat(16 + i * 15)
                guard gx >= 10 else { continue }
                let gy = cy + CGFloat(sin(snapshot.ambientTime * 3.0 + Double(i)) * 1.0)
                drawGhost(ctx: &ctx, center: CGPoint(x: gx, y: gy), color: c, frightened: frightened)
            }
        }
    }

    private func drawGhost(ctx: inout GraphicsContext, center: CGPoint, color: Color, frightened: Bool) {
        let r: CGFloat = 5.8
        var p = Path()
        p.addArc(
            center: CGPoint(x: center.x, y: center.y - 1),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: center.x + r, y: center.y + r))
        p.addLine(to: CGPoint(x: center.x + r * 0.33, y: center.y + r - 2))
        p.addLine(to: CGPoint(x: center.x, y: center.y + r))
        p.addLine(to: CGPoint(x: center.x - r * 0.33, y: center.y + r - 2))
        p.addLine(to: CGPoint(x: center.x - r, y: center.y + r))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))

        let eyeColor: Color = frightened ? .yellow : .white
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3.3, y: center.y - 2.8, width: 2.3, height: 2.8)), with: .color(eyeColor))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x + 1.0, y: center.y - 2.8, width: 2.3, height: 2.8)), with: .color(eyeColor))
        if !frightened {
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 2.1, y: center.y - 1.9, width: 1.3, height: 1.5)), with: .color(.blue))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x + 2.1, y: center.y - 1.9, width: 1.3, height: 1.5)), with: .color(.blue))
        }
    }

    private func matrixRainCanvas(t: Double, snapshot: IdleInteractionSnapshot, seedOffset: Int) -> some View {
        Canvas { ctx, size in
            let colWidth: CGFloat = 9.5
            let cols = max(3, Int(size.width / colWidth))
            let totalWrap = Double(max(22, size.height + 16))

            for c in 0..<cols {
                let seed = c + seedOffset
                let colSpeed = 8.0 + Double((seed * 7) % 4) * 2.2
                let headY = CGFloat((t * colSpeed + Double(seed * 11)).truncatingRemainder(dividingBy: totalWrap)) - 4

                for trail in 0..<3 {
                    let y = headY - CGFloat(trail) * 6.8
                    guard y >= -3 && y <= size.height + 2 else { continue }
                    let cellRow = abs(Int(y / 6.5)) + seed * 5 + (trail == 0 ? Int(t * 2.0) : 0)
                    let char = Self.matrixGlyphs[cellRow % Self.matrixGlyphs.count]
                    let color: Color = trail == 0
                        ? Color(red: 0.82, green: 1.0, blue: 0.86)
                        : Color(red: 0.0, green: 0.90, blue: 0.28).opacity(trail == 1 ? 0.72 : 0.34)
                    let text = Text(char)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                    ctx.draw(text, at: CGPoint(x: CGFloat(c) * colWidth + 4.5, y: y))
                }
            }
        }
    }

    private func nyanCatTrailWing(t: Double, snapshot: IdleInteractionSnapshot, isRightWing: Bool) -> some View {
        Canvas { ctx, size in
            drawNyanRainbowAndStars(ctx: &ctx, size: size, t: t, includeCat: isRightWing)
        }
    }

    private func nyanCatFullScene(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        Canvas { ctx, size in
            drawNyanRainbowAndStars(ctx: &ctx, size: size, t: t, includeCat: true)
        }
    }

    private func drawNyanRainbowAndStars(ctx: inout GraphicsContext, size: CGSize, t: Double, includeCat: Bool) {
        let rainbowColors: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]
        let cy = size.height * 0.5
        let w = size.width

        for i in 0..<4 {
            let sx = w - CGFloat((t * 14.0 + Double(i * 29)).truncatingRemainder(dividingBy: Double(max(12, w))))
            let sy: CGFloat = (i % 2 == 0) ? 4.0 : (size.height - 4.0)
            ctx.fill(Path(CGRect(x: sx, y: sy, width: 2.0, height: 2.0)), with: .color(.white.opacity(0.55)))
        }

        let endRainbowX = includeCat ? max(12, w - 20) : w
        let segW: CGFloat = 6.0
        let waveSegments = max(2, Int(endRainbowX / segW))
        let stripeH: CGFloat = 1.9

        for s in 0..<waveSegments {
            let x = CGFloat(s) * segW
            let waveOffset = CGFloat(sin(t * 4.2 + Double(s) * 0.7) * 1.6)
            for (cIdx, color) in rainbowColors.enumerated() {
                let y = cy - 5.7 + CGFloat(cIdx) * stripeH + waveOffset
                let rect = CGRect(x: x, y: y, width: segW + 0.5, height: stripeH)
                ctx.fill(Path(rect), with: .color(color.opacity(0.92)))
            }
        }

        if includeCat {
            let catX = max(16, w - 15)
            let bob = CGFloat(sin(t * 4.8) * 1.2)

            let tartRect = CGRect(x: catX - 11, y: cy - 6.0 + bob, width: 13.5, height: 11.5)
            ctx.fill(Path(roundedRect: tartRect, cornerRadius: 2.2), with: .color(Color(red: 0.96, green: 0.78, blue: 0.52)))
            let frostingRect = tartRect.insetBy(dx: 1.2, dy: 1.2)
            ctx.fill(Path(roundedRect: frostingRect, cornerRadius: 1.8), with: .color(Color(red: 1.0, green: 0.55, blue: 0.82)))

            let headRect = CGRect(x: catX - 1.0, y: cy - 4.2 + bob, width: 8.5, height: 7.5)
            ctx.fill(Path(roundedRect: headRect, cornerRadius: 2.0), with: .color(.gray))
            var lEar = Path()
            lEar.move(to: CGPoint(x: catX, y: cy - 4.0 + bob))
            lEar.addLine(to: CGPoint(x: catX + 1.2, y: cy - 7.0 + bob))
            lEar.addLine(to: CGPoint(x: catX + 3.0, y: cy - 4.0 + bob))
            ctx.fill(lEar, with: .color(.gray))

            var rEar = Path()
            rEar.move(to: CGPoint(x: catX + 4.2, y: cy - 4.0 + bob))
            rEar.addLine(to: CGPoint(x: catX + 6.0, y: cy - 7.0 + bob))
            rEar.addLine(to: CGPoint(x: catX + 7.2, y: cy - 4.0 + bob))
            ctx.fill(rEar, with: .color(.gray))

            ctx.fill(Path(CGRect(x: catX + 1.8, y: cy - 1.8 + bob, width: 1.4, height: 1.4)), with: .color(.black))
            ctx.fill(Path(CGRect(x: catX + 4.8, y: cy - 1.8 + bob, width: 1.4, height: 1.4)), with: .color(.black))
        }
    }

    private func dinoScoreWing(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        let score: Int = {
            if interactionMode == .alwaysActive {
                return Int(t * 8.0) % 99999
            } else {
                return (snapshot.strokeCount * 10 + Int(t * 3.0)) % 99999
            }
        }()
        return HStack(spacing: 3) {
            Text("HI")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.85))
            Text(String(format: "%05d", score))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.90))
        }
    }

    private func dinoRunnerScene(t: Double, snapshot: IdleInteractionSnapshot) -> some View {
        Canvas { ctx, size in
            let w = size.width
            let groundY = size.height * 0.78

            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: 1)), with: .color(.white.opacity(0.35)))

            let cycle = (t * 0.36).truncatingRemainder(dividingBy: 1.0)
            let cactusX = w - CGFloat(cycle) * (w + 14) + 7
            let cactusRect = CGRect(x: cactusX, y: groundY - 7.5, width: 3.2, height: 7.5)
            ctx.fill(Path(roundedRect: cactusRect, cornerRadius: 1), with: .color(.green.opacity(0.92)))

            let dinoX: CGFloat = 14
            let dist = abs(cactusX - dinoX)
            let jumpOffset: CGFloat = dist < 15 ? -CGFloat(sin(Double(1.0 - dist / 15.0) * .pi) * 8.5) : 0
            let dy = groundY + jumpOffset

            let head = CGRect(x: dinoX, y: dy - 11.5, width: 6.8, height: 4.8)
            let torso = CGRect(x: dinoX - 2.8, y: dy - 7.8, width: 5.8, height: 5.6)
            let tail = CGRect(x: dinoX - 5.5, y: dy - 6.8, width: 2.8, height: 2.8)
            let legStep = snapshot.isActiveNow && (Int(t * 6.5) % 2 == 0)
            let leg1 = CGRect(x: dinoX - 2.0, y: dy - (legStep ? 1.8 : 2.8), width: 1.7, height: 2.5)
            let leg2 = CGRect(x: dinoX + 1.0, y: dy - (legStep ? 2.8 : 1.8), width: 1.7, height: 2.5)

            for r in [head, torso, tail, leg1, leg2] {
                ctx.fill(Path(r), with: .color(.white))
            }
            ctx.fill(Path(CGRect(x: dinoX + 4.3, y: dy - 10.5, width: 1.2, height: 1.2)), with: .color(.black))
        }
    }

    private func spaceInvadersWing(
        t: Double,
        snapshot: IdleInteractionSnapshot,
        isRightWing: Bool
    ) -> some View {
        Canvas { ctx, size in
            let cy = size.height * 0.38
            let shift = CGFloat(sin(t * 1.6) * 3.5)
            let count = max(1, min(3, Int(size.width / 20)))
            let armsUp = Int(t * 2.0) % 2 == 0

            for i in 0..<count {
                let ix = 11 + CGFloat(i) * 18 + shift
                let color: Color = isRightWing ? (i % 2 == 0 ? .mint : .pink) : (i % 2 == 0 ? .cyan : .yellow)
                let body = CGRect(x: ix - 4.5, y: cy - 3.5, width: 9.0, height: 5.2)
                let arms = CGRect(x: ix - 6.5, y: armsUp ? (cy - 3.0) : (cy - 1.0), width: 13.0, height: 2.4)
                ctx.fill(Path(roundedRect: body, cornerRadius: 1), with: .color(color))
                ctx.fill(Path(roundedRect: arms, cornerRadius: 0.8), with: .color(color))
                ctx.fill(Path(CGRect(x: ix - 2.8, y: cy - 1.8, width: 1.5, height: 1.5)), with: .color(.black))
                ctx.fill(Path(CGRect(x: ix + 1.3, y: cy - 1.8, width: 1.5, height: 1.5)), with: .color(.black))
            }

            let shipX = size.width * 0.5 - shift * 0.6
            let shipY = size.height - 4.0
            ctx.fill(Path(roundedRect: CGRect(x: shipX - 4.5, y: shipY, width: 9.0, height: 2.4), cornerRadius: 0.8), with: .color(.green))
            ctx.fill(Path(CGRect(x: shipX - 1.0, y: shipY - 1.8, width: 2.0, height: 2.0)), with: .color(.green))

            if snapshot.isActiveNow {
                let laserPhase = CGFloat((t * 1.1 + (isRightWing ? 0.5 : 0)).truncatingRemainder(dividingBy: 1.0))
                let ly = (shipY - 2.0) - laserPhase * (shipY - 4.0)
                ctx.fill(Path(CGRect(x: shipX - 0.7, y: ly, width: 1.4, height: 4.0)), with: .color(.green))
            }
        }
    }
}
