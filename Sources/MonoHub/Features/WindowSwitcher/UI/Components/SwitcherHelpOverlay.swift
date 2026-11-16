import SwiftUI

struct HelpOverlayView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SwitcherSheetHeader(
                title: localized("Keyboard shortcuts"),
                closeHelp: localized("Close (? or Esc)"),
                onClose: onClose
            )
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)

            Form {
                ShortcutSections()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
