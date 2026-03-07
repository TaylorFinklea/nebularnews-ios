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

public let deterministicTagKeywordsBySlug: [String: [String]] = [
    "artificial-intelligence": ["artificial intelligence", "ai"],
    "generative-ai": ["generative ai", "diffusion", "image generation"],
    "large-language-models": ["llm", "llms", "large language model", "large language models", "foundation model"],
    "ai-agents": ["ai agent", "ai agents", "agentic", "tool use", "tool-using agent"],
    "ai-safety": ["ai safety", "alignment", "model eval", "model evals", "guardrail", "guardrails"],
    "conversational-ai": ["chatbot", "assistant", "conversational ai"],
    "deep-learning": ["deep learning", "neural network", "neural networks"],
    "robotics": ["robot", "robots", "robotics", "humanoid"],
    "cybersecurity": ["cybersecurity", "cyber", "infosec", "malware", "breach", "vulnerability", "vulnerabilities"],
    "cloud-infrastructure": ["cloud", "infrastructure", "compute platform"],
    "kubernetes": ["kubernetes", "k8s"],
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
    "research": ["research", "paper", "papers", "study", "studies", "arxiv"]
]
