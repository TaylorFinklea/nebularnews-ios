import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.red)
                .accessibilityLabel("Connection error")
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
