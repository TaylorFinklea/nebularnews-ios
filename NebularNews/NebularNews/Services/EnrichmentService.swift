import Foundation
import NebularNewsKit
import Supabase

struct EnrichmentService: Sendable {
    let client: SupabaseClient

    private var currentUserId: UUID? {
        get async {
            try? await client.auth.session.user.id
        }
    }

    func fetchChat(articleId: String) async throws -> CompanionChatPayload {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        let threads: [SupabaseChatThreadRow] = try await client.from("chat_threads")
            .select("id, article_id, created_at, updated_at")
            .eq("article_id", value: articleId)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let thread = threads.first else {
            return CompanionChatPayload(thread: nil, messages: [])
        }

        let messages: [SupabaseChatMessageRow] = try await client.from("chat_messages")
            .select("id, thread_id, role, content, created_at")
            .eq("thread_id", value: thread.id)
            .order("created_at")
            .execute()
            .value

        let companionThread = CompanionChatThread(
            id: thread.id,
            articleId: thread.articleId,
            title: nil,
            createdAt: Int(thread.createdAt?.timeIntervalSince1970 ?? 0),
            updatedAt: Int(thread.updatedAt?.timeIntervalSince1970 ?? 0)
        )

        let companionMessages = messages.map { msg in
            CompanionChatMessage(
                id: msg.id,
                threadId: msg.threadId,
                role: msg.role,
                content: msg.content,
                tokenCount: nil,
                provider: nil,
                model: nil,
                createdAt: Int(msg.createdAt?.timeIntervalSince1970 ?? 0)
            )
        }

        return CompanionChatPayload(thread: companionThread, messages: companionMessages)
    }

    func fetchSuggestedQuestions(articleId: String) async throws -> [String] {
        struct QuestionsRow: Decodable {
            let questionsJson: String

            enum CodingKeys: String, CodingKey {
                case questionsJson = "questions_json"
            }
        }

        let rows: [QuestionsRow] = try await client.from("article_suggested_questions")
            .select("questions_json")
            .eq("article_id", value: articleId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first,
              let data = row.questionsJson.data(using: .utf8),
              let questions = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }

        return questions
    }

    func requestSuggestedQuestions(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        _ = try await client.functions.invoke(
            "enrich-article",
            options: FunctionInvokeOptions(
                headers: userAIHeaders(),
                body: [
                    "article_id": articleId,
                    "user_id": userId.uuidString,
                    "job_type": "suggest_questions"
                ]
            )
        )
    }

    func sendChatMessage(articleId: String, content: String) async throws -> CompanionChatPayload {
        guard await currentUserId != nil else { throw SupabaseManagerError.notAuthenticated }

        let payload: CompanionChatPayload = try await client.functions.invoke(
            "article-chat",
            options: FunctionInvokeOptions(
                headers: userAIHeaders(),
                body: [
                    "article_id": articleId,
                    "message": content
                ]
            )
        )

        return payload
    }

    func rerunSummarize(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        for jobType in ["summarize", "key_points"] {
            _ = try await client.functions.invoke(
                "enrich-article",
                options: FunctionInvokeOptions(
                    headers: userAIHeaders(),
                    body: [
                        "article_id": articleId,
                        "user_id": userId.uuidString,
                        "job_type": jobType
                    ]
                )
            )
        }
    }

    func requestAIScore(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        _ = try await client.functions.invoke(
            "enrich-article",
            options: FunctionInvokeOptions(
                headers: userAIHeaders(),
                body: [
                    "article_id": articleId,
                    "user_id": userId.uuidString,
                    "job_type": "score"
                ]
            )
        )
    }

    func generateKeyPoints(articleId: String) async throws {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        _ = try await client.functions.invoke(
            "enrich-article",
            options: FunctionInvokeOptions(
                headers: userAIHeaders(),
                body: [
                    "article_id": articleId,
                    "user_id": userId.uuidString,
                    "job_type": "key_points"
                ]
            )
        )
    }

    func generateNewsBrief() async throws -> CompanionNewsBrief? {
        guard let userId = await currentUserId else { throw SupabaseManagerError.notAuthenticated }

        struct BriefResponse: Decodable {
            let ok: Bool?
            let brief: BriefData?

            struct BriefData: Decodable {
                let id: String
                let editionType: String
                let briefText: String
                let articleIdsJson: String?
                let provider: String?
                let model: String?
                let createdAt: String?
            }
        }

        let response: BriefResponse = try await client.functions.invoke(
            "generate-news-brief",
            options: FunctionInvokeOptions(
                headers: userAIHeaders(),
                body: ["user_id": userId.uuidString]
            )
        )

        guard let brief = response.brief else { return nil }

        let bullets: [CompanionNewsBrief.Bullet]
        if let data = brief.briefText.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([BriefBulletDTO].self, from: data) {
            bullets = parsed.map { dto in
                CompanionNewsBrief.Bullet(
                    text: dto.text,
                    sources: (dto.sourceArticleIds ?? []).map { id in
                        CompanionNewsBrief.Bullet.Source(articleId: id, title: "", canonicalUrl: nil)
                    }
                )
            }
        } else {
            bullets = [CompanionNewsBrief.Bullet(text: brief.briefText, sources: [])]
        }

        return CompanionNewsBrief(
            state: "ready",
            title: "News Brief",
            editionLabel: brief.editionType.replacingOccurrences(of: "_", with: " ").capitalized,
            generatedAt: brief.createdAt.flatMap { timestampMillis($0) },
            windowHours: 12,
            scoreCutoff: 3,
            bullets: bullets,
            nextScheduledAt: nil,
            stale: false
        )
    }

    private func userAIHeaders() -> [String: String] {
        let keychain = KeychainManager()
        if let key = keychain.get(forKey: KeychainManager.Key.anthropicApiKey) {
            return ["x-user-api-key": key, "x-user-api-provider": "anthropic"]
        }
        if let key = keychain.get(forKey: KeychainManager.Key.openaiApiKey) {
            return ["x-user-api-key": key, "x-user-api-provider": "openai"]
        }
        return [:]
    }
}
