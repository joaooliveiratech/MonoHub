import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal

@Observable
final class ScreenshotDocument {
    let baseImage: CGImage
    let scaleFactor: CGFloat
    let capturedAt = Date()

    var annotations: [AnnotationElement] = [] {
        didSet { invalidateCaches() }
    }

    var nextCounterIndex: Int {
        let highest = annotations.lazy.compactMap { element -> Int? in
            if case .counter(let counter) = element { return counter.number }
            return nil
        }.max() ?? 0
        return highest + 1
    }

    private static let maxHistoryDepth = 50

    @ObservationIgnored private var undoStack: [[AnnotationElement]] = []
    @ObservationIgnored private var redoStack: [[AnnotationElement]] = []
    @ObservationIgnored private var cachedCompositeImage: CGImage?
    @ObservationIgnored private var cachedCensoredBase: CGImage?
    @ObservationIgnored private var cachedCensorKey: [CensorAnnotation] = []

    private static let sharedCIContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .priorityRequestLow: false,
                .cacheIntermediates: false
            ])
        }
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false
        ])
    }()

    init(baseImage: CGImage, scaleFactor: CGFloat = 2.0) {
        self.baseImage = baseImage
        self.scaleFactor = max(1.0, scaleFactor)
    }

    var logicalSize: CGSize {
        CGSize(
            width: CGFloat(baseImage.width) / scaleFactor,
            height: CGFloat(baseImage.height) / scaleFactor
        )
    }

    func addAnnotation(_ annotation: AnnotationElement) {
        pushHistory()
        annotations.append(annotation)
    }

    func removeAnnotation(withId id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        pushHistory()
        annotations.removeAll(where: { $0.id == id })
    }

    func updateAnnotation(_ annotation: AnnotationElement) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }),
              annotations[index] != annotation else { return }
        pushHistory()
        annotations[index] = annotation
    }

    func moveAnnotation(withId id: UUID, by delta: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = annotations[index].moved(by: delta)
    }

    func commitMove(previousState: [AnnotationElement]) {
        pushHistory(state: previousState)
    }

    func annotation(withId id: UUID) -> AnnotationElement? {
        annotations.first(where: { $0.id == id })
    }

    func annotation(at point: CGPoint) -> AnnotationElement? {
        annotations.reversed().first(where: { $0.contains(point: point) })
    }

    private func pushHistory(state: [AnnotationElement]? = nil) {
        undoStack.append(state ?? annotations)
        if undoStack.count > Self.maxHistoryDepth {
            undoStack.removeFirst(undoStack.count - Self.maxHistoryDepth)
        }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func invalidateCaches() {
        cachedCompositeImage = nil
        if censors != cachedCensorKey {
            cachedCensoredBase = nil
        }
    }

    private var censors: [CensorAnnotation] {
        annotations.compactMap { element in
            if case .censor(let censor) = element { return censor }
            return nil
        }
    }

    var censoredBaseImage: CGImage {
        let currentCensors = censors
        if let cached = cachedCensoredBase, cachedCensorKey == currentCensors {
            return cached
        }

        let rendered = currentCensors.isEmpty
            ? baseImage
            : (applyCensors(to: baseImage, censors: currentCensors) ?? baseImage)

        cachedCensoredBase = rendered
        cachedCensorKey = currentCensors
        return rendered
    }

    func renderCompositeImage() -> CGImage? {
        if let cached = cachedCompositeImage {
            return cached
        }

        let workingImage = censoredBaseImage
        let width = baseImage.width
        let height = baseImage.height

        guard let ctx = ImageEncoder.makeContext(width: width, height: height, colorSpace: baseImage.colorSpace) else {
            return workingImage
        }

        ctx.draw(workingImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        ctx.saveGState()
        ctx.scaleBy(x: scaleFactor, y: scaleFactor)
        AnnotationRenderer.draw(annotations, in: ctx)
        ctx.restoreGState()

        let result = ctx.makeImage()
        cachedCompositeImage = result
        return result
    }

    private func applyCensors(to image: CGImage, censors: [CensorAnnotation]) -> CGImage? {
        var ciImage = CIImage(cgImage: image)
        let fullRect = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))

        for censor in censors {
            let pixelRect = CGRect(
                x: censor.rect.origin.x * scaleFactor,
                y: censor.rect.origin.y * scaleFactor,
                width: censor.rect.width * scaleFactor,
                height: censor.rect.height * scaleFactor
            )

            let region = pixelRect.intersection(fullRect)
            guard !region.isNull, region.width > 2, region.height > 2 else { continue }

            if let censored = censoredRegion(of: ciImage, in: region, censor: censor) {
                ciImage = censored.composited(over: ciImage)
            }
        }

        return Self.sharedCIContext.createCGImage(
            ciImage,
            from: fullRect,
            format: .RGBA8,
            colorSpace: image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                ?? CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB()
        )
    }

    private func censoredRegion(of image: CIImage, in region: CGRect, censor: CensorAnnotation) -> CIImage? {

        let localised = image
            .cropped(to: region)
            .clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))

        let localRegion = CGRect(origin: .zero, size: region.size)
        let minSide = min(region.width, region.height)
        let rebuilt: CIImage?

        switch censor.kind {
        case .pixelate:
            let block = Self.censorBlockSize(scale: censor.scale, scaleFactor: scaleFactor, minSide: minSide)
            rebuilt = Self.downsampled(localised, size: region.size, by: block)?
                .samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: block, y: block))

        case .blur:
            let factor = Self.censorBlurFactor(scale: censor.scale, scaleFactor: scaleFactor, minSide: minSide)

            rebuilt = Self.downsampled(localised, size: region.size, by: factor)
                .flatMap { Self.scaled($0.clampedToExtent(), by: factor) }
        }

        return rebuilt?
            .cropped(to: localRegion)
            .transformed(by: CGAffineTransform(translationX: region.minX, y: region.minY))
    }

    private static func downsampled(_ localised: CIImage, size: CGSize, by factor: CGFloat) -> CIImage? {
        let antiAlias = CIFilter.gaussianBlur()
        antiAlias.inputImage = localised
        antiAlias.radius = Float(min(max(factor / 2.0, 2.0), 12.0))

        guard let softened = antiAlias.outputImage,
              let small = Self.scaled(softened, by: 1.0 / factor) else { return nil }

        let smallRect = CGRect(
            x: 0,
            y: 0,
            width: (size.width / factor).rounded(.up),
            height: (size.height / factor).rounded(.up)
        )
        return small.cropped(to: smallRect)
    }

    static func censorBlockSize(scale: CGFloat, scaleFactor: CGFloat, minSide: CGFloat) -> CGFloat {
        min(max(scale * scaleFactor * 0.30, 8), max(8, minSide / 3))
    }

    static func censorBlurFactor(scale: CGFloat, scaleFactor: CGFloat, minSide: CGFloat) -> CGFloat {
        min(max(scale * scaleFactor * 0.18, 4), max(4, minSide / 5))
    }

    private static func scaled(_ image: CIImage, by factor: CGFloat) -> CIImage? {
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(factor)
        filter.aspectRatio = 1
        return filter.outputImage
    }

    enum ExportError: Error {
        case renderFailed
    }

    func exportImage(downscaleRetina: Bool) throws -> CGImage {
        guard let composite = renderCompositeImage() else { throw ExportError.renderFailed }
        guard downscaleRetina, scaleFactor > 1.0 else { return composite }
        return ImageEncoder.resized(composite, to: logicalSize) ?? composite
    }

    @discardableResult
    func copyToPasteboard() async -> Bool {
        guard let image = renderCompositeImage(),
              let pngData = try? await ImageEncoder.encodeInBackground(image, as: .png) else { return false }
        return PasteboardWriter.write(pngData: pngData)
    }

    func save(
        to url: URL,
        format explicitFormat: ExportFormat? = nil,
        quality: Double = ScreenshotPreferences.shared.jpegQuality,
        downscaleRetina: Bool = ScreenshotPreferences.shared.downscaleRetina
    ) throws {
        let format = explicitFormat ?? ExportFormat.inferred(fromExtension: url.pathExtension)
        let image = try exportImage(downscaleRetina: downscaleRetina)
        try ImageEncoder.encode(image, as: format, quality: quality).write(to: url, options: .atomic)
    }
}
