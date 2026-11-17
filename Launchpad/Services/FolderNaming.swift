import AppKit

/// Picks the name for a freshly created folder from its apps' App Store
/// categories, the way Launchpad does ("Utilities", "Productivity", …).
enum FolderNaming {
    static func suggestedName(for apps: [AppItem]) -> String {
        let categories = apps.compactMap(category(for:))
        guard let first = categories.first,
              categories.allSatisfy({ $0 == first }),
              let name = displayNames[first] else { return "Folder" }
        return name
    }

    static func category(for app: AppItem) -> String? {
        Bundle(url: app.url)?
            .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }

    private static let displayNames: [String: String] = [
        "public.app-category.business": "Business",
        "public.app-category.developer-tools": "Developer Tools",
        "public.app-category.education": "Education",
        "public.app-category.entertainment": "Entertainment",
        "public.app-category.finance": "Finance",
        "public.app-category.games": "Games",
        "public.app-category.graphics-design": "Graphics & Design",
        "public.app-category.healthcare-fitness": "Health & Fitness",
        "public.app-category.lifestyle": "Lifestyle",
        "public.app-category.medical": "Medical",
        "public.app-category.music": "Music",
        "public.app-category.news": "News",
        "public.app-category.photography": "Photography",
        "public.app-category.productivity": "Productivity",
        "public.app-category.reference": "Reference",
        "public.app-category.social-networking": "Social Networking",
        "public.app-category.sports": "Sports",
        "public.app-category.travel": "Travel",
        "public.app-category.utilities": "Utilities",
        "public.app-category.video": "Video",
        "public.app-category.weather": "Weather",
        "public.app-category.food-and-drink": "Food & Drink",
        "public.app-category.shopping": "Shopping",
        "public.app-category.bookkeeping": "Bookkeeping",
        "public.app-category.books": "Books"
    ]
}
