import SwiftUI

/// Floating AI assistant button + bottom sheet.
/// Applied as an overlay on `MainTabView`.
struct AIAssistantOverlay: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator
    @Environment(AppState.self) private var appState
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack(alignment: .bottomTrailing) {
            Color.clear // Passthrough background

            VStack(alignment: .trailing, spacing: 8) {
                Spacer()

                // Undo toast — anchored above the FAB.
                if let toast = coordinator.pendingUndoToast {
                    AIUndoToast(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.trailing, 16)
                }

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
                    .accessibilityLabel("AI Assistant")
                }
            }
            .padding(.bottom, 72)
        }
        .animation(.spring(response: 0.3), value: coordinator.pendingUndoToast != nil)
        .sheet(isPresented: $coordinator.isSheetPresented) {
            AIAssistantSheetView()
                .presentationDetents([.fraction(1.0/3.0), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(1.0/3.0)))
        }
        .onAppear {
            // Wire the client-side tool dispatcher — the coordinator itself
            // doesn't depend on AppState / DeepLinkRouter.
            coordinator.clientToolHandler = { [appState, deepLinkRouter] name, args in
                let result = AssistantActionDispatcher.dispatch(
                    toolName: name,
                    args: args,
                    appState: appState,
                    deepLinkRouter: deepLinkRouter
                )
                return (summary: result.summary, succeeded: result.succeeded)
            }
            // Wire guardrail policy.
            coordinator.guardrailsPolicy = appState.aiGuardrails
        }
    }
}
