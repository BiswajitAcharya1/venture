import SwiftUI

enum VentureTheme {
    static let background = Color(red: 0.969, green: 0.953, blue: 0.925)
    static let surface = Color(red: 1.0, green: 0.992, blue: 0.980)
    static let surfaceMuted = Color(red: 0.933, green: 0.910, blue: 0.894)
    static let deepSurface = Color(red: 0.867, green: 0.824, blue: 0.898)
    static let ink = Color(red: 0.188, green: 0.153, blue: 0.231)
    static let secondary = Color(red: 0.443, green: 0.404, blue: 0.475)
    static let line = ink.opacity(0.14)
    static let sage = Color(red: 0.475, green: 0.392, blue: 0.561)
    static let warm = Color(red: 0.522, green: 0.388, blue: 0.525)
    static let primaryFill = Color(red: 0.427, green: 0.333, blue: 0.533)
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18
}

extension View {
    func ventureCard(padding: CGFloat = 18) -> some View {
        self
            .padding(.vertical, padding)
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, VentureTheme.line, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
    }
}
