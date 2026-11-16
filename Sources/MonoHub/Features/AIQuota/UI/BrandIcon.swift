import SwiftUI

struct BrandIcon: View {
    let provider: ProviderType
    var size: CGFloat = 12.0
    var tinted: Bool = true

    var body: some View {
        Image(nsImage: provider.brandIcon)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(tinted ? AnyShapeStyle(provider.accentColor) : AnyShapeStyle(.foreground))
    }
}

struct BrandTile: View {
    let provider: ProviderType
    var size: CGFloat = 28

    var body: some View {
        BrandIcon(provider: provider, size: size * 0.56, tinted: false)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(provider.accentColor.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}
