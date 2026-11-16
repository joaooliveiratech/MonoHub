import SwiftUI

struct PermissionsBannerView: View {
    private let permissions = SwitcherPermissionsManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))

            Text(message)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !permissions.hasAccessibility {
                Button(localized("Accessibility…")) { permissions.openSettings(for: .accessibility) }
            }
            if !permissions.hasScreenRecording {
                Button(localized("Screen Recording…")) { permissions.openSettings(for: .screenRecording) }
            }

            SwitcherCloseButton(help: localized("Dismiss")) { permissions.dismissBanner() }
                .controlSize(.small)
        }
        .controlSize(.small)
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: SwitcherMetrics.bannerHeight - 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12))
        )
    }

    private var message: String {
        switch (permissions.hasAccessibility, permissions.hasScreenRecording) {
        case (false, false): localized("MonoHub requires Accessibility and Screen Recording to switch windows.")
        case (false, _): localized("Grant Accessibility permission to switch and manage windows.")
        default: localized("Grant Screen Recording permission to display visual previews.")
        }
    }
}
