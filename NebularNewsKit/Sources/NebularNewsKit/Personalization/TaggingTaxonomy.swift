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
    .init(id: "tag-research", name: "Research", slug: "research")
]

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

public let deterministicTagSourceProfiles: [DeterministicTagSourceProfile] = [
    .init(
        name: "OpenAI News",
        feedTitles: ["OpenAI News"],
        siteHosts: ["openai.com"],
        tagSlugs: ["artificial-intelligence", "generative-ai", "large-language-models"]
    ),
    .init(
        name: "Google DeepMind News",
        feedTitles: ["Google DeepMind News"],
        siteHosts: ["deepmind.google"],
        tagSlugs: ["artificial-intelligence", "generative-ai", "large-language-models", "research"]
    ),
    .init(
        name: "The latest research from Google",
        feedTitles: ["The latest research from Google"],
        siteHosts: ["research.google"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Microsoft Research Blog",
        feedTitles: ["Microsoft Research Blog - Microsoft Research"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "MIT News - Artificial intelligence",
        feedTitles: ["MIT News - Artificial intelligence"],
        siteHosts: ["news.mit.edu"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "MIT Technology Review AI",
        feedTitles: ["Artificial intelligence - MIT Technology Review", "Artificial intelligence – MIT Technology Review"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Import AI",
        feedTitles: ["Import AI"],
        siteHosts: ["importai.substack.com"],
        tagSlugs: ["artificial-intelligence", "research", "large-language-models"]
    ),
    .init(
        name: "Hugging Face Blog",
        feedTitles: ["Hugging Face - Blog"],
        siteHosts: ["huggingface.co"],
        tagSlugs: ["artificial-intelligence", "open-source", "developer-tools"]
    ),
    .init(
        name: "InfoQ DevOps",
        feedTitles: ["InfoQ - DevOps"],
        tagSlugs: ["cloud-infrastructure", "open-source", "developer-tools"]
    ),
    .init(
        name: "Kubernetes Blog",
        feedTitles: ["Kubernetes Blog"],
        siteHosts: ["kubernetes.io"],
        tagSlugs: ["kubernetes", "cloud-infrastructure", "open-source"]
    )
]

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
    "deep-learning": ["deep learning", "neural network", "neural networks"],
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
    "privacy": ["privacy", "tracking", "surveillance", "data protection"],
    "iot": ["iot", "internet of things", "connected device", "connected devices"],
    "consumer-hardware": ["smartphone", "smartphones", "laptop", "laptops", "wearable", "wearables", "headset"],
    "research": ["research", "paper", "papers", "study", "studies", "arxiv", "benchmark", "dataset", "preprint", "conference", "workshop"]
]
