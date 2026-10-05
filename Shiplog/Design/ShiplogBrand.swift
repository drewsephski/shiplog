import SwiftUI

/// The shared folded-page mark. Template rendering follows appearance and contrast.
struct ShiplogMark: View {
    var size: CGFloat = 42

    var body: some View {
        Image("ShiplogSymbol")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            // The source retains the app icon's safe area. Remove that visual
            // padding when displaying the standalone mark within the app.
            .frame(width: size * 1.55, height: size * 1.55)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityHidden(true)
    }
}

struct ShiplogLogo: View {
    var markSize: CGFloat = 42

    var body: some View {
        HStack(spacing: 12) {
            ShiplogMark(size: markSize)
            Text("Shiplog")
                .font(.title3.weight(.semibold))
                .tracking(-0.4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Uses the same artwork as the installed app icon on product identity surfaces.
struct ShiplogAppIcon: View {
    var size: CGFloat = 48

    var body: some View {
        Image("ShiplogIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }
}

#Preview("Brand · light") {
    VStack(spacing: 32) {
        ShiplogLogo(markSize: 48)
        HStack(spacing: 24) {
            ShiplogMark(size: 20)
            ShiplogMark(size: 28)
            ShiplogMark(size: 48)
            ShiplogAppIcon(size: 64)
        }
    }
    .padding(32)
    .preferredColorScheme(.light)
}

#Preview("Brand · dark") {
    VStack(spacing: 32) {
        ShiplogLogo(markSize: 48)
        HStack(spacing: 24) {
            ShiplogMark(size: 20)
            ShiplogMark(size: 28)
            ShiplogMark(size: 48)
            ShiplogAppIcon(size: 64)
        }
    }
    .padding(32)
    .preferredColorScheme(.dark)
}
