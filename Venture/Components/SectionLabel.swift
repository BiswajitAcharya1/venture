import SwiftUI

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(VentureTheme.secondary)
    }
}

struct SignalRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(VentureTheme.secondary)
                .frame(width: 22)
            Text(title)
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}
