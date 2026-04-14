import SwiftUI

/// Floating AI assistant button + bottom sheet.
/// Applied as an overlay on `MainTabView`.
struct AIAssistantOverlay: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack(alignment: .bottomTrailing) {
            Color.clear // Passthrough background

            if !coordinator.hideFloatingButton {
                Button {
                    coordinator.toggle()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 72)
                .accessibilityLabel("AI Assistant")
            }
        }
        .sheet(isPresented: $coordinator.isSheetPresented) {
            AIAssistantSheetView()
                .presentationDetents([.fraction(1.0/3.0), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(1.0/3.0)))
        }
    }
}
