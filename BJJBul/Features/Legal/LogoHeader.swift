import SwiftUI

/// Centered app logo for list/form headers (light + dark variants come from the asset catalog).
struct LogoHeader: View {
    var height: CGFloat = 96

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityLabel(Text(verbatim: "BJJ Bul"))
    }
}
