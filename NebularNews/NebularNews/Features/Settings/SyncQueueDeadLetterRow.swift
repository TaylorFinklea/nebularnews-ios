import SwiftUI
import os

/// Actionable row for a dead-letter queued action.
/// Swipe actions: Retry (leading-trailing), Discard (trailing), Report (leading).
/// Tap → detail sheet with full info and three buttons.
struct SyncQueueDeadLetterRow: View {
    let descriptor: SyncQueueRowDescriptor
    let onRetry: () async -> Void
    let onDiscard: () -> Void
    let onReport: () -> Void

    @State private var showDetailSheet = false
    @State private var showDiscardAlert = false

    var body: some View {
        Button {
            showDetailSheet = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showDiscardAlert = true
            } label: {
                Label("Discard", systemImage: "trash")
            }

            Button {
                Task { await onRetry() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button {
                onReport()
            } label: {
                Label("Report", systemImage: "square.and.arrow.up")
            }
            .tint(.indigo)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Retry") { Task { await onRetry() } }
        .accessibilityAction(named: "Discard") { showDiscardAlert = true }
        .accessibilityAction(named: "Report") { onReport() }
        .alert("Discard this action?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { onDiscard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(descriptor.discardConfirmationBody())
        }
        .sheet(isPresented: $showDetailSheet) {
            SyncQueueDeadLetterDetailSheet(
                descriptor: descriptor,
                onRetry: onRetry,
                onDiscard: {
                    onDiscard()
                    showDetailSheet = false
                },
                onReport: onReport
            )
        }
    }

    // MARK: - Row layout

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: descriptor.actionIcon)
                .foregroundStyle(.secondary)
                .font(.title3)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(descriptor.actionLabel)
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    Text(descriptor.enqueuedAge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(descriptor.targetTitle) \u{00B7} attempt 10 of 10 \u{2014} failed")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
                    Spacer()
                }

                if let error = descriptor.lastErrorTail {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Trailing chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        "\(descriptor.actionLabel). \(descriptor.targetTitle). Failed after 10 attempts."
    }
}

// MARK: - Detail sheet

struct SyncQueueDeadLetterDetailSheet: View {
    let descriptor: SyncQueueRowDescriptor
    let onRetry: () async -> Void
    let onDiscard: () -> Void
    let onReport: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isRetrying = false
    @State private var showDiscardAlert = false
    @State private var retryToastMessage: String?
    @State private var showRetryToast = false

    private static let logger = Logger(subsystem: "com.nebularnews", category: "SyncQueueInspector")

    var body: some View {
        NavigationStack {
            List {
                // Metadata section
                Section("Action details") {
                    LabeledContent("Type", value: "\(descriptor.actionLabel) (\(descriptor.actionType))")
                    LabeledContent("Target", value: descriptor.targetTitle)
                    if let sub = descriptor.targetSubtitle {
                        LabeledContent("Details", value: sub)
                    }
                    LabeledContent("Enqueued", value: formattedEnqueuedDate)
                    LabeledContent("Attempts", value: "10")
                }

                // Error section
                if let error = descriptor.lastErrorTail {
                    Section("Last error") {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Payload section
                Section("Payload") {
                    ScrollView {
                        Text(prettyPayload)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }

                // Action buttons
                Section {
                    Button {
                        Task {
                            isRetrying = true
                            await onRetry()
                            isRetrying = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Retry now")
                        }
                    }
                    .disabled(isRetrying)

                    Button(role: .destructive) {
                        showDiscardAlert = true
                    } label: {
                        Text("Discard")
                    }

                    // Report: build redacted JSON + offer ShareLink
                    ShareLink(item: buildReportJSON()) {
                        Label("Report", systemImage: "square.and.arrow.up")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        logReport()
                    })
                }
            }
            .navigationTitle("Failed action")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Discard this action?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { onDiscard() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(descriptor.discardConfirmationBody())
            }
        }
    }

    // MARK: - Helpers

    private var formattedEnqueuedDate: String {
        // We don't have the original Date in the descriptor — re-derive from enqueuedAge label.
        // The descriptor carries age as a string; use it as-is.
        descriptor.enqueuedAge
    }

    private var prettyPayload: String {
        guard let data = descriptor.rawPayloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return descriptor.rawPayloadJSON
        }
        return str
    }

    // MARK: - Report

    private func buildReportJSON() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let redactedPayload = redactPayload(descriptor.rawPayloadJSON, actionType: descriptor.actionType)

        let report: [String: Any] = [
            "schemaVersion": 1,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "appVersion": "\(version) (\(build))",
            "actionType": descriptor.actionType,
            "resourceId": descriptor.id,
            "retryCount": descriptor.retryCount,
            "lastError": descriptor.lastErrorTail ?? "",
            "payload": redactedPayload
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize report\"}"
        }
        return str
    }

    private func logReport() {
        let json = buildReportJSON()
        Self.logger.error("sync-queue-report \(json, privacy: .public)")
    }

    private func redactPayload(_ payload: String, actionType: String) -> Any {
        guard let data = payload.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return payload
        }

        // Redact any string >= 256 chars
        for key in obj.keys {
            if let str = obj[key] as? String, str.count >= 256 {
                obj[key] = "<redacted: length=\(str.count)>"
            }
        }

        // For subscribe_feed: strip URL query string from the url field
        if actionType == "subscribe_feed", let urlStr = obj["url"] as? String,
           var components = URLComponents(string: urlStr) {
            components.query = nil
            obj["url"] = components.string ?? urlStr
        }

        return obj
    }
}
