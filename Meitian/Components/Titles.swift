import SwiftUI

/// The colours of a title cosmetic (decided by the core), left to right.
func titleGradient(_ id: String) -> LinearGradient {
    LinearGradient(colors: titleColors(id: id).map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
}

extension Text {
    /// A name (or a title) in its title's colours.
    func titled(_ id: String) -> some View { lineLimit(1).foregroundStyle(titleGradient(id)) }
}

extension View {
    /// The dark plate names sit on, so every title's colours can be read on every frame.
    func namePlate() -> some View {
        padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
