import Foundation
import os

/// Dispatches client-side tool calls from the AI assistant into app state
/// mutations. Server-executed tools are handled before this; here we only
/// route the navigation/filter primitives that iOS owns.
@MainActor
enum AssistantActionDispatcher {
    private static let logger = Logger(subsystem: "com.nebularnews", category: "AssistantActionDispatcher")

    /// Return value describes what happened so the caller can surface a
    /// confirmation chip in the chat transcript.
    struct DispatchResult {
        let summary: String
        let succeeded: Bool
    }

    static func dispatch(
        toolName: String,
        args: [String: AnyCodable],
        appState: AppState,
        deepLinkRouter: DeepLinkRouter
    ) -> DispatchResult {
        switch toolName {
        case "open_article":
            guard let id = args["article_id"]?.stringValue,
                  let url = URL(string: "nebularnews://article/\(id)") else {
                return .init(summary: "Couldn't open article", succeeded: false)
            }
            deepLinkRouter.handle(url)
            return .init(summary: "Opened article", succeeded: true)

        case "navigate_to_tab":
            guard let tab = args["tab"]?.stringValue else {
                return .init(summary: "Missing tab", succeeded: false)
            }
            appState.pendingTabSwitch = tab
            return .init(summary: "Switched to \(tab.capitalized)", succeeded: true)

        case "set_articles_filter":
            let filter = AppState.PendingArticlesFilter(
                read: args["read"]?.stringValue,
                minScore: args["min_score"]?.intValue,
                sort: args["sort"]?.stringValue,
                tag: args["tag"]?.stringValue,
                query: args["query"]?.stringValue
            )
            appState.pendingArticlesFilter = filter
            appState.pendingTabSwitch = "articles"
            return .init(summary: "Applied articles filter", succeeded: true)

        case "generate_brief_now":
            appState.pendingTabSwitch = "today"
            appState.pendingBriefGeneration = true
            return .init(summary: "Generating brief", succeeded: true)

        default:
            logger.warning("Unknown client tool: \(toolName)")
            return .init(summary: "Unknown action: \(toolName)", succeeded: false)
        }
    }
}
