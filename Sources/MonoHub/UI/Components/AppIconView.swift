import AppKit
import SwiftUI

struct AppIconView: View {
    let size: CGFloat

    init(size: CGFloat = 64) {
        self.size = size
    }

    private static let resolvedIcon: NSImage? = {
        if let image = NSImage(named: NSImage.Name("AppIcon")), image.isValid, image.size.width > 0 {
            return image
        }
        if let image = NSApplication.shared.applicationIconImage, image.isValid, image.size.width > 0 {
            return image
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path), image.isValid {
            return image
        }
        return nil
    }()

    var body: some View {
        if let icon = Self.resolvedIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            HubIcon(systemName: "square.grid.2x2.fill", tint: .accentColor, size: size)
        }
    }
}
