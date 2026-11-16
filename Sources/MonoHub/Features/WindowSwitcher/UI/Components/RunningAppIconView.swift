import AppKit
import SwiftUI

struct RunningAppIconView: View {
    let pid: pid_t
    let size: CGFloat

    var body: some View {
        if let icon = SwitcherAppIconCache.icon(for: pid) {
            Image(decorative: icon, scale: 2)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.7, weight: .light))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }
}
