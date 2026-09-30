import Foundation
import SwiftData

/// 20 invented people across all three platforms, with tags, notes and 5 Spaces.
/// For SwiftUI previews, tests and the DEBUG "Add sample data" action. Handles are
/// prefixed `tabby_sample` / `tabby-sample` so they do not point at real accounts.
@MainActor
public enum SampleData {
    struct Entry {
        let name: String
        let platform: Platform
        let handle: String
        let headline: String
        let bio: String
        let tags: [String]
        let note: String
        let daysAgo: Int
        var status: ExtractionStatus = .complete
    }

    static let entries: [Entry] = [
        Entry(name: "Mara Quill", platform: .instagram, handle: "tabby_sample_mara", headline: "",
              bio: "Packaging designer • Portland", tags: ["designer", "packaging"],
              note: "Great packaging work, possible collaborator", daysAgo: 1),
        Entry(name: "Dev Okafor", platform: .tiktok, handle: "tabby_sample_dev", headline: "",
              bio: "hardware tinkerer 🔧", tags: ["hardware", "maker"], note: "Explains PCB design really clearly", daysAgo: 2),
        Entry(name: "Priya Castellan", platform: .linkedin, handle: "tabby-sample-priya", headline: "Industrial Designer · Northwind Labs",
              bio: "I design hardware that ships.", tags: ["designer", "hardware", "boston"],
              note: "Met at the Boston design meetup", daysAgo: 3),
        Entry(name: "Leo Brandt", platform: .instagram, handle: "tabby_sample_leo", headline: "",
              bio: "Furniture maker. Commissions open.", tags: ["maker", "woodwork"], note: "", daysAgo: 5),
        Entry(name: "Ines Varga", platform: .linkedin, handle: "tabby-sample-ines", headline: "Head of Product · Lumen Health",
              bio: "", tags: ["founder", "health", "boston"], note: "Hiring PMs next quarter", daysAgo: 8),
        Entry(name: "Tomasz Reyes", platform: .tiktok, handle: "tabby_sample_tomasz", headline: "",
              bio: "street food, one bite at a time", tags: ["food"], note: "", daysAgo: 9),
        Entry(name: "Aiko Lindqvist", platform: .instagram, handle: "tabby_sample_aiko", headline: "",
              bio: "Ceramicist. Stoneware and glazes.", tags: ["maker", "ceramics"], note: "Custom mugs for the office?", daysAgo: 12),
        Entry(name: "Sam Achebe", platform: .linkedin, handle: "tabby-sample-sam", headline: "Firmware Engineer · Ferrous Robotics",
              bio: "", tags: ["hardware", "engineer", "cambridge"], note: "", daysAgo: 14),
        Entry(name: "Noor Haddad", platform: .tiktok, handle: "tabby_sample_noor", headline: "",
              bio: "strength coach | form checks", tags: ["fitness"], note: "", daysAgo: 16),
        Entry(name: "Felix Moreau", platform: .instagram, handle: "tabby_sample_felix", headline: "",
              bio: "Brand identity for small studios", tags: ["designer", "branding"], note: "Rebrand candidate", daysAgo: 20),
        Entry(name: "Rosa Delgado", platform: .linkedin, handle: "tabby-sample-rosa", headline: "Founder · Tidewater Foods",
              bio: "", tags: ["founder", "food"], note: "", daysAgo: 24),
        Entry(name: "Kenji Park", platform: .tiktok, handle: "tabby_sample_kenji", headline: "",
              bio: "3D printing everything", tags: ["hardware", "maker"], note: "", daysAgo: 27),
        Entry(name: "Olivia Grant", platform: .instagram, handle: "tabby_sample_olivia", headline: "",
              bio: "Pilates · Back Bay", tags: ["fitness", "boston"], note: "", daysAgo: 33),
        Entry(name: "Arjun Mehta", platform: .linkedin, handle: "tabby-sample-arjun", headline: "Mechanical Engineer · Orbital Dynamics",
              bio: "", tags: ["engineer", "hardware", "designer"], note: "Enclosure design expert", daysAgo: 38),
        Entry(name: "Chloé Dubois", platform: .instagram, handle: "tabby_sample_chloe", headline: "",
              bio: "Food photographer", tags: ["food", "photography"], note: "", daysAgo: 41),
        Entry(name: "Marcus Bell", platform: .tiktok, handle: "tabby_sample_marcus", headline: "",
              bio: "running coach, 5k to marathon", tags: ["fitness"], note: "", daysAgo: 45),
        Entry(name: "Hana Sato", platform: .linkedin, handle: "tabby-sample-hana", headline: "UX Researcher · Brightline",
              bio: "", tags: ["designer", "research", "cambridge"], note: "", daysAgo: 50),
        Entry(name: "Diego Alvarez", platform: .instagram, handle: "tabby_sample_diego", headline: "",
              bio: "Hand-built steel bikes", tags: ["hardware", "maker"], note: "", daysAgo: 55),
        Entry(name: "Freya Nilsen", platform: .tiktok, handle: "tabby_sample_freya", headline: "",
              bio: "", tags: [], note: "", daysAgo: 58, status: .pending),
        Entry(name: "", platform: .linkedin, handle: "tabby-sample-omar", headline: "",
              bio: "", tags: [], note: "Profile was behind the login wall", daysAgo: 60, status: .failed),
    ]

    static let spaces: [(draft: SpaceDraft, tags: [String], pinned: Bool)] = [
        (SampleData.space("Hardware designers", icon: "cpu", color: 0, matchAll: true), ["designer", "hardware"], true),
        (SampleData.space("Boston", icon: "building.2.fill", color: 3, matchAll: false), ["boston", "cambridge"], false),
        (SampleData.space("Makers", icon: "hammer.fill", color: 4, matchAll: false), ["maker"], false),
        (SampleData.space("Fitness creators", icon: "figure.run", color: 6, matchAll: false, platforms: [.tiktok, .instagram]), ["fitness"], false),
        (SampleData.space("Food", icon: "fork.knife", color: 5, matchAll: false), ["food"], false),
    ]

    private static func space(_ name: String, icon: String, color: Int, matchAll: Bool, platforms: Set<Platform> = []) -> SpaceDraft {
        var draft = SpaceDraft()
        draft.name = name
        draft.icon = icon
        draft.colorIndex = color
        draft.matchAll = matchAll
        draft.platforms = platforms
        return draft
    }

    public static func seed(into context: ModelContext, now: Date = .now) {
        let store = TabbyStore(context: context)
        for entry in entries {
            let date = now.addingTimeInterval(-Double(entry.daysAgo) * 86_400)
            var draft = PersonDraft(
                platform: entry.platform,
                handle: entry.handle,
                profileURL: ProfileURLParser.profile(platform: entry.platform, handle: entry.handle)?.url
            )
            draft.displayName = entry.name
            draft.headline = entry.headline
            draft.bio = entry.bio
            draft.note = entry.note
            draft.extractionStatus = entry.status
            draft.tagIDs = Set(entry.tags.compactMap { store.findOrCreateTag(named: $0, at: date)?.id })
            _ = try? store.save(draft, at: date)
        }
        for (index, sample) in spaces.enumerated() {
            var draft = sample.draft
            draft.tagIDs = Set(sample.tags.compactMap { store.tag(named: $0)?.id })
            let created = try? store.createSpace(draft, at: now.addingTimeInterval(Double(index)))
            if sample.pinned, let created { store.setPinned(true, for: created) }
        }
    }

    /// An in-memory container seeded with the sample data, for previews.
    public static func previewContainer() -> ModelContainer {
        let container = try! TabbyContainer.make(inMemory: true)
        seed(into: container.mainContext)
        return container
    }
}
