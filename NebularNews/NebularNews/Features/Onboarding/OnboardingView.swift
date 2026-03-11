import SwiftUI
import SwiftData
import NebularNewsKit

private enum StandaloneOnboardingStep {
    case interests
    case avoid
    case review
    case finish

    var title: String {
        switch self {
        case .interests:
            "Choose interests"
        case .avoid:
            "Anything to avoid?"
        case .review:
            "Review starter feeds"
        case .finish:
            "Finish setup"
        }
    }

    var progressText: String {
        switch self {
        case .interests:
            "Step 1 of 4"
        case .avoid:
            "Step 2 of 4"
        case .review:
            "Step 3 of 4"
        case .finish:
            "Step 4 of 4"
        }
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var standaloneStep: StandaloneOnboardingStep?
    @State private var selectedInterestIDs: Set<String> = []
    @State private var avoidedInterestIDs: Set<String> = []
    @State private var customFeeds: [StarterFeedDefinition] = []
    @State private var feedSelections: [String: Bool] = [:]
    @State private var showingAddFeedSheet = false
    @State private var showingHelpForAddFeedSheet = false
    @State private var isFinishingStandalone = false
    @State private var standaloneError: String?
    @State private var apiSetupExpanded = false
    @State private var apiKey = ""
    @State private var selectedProvider = "anthropic"
    @State private var companionServerURL = AppConfiguration.shared.mobileDefaultServerURL?.absoluteString ?? "https://api.example.com"
    @State private var companionError = ""
    @State private var companionLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var palette: NebularPalette {
        NebularPalette.forColorScheme(colorScheme)
    }

    private var reviewChoices: [StarterFeedChoice] {
        buildStarterFeedChoices(
            selectedInterestIDs: selectedInterestIDs,
            avoidedInterestIDs: avoidedInterestIDs,
            customFeeds: customFeeds
        )
    }

    private var selectedReviewFeeds: [StarterFeedDefinition] {
        reviewChoices
            .filter { feedSelections[$0.id] ?? $0.isInitiallySelected }
            .map(\.feed)
    }

    private var selectedInterests: [StarterInterest] {
        starterInterestCatalog.filter { selectedInterestIDs.contains($0.id) }
    }

    private var avoidedInterests: [StarterInterest] {
        starterInterestCatalog.filter { avoidedInterestIDs.contains($0.id) }
    }

    var body: some View {
        NebularScreen(emphasis: .hero) {
            if let standaloneStep {
                standaloneFlow(step: standaloneStep)
            } else {
                welcomePage
            }
        }
        .sheet(isPresented: $showingAddFeedSheet) {
            AddFeedSheet { request in
                await handleAddFeedRequest(request)
            }
        }
        .alert("Add feeds during onboarding", isPresented: $showingHelpForAddFeedSheet) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use the sheet to add a single feed or import OPML. Feeds added here stay in the onboarding review until you finish setup.")
        }
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 56)

                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .frame(width: 96, height: 96)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .background(palette.primarySoft, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .strokeBorder(palette.primary.opacity(0.18))
                        )
                        .background {
                            NebularHeaderHalo(color: palette.primary)
                        }

                    Text("Nebular News")
                        .font(.largeTitle.bold())
                        .tracking(-0.8)

                    Text("Choose how you want to use the app. Standalone mode gets you reading quickly with curated feeds and local personalization. You can also connect to an existing Nebular News server and keep the iPhone app in sync with the web app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                standaloneCard
                companionCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private var companionCard: some View {
        GlassCard(cornerRadius: 30, style: .raised, tintColor: palette.primary) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Connect to a Nebular News server", systemImage: "iphone.and.arrow.forward")
                    .font(.headline)

                Text("Use the public API hostname for your deployment, sign in once, and read the same dashboard, News Brief, articles, reactions, and tags as the web app.")
                    .foregroundStyle(.secondary)

                TextField("https://api.example.com", text: $companionServerURL)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !companionError.isEmpty {
                    Text(companionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await connectCompanionMode() }
                } label: {
                    if companionLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in to server")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(companionLoading)
            }
        }
    }

    private var standaloneCard: some View {
        GlassCard(cornerRadius: 30, style: .standard, tintColor: Color.forScore(4)) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Use standalone mode", systemImage: "internaldrive")
                    .font(.headline)

                Text("Pick the topics you care about, start with a curated feed bundle, and let the app learn locally from there.")
                    .foregroundStyle(.secondary)

                Button("Set up standalone mode") {
                    withAnimation(.snappy(duration: 0.22)) {
                        standaloneStep = .interests
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func standaloneFlow(step: StandaloneOnboardingStep) -> some View {
        NavigationStack {
            switch step {
            case .interests:
                interestsStep
            case .avoid:
                avoidStep
            case .review:
                reviewFeedsStep
            case .finish:
                finishStep
            }
        }
        .tint(palette.primary)
    }

    private var interestsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                standaloneStepHeader(
                    title: StandaloneOnboardingStep.interests.title,
                    subtitle: "Pick the areas you want more of. We recommend 2 to 5.",
                    progress: StandaloneOnboardingStep.interests.progressText
                )

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(starterInterestCatalog) { interest in
                        interestCard(
                            interest,
                            isSelected: selectedInterestIDs.contains(interest.id)
                        ) {
                            if selectedInterestIDs.contains(interest.id) {
                                selectedInterestIDs.remove(interest.id)
                            } else {
                                selectedInterestIDs.insert(interest.id)
                                avoidedInterestIDs.remove(interest.id)
                            }
                        }
                    }
                }

                onboardingActions(
                    backTitle: "Back",
                    continueTitle: "Continue",
                    showBack: true,
                    continueDisabled: selectedInterestIDs.isEmpty,
                    backAction: { standaloneStep = nil },
                    continueAction: { standaloneStep = .avoid }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
    }

    private var avoidStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                standaloneStepHeader(
                    title: StandaloneOnboardingStep.avoid.title,
                    subtitle: "Optional. This gently downweights whole areas without blocking them completely.",
                    progress: StandaloneOnboardingStep.avoid.progressText
                )

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(starterInterestCatalog) { interest in
                        interestCard(
                            interest,
                            isSelected: avoidedInterestIDs.contains(interest.id),
                            accentColor: .orange
                        ) {
                            if avoidedInterestIDs.contains(interest.id) {
                                avoidedInterestIDs.remove(interest.id)
                            } else {
                                avoidedInterestIDs.insert(interest.id)
                                selectedInterestIDs.remove(interest.id)
                            }
                        }
                    }
                }

                onboardingActions(
                    backTitle: "Back",
                    continueTitle: "Review feeds",
                    showBack: true,
                    continueDisabled: selectedInterestIDs.isEmpty,
                    backAction: { standaloneStep = .interests },
                    continueAction: {
                        syncFeedSelections()
                        standaloneStep = .review
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
    }

    private var reviewFeedsStep: some View {
        List {
            Section {
                LabeledContent("Selected interests", value: "\(selectedInterestIDs.count)")
                LabeledContent("Starter feeds", value: "\(reviewChoices.count)")
                LabeledContent("Preselected", value: "\(selectedReviewFeeds.count)")
            } header: {
                Text(StandaloneOnboardingStep.review.progressText)
            } footer: {
                Text("We preselect up to two primary feeds per interest, capped at twelve, but you can customize this list.")
            }

            Section("Starter bundle") {
                ForEach(reviewChoices.filter { $0.isCustom == false }) { choice in
                    Toggle(isOn: binding(for: choice)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.feed.title)
                                .font(.body.weight(.semibold))
                            Text(choice.interestTitles.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(choice.feed.feedURL)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }

            if reviewChoices.contains(where: \.isCustom) {
                Section("Imported & Custom") {
                    ForEach(reviewChoices.filter(\.isCustom)) { choice in
                        Toggle(isOn: binding(for: choice)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(choice.feed.title)
                                    .font(.body.weight(.semibold))
                                Text(choice.feed.feedURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.switch)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                removeCustomFeed(choice.feed)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Import OPML") {
                    showingAddFeedSheet = true
                }

                Button("Add one custom feed") {
                    showingAddFeedSheet = true
                }

                Button("How this works") {
                    showingHelpForAddFeedSheet = true
                }
                .foregroundStyle(.secondary)
            } header: {
                Text("Add more")
            } footer: {
                Text("Both actions open the same add-feed sheet so you can paste OPML, import a file, or add one feed URL.")
            }

            if let standaloneError, !standaloneError.isEmpty {
                Section {
                    Label(standaloneError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                onboardingListAction(
                    title: "Continue",
                    systemImage: "arrow.right"
                ) {
                    standaloneError = nil
                    standaloneStep = .finish
                }
                .disabled(selectedReviewFeeds.isEmpty)

                onboardingListAction(
                    title: "Back",
                    systemImage: "chevron.left"
                ) {
                    standaloneStep = .avoid
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(StandaloneOnboardingStep.review.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var finishStep: some View {
        List {
            Section {
                LabeledContent("Interests", value: selectedInterests.map(\.title).joined(separator: ", "))
                if avoidedInterests.isEmpty == false {
                    LabeledContent("Avoiding", value: avoidedInterests.map(\.title).joined(separator: ", "))
                }
                LabeledContent("Selected feeds", value: "\(selectedReviewFeeds.count)")
            } header: {
                Text(StandaloneOnboardingStep.finish.progressText)
            }

            Section("Starter feeds") {
                ForEach(selectedReviewFeeds, id: \.id) { feed in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feed.title)
                            .font(.body.weight(.semibold))
                        Text(feed.feedURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $apiSetupExpanded) {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Anthropic").tag("anthropic")
                        Text("OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } label: {
                    Text("Configure AI provider")
                }
            } header: {
                Text("Optional AI setup")
            } footer: {
                Text("AI keys are optional. They don’t block onboarding and can be added later in Settings.")
            }

            if let standaloneError, !standaloneError.isEmpty {
                Section {
                    Label(standaloneError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await finishStandaloneSetup() }
                } label: {
                    if isFinishingStandalone {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text("Start Reading")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(isFinishingStandalone || selectedReviewFeeds.isEmpty)

                onboardingListAction(
                    title: "Back",
                    systemImage: "chevron.left"
                ) {
                    standaloneStep = .review
                }
                .disabled(isFinishingStandalone)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(StandaloneOnboardingStep.finish.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func standaloneStepHeader(
        title: String,
        subtitle: String,
        progress: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(progress.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.largeTitle.bold())

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interestCard(
        _ interest: StarterInterest,
        isSelected: Bool,
        accentColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let tint = accentColor ?? palette.primary

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: interest.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? tint : .secondary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? tint : Color.secondary.opacity(0.35))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(interest.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    Text(interest.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)

                    Spacer(minLength: 0)

                    Text("\(interest.starterFeedCount) starter feeds")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? tint : .secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.7) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(interest.title), \(interest.starterFeedCount) starter feeds")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func onboardingActions(
        backTitle: String,
        continueTitle: String,
        showBack: Bool,
        continueDisabled: Bool,
        backAction: @escaping () -> Void,
        continueAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            if showBack {
                Button(backTitle, action: backAction)
                    .buttonStyle(.bordered)
            }

            Button(continueTitle, action: continueAction)
                .buttonStyle(.borderedProminent)
                .disabled(continueDisabled)
        }
        .controlSize(.large)
    }

    private func onboardingListAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func binding(for choice: StarterFeedChoice) -> Binding<Bool> {
        Binding(
            get: { feedSelections[choice.id] ?? choice.isInitiallySelected },
            set: { newValue in
                feedSelections[choice.id] = newValue
            }
        )
    }

    private func syncFeedSelections() {
        let choices = reviewChoices
        let validIDs = Set(choices.map(\.id))
        feedSelections = feedSelections.filter { validIDs.contains($0.key) }

        for choice in choices {
            if feedSelections[choice.id] == nil {
                feedSelections[choice.id] = choice.isInitiallySelected
            }
        }
    }

    private func removeCustomFeed(_ feed: StarterFeedDefinition) {
        customFeeds.removeAll { $0.id == feed.id }
        feedSelections.removeValue(forKey: feed.id)
        syncFeedSelections()
    }

    private func handleAddFeedRequest(_ request: AddFeedRequest) async -> String? {
        let feedsToMerge: [StarterFeedDefinition]

        switch request {
        case let .single(url, title):
            guard let feed = StarterFeedDefinition.custom(title: title, feedURL: url) else {
                return "Please enter a valid feed URL."
            }
            feedsToMerge = [feed]

        case let .opml(entries):
            let feeds = entries.compactMap { entry in
                StarterFeedDefinition.custom(title: entry.title, feedURL: entry.feedURL)
            }
            guard feeds.isEmpty == false else {
                return "No valid feed URLs were found."
            }
            feedsToMerge = feeds
        }

        mergeCustomFeeds(feedsToMerge)
        return nil
    }

    private func mergeCustomFeeds(_ feeds: [StarterFeedDefinition]) {
        var byCanonicalURL: [String: StarterFeedDefinition] = [:]
        var orderedURLs: [String] = []

        for feed in customFeeds + feeds {
            guard let canonicalURL = canonicalStarterFeedURL(feed.feedURL) else { continue }
            if byCanonicalURL[canonicalURL] == nil {
                orderedURLs.append(canonicalURL)
            }
            byCanonicalURL[canonicalURL] = StarterFeedDefinition(
                id: feed.id,
                title: feed.title,
                feedURL: canonicalURL,
                aliases: feed.aliases
            )
        }

        customFeeds = orderedURLs.compactMap { byCanonicalURL[$0] }
        syncFeedSelections()
        for feed in customFeeds {
            feedSelections[feed.id] = true
        }
    }

    private func finishStandaloneSetup() async {
        guard selectedReviewFeeds.isEmpty == false else {
            standaloneError = "Pick at least one feed to start with."
            return
        }

        standaloneError = nil
        isFinishingStandalone = true
        defer { isFinishingStandalone = false }

        do {
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                try appState.saveStandaloneApiKey(provider: selectedProvider, key: apiKey)
            }

            let service = OnboardingSeedService(
                modelContainer: modelContext.container,
                keychainService: appState.configuration.keychainService
            )
            let request = OnboardingSeedRequest(
                selectedInterestIDs: selectedInterests.map(\.id),
                avoidedInterestIDs: avoidedInterests.map(\.id),
                selectedFeeds: selectedReviewFeeds
            )
            let result = try await service.apply(request: request)

            appState.beginStandaloneFirstBriefing(feedIDs: result.feedIDs)
            appState.completeStandaloneOnboarding()
        } catch {
            standaloneError = error.localizedDescription
        }
    }

    private func connectCompanionMode() async {
        companionLoading = true
        companionError = ""
        defer { companionLoading = false }

        let trimmed = companionServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            companionError = "Enter a valid server URL."
            return
        }

        do {
            let session = try await appState.mobileOAuthCoordinator.signIn(serverURL: url)
            try appState.completeCompanionOnboarding(
                serverURL: session.serverURL,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken
            )
        } catch {
            companionError = error.localizedDescription
        }
    }
}
