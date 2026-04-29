import SwiftUI

/// A capsule-style toast shown near the AI FAB when a destructive tool runs
/// under the "Undo only" policy. Displays a 7-second countdown and an Undo
/// button. Rendered in AIAssistantOverlay so it stays visible even when the
/// chat sheet is dismissed.
struct AIUndoToast: View {
    @Environment(AIAssistantCoordinator.self) private var coordinator

    let toast: PendingUndoToast
    @State private var elapsed: Double = 0
    @State private var timer: Timer?

    private let duration: Double = 7

    struct PendingUndoToast: Equatable {
        let summary: String
        let undoTool: String
        let undoArgsB64: String
    }

    var body: some View {
        HStack(spacing: 8) {
            // Circular countdown progress.
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                Circle()
                    .trim(from: 0, to: CGFloat(1 - elapsed / duration))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: elapsed)
            }

            Text(toast.summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Button("Undo") {
                coordinator.dismissUndoToast()
                Task { await coordinator.undoTool(tool: toast.undoTool, argsB64: toast.undoArgsB64) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing),
            in: Capsule()
        )
        .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
        .onAppear {
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                elapsed = min(elapsed + 0.25, duration)
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
