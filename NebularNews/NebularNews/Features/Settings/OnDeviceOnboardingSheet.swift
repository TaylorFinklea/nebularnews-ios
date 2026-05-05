import SwiftUI

/// One-shot explainer for the free on-device AI tier. Surfaces once
/// per device (gated by `@AppStorage("seenOnDeviceOnboarding")` in the
/// presenter) so users understand both what works and what to expect
/// before they encounter the limits in conversation.
///
/// Two CTAs: "Got it" simply dismisses; "Add an API key" jumps the
/// user into the BYOK entry sheet so the upgrade path is one tap away.
struct OnDeviceOnboardingSheet: View {
    let onDismiss: () -> Void
    let onAddKey: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)

                    Text("AI runs on your iPhone")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("On the free tier, your assistant uses Apple Intelligence locally. No data leaves the device for chat, and there's no token bill.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    bulletList(title: "What works on-device", systemImage: "checkmark.circle.fill", color: .green, items: [
                        "Asking questions about today's brief",
                        "Quick clarifications on an article you're reading",
                        "Summaries and explanations grounded in conversation",
                    ])

                    bulletList(title: "What needs a key or subscription", systemImage: "lock.circle.fill", color: .orange, items: [
                        "Searching across your articles or feeds",
                        "Acting on your library (Save, Mark read, Pause feed)",
                        "Generating a fresh brief on demand",
                        "Richer answers from a larger model",
                    ])

                    Spacer(minLength: 12)

                    Button(action: onAddKey) {
                        Label("Add an API key", systemImage: "key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Got it", action: onDismiss)
                        .frame(maxWidth: .infinity)
                        .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }

    @ViewBuilder
    private func bulletList(title: String, systemImage: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
