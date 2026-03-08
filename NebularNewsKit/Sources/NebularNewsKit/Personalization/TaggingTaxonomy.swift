import Foundation

public struct StarterCanonicalTag: Sendable, Hashable {
    public let id: String
    public let name: String
    public let slug: String

    public init(id: String, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public let starterCanonicalTags: [StarterCanonicalTag] = [
    .init(id: "tag-artificial-intelligence", name: "Artificial Intelligence", slug: "artificial-intelligence"),
    .init(id: "tag-generative-ai", name: "Generative AI", slug: "generative-ai"),
    .init(id: "tag-large-language-models", name: "Large Language Models", slug: "large-language-models"),
    .init(id: "tag-ai-agents", name: "AI Agents", slug: "ai-agents"),
    .init(id: "tag-ai-safety", name: "AI Safety", slug: "ai-safety"),
    .init(id: "tag-conversational-ai", name: "Conversational AI", slug: "conversational-ai"),
    .init(id: "tag-deep-learning", name: "Deep Learning", slug: "deep-learning"),
    .init(id: "tag-robotics", name: "Robotics", slug: "robotics"),
    .init(id: "tag-cybersecurity", name: "Cybersecurity", slug: "cybersecurity"),
    .init(id: "tag-cloud-infrastructure", name: "Cloud Infrastructure", slug: "cloud-infrastructure"),
    .init(id: "tag-kubernetes", name: "Kubernetes", slug: "kubernetes"),
    .init(id: "tag-open-source", name: "Open Source", slug: "open-source"),
    .init(id: "tag-developer-tools", name: "Developer Tools", slug: "developer-tools"),
    .init(id: "tag-software-engineering", name: "Software Engineering", slug: "software-engineering"),
    .init(id: "tag-semiconductors", name: "Semiconductors", slug: "semiconductors"),
    .init(id: "tag-gpus", name: "GPUs", slug: "gpus"),
    .init(id: "tag-data-centers", name: "Data Centers", slug: "data-centers"),
    .init(id: "tag-enterprise-software", name: "Enterprise Software", slug: "enterprise-software"),
    .init(id: "tag-startups", name: "Startups", slug: "startups"),
    .init(id: "tag-regulation", name: "Regulation", slug: "regulation"),
    .init(id: "tag-privacy", name: "Privacy", slug: "privacy"),
    .init(id: "tag-iot", name: "IoT", slug: "iot"),
    .init(id: "tag-consumer-hardware", name: "Consumer Hardware", slug: "consumer-hardware"),
    .init(id: "tag-research", name: "Research", slug: "research"),
    .init(id: "tag-birding", name: "Birding", slug: "birding"),
    .init(id: "tag-wildlife", name: "Wildlife", slug: "wildlife"),
    .init(id: "tag-conservation", name: "Conservation", slug: "conservation"),
    .init(id: "tag-nature", name: "Nature", slug: "nature"),
    .init(id: "tag-local-news", name: "Local News", slug: "local-news"),
    .init(id: "tag-kansas-city", name: "Kansas City", slug: "kansas-city"),
    .init(id: "tag-civics", name: "Civics", slug: "civics"),
    .init(id: "tag-transportation", name: "Transportation", slug: "transportation"),
    .init(id: "tag-housing", name: "Housing", slug: "housing"),
    .init(id: "tag-economics", name: "Economics", slug: "economics"),
    .init(id: "tag-monetary-policy", name: "Monetary Policy", slug: "monetary-policy"),
    .init(id: "tag-inflation", name: "Inflation", slug: "inflation"),
    .init(id: "tag-banking", name: "Banking", slug: "banking"),
    .init(id: "tag-standards", name: "Standards", slug: "standards"),
    .init(id: "tag-manufacturing", name: "Manufacturing", slug: "manufacturing"),
    .init(id: "tag-observability", name: "Observability", slug: "observability"),
    .init(id: "tag-site-reliability", name: "Site Reliability", slug: "site-reliability")
]

public struct PersonalizationTargetFeedFamily: Sendable, Hashable {
    public let name: String
    public let feedTitleAliases: [String]
    public let siteHosts: [String]
    public let tagSlugs: [String]

    public init(name: String, feedTitleAliases: [String] = [], siteHosts: [String] = [], tagSlugs: [String]) {
        self.name = name
        self.feedTitleAliases = feedTitleAliases
        self.siteHosts = siteHosts
        self.tagSlugs = tagSlugs
    }
}

public struct DeterministicTagSourceProfile: Sendable, Hashable {
    public let name: String
    public let feedTitles: [String]
    public let siteHosts: [String]
    public let tagSlugs: [String]

    public init(name: String, feedTitles: [String] = [], siteHosts: [String] = [], tagSlugs: [String]) {
        self.name = name
        self.feedTitles = feedTitles
        self.siteHosts = siteHosts
        self.tagSlugs = tagSlugs
    }
}

public let personalizationTargetFeedFamilies: [PersonalizationTargetFeedFamily] = [
    .init(
        name: "OpenAI News",
        feedTitleAliases: ["OpenAI News"],
        siteHosts: ["openai.com"],
        tagSlugs: ["artificial-intelligence", "generative-ai", "large-language-models"]
    ),
    .init(
        name: "Google DeepMind News",
        feedTitleAliases: ["Google DeepMind News"],
        siteHosts: ["deepmind.google"],
        tagSlugs: ["artificial-intelligence", "generative-ai", "large-language-models", "research"]
    ),
    .init(
        name: "The latest research from Google",
        feedTitleAliases: ["The latest research from Google"],
        siteHosts: ["research.google"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Microsoft Research Blog - Microsoft Research",
        feedTitleAliases: ["Microsoft Research Blog - Microsoft Research", "Microsoft Research Blog"],
        siteHosts: ["research.microsoft.com"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "MIT News - Artificial intelligence",
        feedTitleAliases: ["MIT News - Artificial intelligence"],
        siteHosts: ["news.mit.edu"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Artificial intelligence – MIT Technology Review",
        feedTitleAliases: [
            "Artificial intelligence - MIT Technology Review",
            "Artificial intelligence – MIT Technology Review",
            "Artificial intelligence &#8211; MIT Technology Review"
        ],
        siteHosts: ["technologyreview.com"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Import AI",
        feedTitleAliases: ["Import AI"],
        siteHosts: ["importai.substack.com"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Hugging Face - Blog",
        feedTitleAliases: ["Hugging Face - Blog"],
        siteHosts: ["huggingface.co"],
        tagSlugs: ["artificial-intelligence", "open-source", "developer-tools"]
    ),
    .init(
        name: "InfoQ - DevOps",
        feedTitleAliases: ["InfoQ - DevOps"],
        siteHosts: ["infoq.com"],
        tagSlugs: ["cloud-infrastructure", "open-source", "developer-tools"]
    ),
    .init(
        name: "Kubernetes Blog",
        feedTitleAliases: ["Kubernetes Blog"],
        siteHosts: ["kubernetes.io"],
        tagSlugs: ["kubernetes", "cloud-infrastructure", "open-source"]
    ),
    .init(
        name: "The Berkeley Artificial Intelligence Research Blog",
        feedTitleAliases: ["The Berkeley Artificial Intelligence Research Blog", "Berkeley AI Research Blog"],
        siteHosts: ["bair.berkeley.edu"],
        tagSlugs: ["artificial-intelligence", "research"]
    ),
    .init(
        name: "The American Birding Podcast",
        feedTitleAliases: ["The American Birding Podcast"],
        siteHosts: ["aba.org"],
        tagSlugs: ["birding", "wildlife", "conservation", "nature"]
    ),
    .init(
        name: "video | All About Birds",
        feedTitleAliases: ["video | All About Birds"],
        siteHosts: ["allaboutbirds.org"],
        tagSlugs: ["birding", "wildlife", "conservation", "nature"]
    ),
    .init(
        name: "Nature Boost",
        feedTitleAliases: ["Nature Boost"],
        tagSlugs: ["wildlife", "conservation", "nature"]
    ),
    .init(
        name: "Kansas City Today",
        feedTitleAliases: ["Kansas City Today"],
        siteHosts: ["kcur.org"],
        tagSlugs: ["local-news", "kansas-city", "civics"]
    ),
    .init(
        name: "Up To Date",
        feedTitleAliases: ["Up To Date"],
        siteHosts: ["kcur.org"],
        tagSlugs: ["local-news", "kansas-city", "civics"]
    ),
    .init(
        name: "Federal Reserve Bank of Kansas City publications",
        feedTitleAliases: ["Federal Reserve Bank of Kansas City publications"],
        siteHosts: ["kansascityfed.org"],
        tagSlugs: ["economics", "monetary-policy", "inflation", "banking"]
    ),
    .init(
        name: "NIST News",
        feedTitleAliases: ["NIST News"],
        siteHosts: ["nist.gov"],
        tagSlugs: ["standards", "research"]
    ),
    .init(
        name: "News and Events Feed by Topic",
        feedTitleAliases: ["News and Events Feed by Topic"],
        siteHosts: ["nist.gov"],
        tagSlugs: ["standards", "research"]
    ),
    .init(
        name: "Distill",
        feedTitleAliases: ["Distill"],
        siteHosts: ["distill.pub"],
        tagSlugs: ["research", "artificial-intelligence", "deep-learning"]
    ),
    .init(
        name: "NVIDIA Blog",
        feedTitleAliases: ["NVIDIA Blog"],
        siteHosts: ["nvidia.com"],
        tagSlugs: ["artificial-intelligence", "gpus", "semiconductors", "data-centers"]
    ),
    .init(
        name: "Cloud Native Computing Foundation",
        feedTitleAliases: ["Cloud Native Computing Foundation"],
        siteHosts: ["cncf.io"],
        tagSlugs: ["cloud-infrastructure", "kubernetes", "open-source"]
    ),
    .init(
        name: "Grafana Labs blog on Grafana Labs",
        feedTitleAliases: ["Grafana Labs blog on Grafana Labs"],
        siteHosts: ["grafana.com"],
        tagSlugs: ["observability", "open-source", "developer-tools"]
    ),
    .init(
        name: "Security on Grafana Labs",
        feedTitleAliases: ["Security on Grafana Labs"],
        siteHosts: ["grafana.com"],
        tagSlugs: ["cybersecurity", "observability", "developer-tools"]
    )
]

public let deterministicTagSourceProfiles: [DeterministicTagSourceProfile] = personalizationTargetFeedFamilies.map { family in
    DeterministicTagSourceProfile(
        name: family.name,
        feedTitles: family.feedTitleAliases,
        siteHosts: family.siteHosts,
        tagSlugs: family.tagSlugs
    )
}

public let deterministicTagKeywordsBySlug: [String: [String]] = [
    "artificial-intelligence": ["artificial intelligence", "ai", "machine learning", "ml", "multimodal"],
    "generative-ai": ["generative ai", "diffusion", "image generation"],
    "large-language-models": [
        "llm",
        "llms",
        "large language model",
        "large language models",
        "language model",
        "language models",
        "foundation model",
        "foundation models",
        "gpt",
        "claude",
        "gemini",
        "phi",
        "reasoning model",
        "reasoning models"
    ],
    "ai-agents": ["ai agent", "ai agents", "agentic", "tool use", "tool-using agent"],
    "ai-safety": ["ai safety", "alignment", "model eval", "model evals", "guardrail", "guardrails"],
    "conversational-ai": ["chatbot", "assistant", "conversational ai"],
    "deep-learning": ["deep learning", "neural network", "neural networks", "graph neural network", "graph neural networks"],
    "robotics": ["robot", "robots", "robotics", "humanoid"],
    "cybersecurity": [
        "cybersecurity",
        "cyber",
        "infosec",
        "malware",
        "breach",
        "vulnerability",
        "vulnerabilities",
        "post-quantum",
        "ipsec",
        "ml-kem",
        "cryptography"
    ],
    "cloud-infrastructure": ["cloud", "infrastructure", "compute platform", "cloud native", "platform engineering", "aws"],
    "kubernetes": ["kubernetes", "k8s", "cncf", "container image", "cluster"],
    "open-source": ["open source", "oss"],
    "developer-tools": ["developer tools", "devtools", "ide", "cli", "sdk"],
    "software-engineering": ["software engineering", "programming", "coding", "developer workflow"],
    "semiconductors": ["semiconductor", "semiconductors", "chip", "chips", "foundry", "wafer"],
    "gpus": ["gpu", "gpus", "accelerator", "accelerators"],
    "data-centers": ["data center", "data centers", "datacenter", "datacenters", "colo", "colocation"],
    "enterprise-software": ["enterprise software", "saas", "b2b software"],
    "startups": ["startup", "startups", "funding", "venture", "vc"],
    "regulation": ["regulation", "policy", "policies", "antitrust", "compliance"],
    "privacy": [
        "privacy",
        "ad tracking",
        "app tracking",
        "tracking pixel",
        "tracking cookie",
        "cross-site tracking",
        "location tracking",
        "surveillance",
        "data protection"
    ],
    "iot": ["iot", "internet of things", "connected device", "connected devices"],
    "consumer-hardware": ["smartphone", "smartphones", "laptop", "laptops", "wearable", "wearables", "headset"],
    "research": ["research", "paper", "papers", "study", "studies", "arxiv", "benchmark", "dataset", "preprint", "conference", "workshop"],
    "birding": ["birding", "bird", "birds", "avian", "owl", "owls", "warbler", "warblers", "raptor", "raptors"],
    "wildlife": ["wildlife", "species", "habitat", "poaching", "migration", "migratory", "tarantula", "tarantulas", "snake", "snakes"],
    "conservation": ["conservation", "habitat", "restoration", "endangered", "protected area", "poaching"],
    "nature": ["nature", "ecosystem", "meadow", "prairie", "outdoors", "biodiversity"],
    "civics": ["city council", "mayor", "ordinance", "ballot", "election", "id invalidated"],
    "transportation": ["bus fare", "transit", "kcata", "transportation", "public transit"],
    "housing": ["housing", "zoning", "rent", "affordable housing", "development"],
    "economics": ["economics", "economy", "labor market", "wages", "income convergence"],
    "monetary-policy": ["monetary policy", "interest rate", "interest rates", "federal reserve", "central bank"],
    "inflation": ["inflation", "inflation expectations", "price growth", "gasoline prices"],
    "banking": ["banking", "payment fraud", "card-present", "card-not-present", "payments"],
    "standards": ["standards", "metrology", "reference material", "interoperability"],
    "manufacturing": ["manufacturing", "industrial", "factory", "factories", "production"],
    "observability": ["observability", "metrics", "logs", "tracing"],
    "site-reliability": ["site reliability", "sre", "slo", "slos", "incident", "incidents"]
]
