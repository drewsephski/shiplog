import Foundation

enum BuildKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case feature, improvement, fix, release, learning
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feature: "Feature"
        case .improvement: "Improvement"
        case .fix: "Fix"
        case .release: "Release"
        case .learning: "Learning"
        }
    }
    var symbol: String {
        switch self {
        case .feature: "plus.square"
        case .improvement: "slider.horizontal.3"
        case .fix: "wrench.adjustable"
        case .release: "shippingbox"
        case .learning: "book.closed"
        }
    }
}

enum EntryOrigin: String, Codable, Sendable {
    case manual, imported, generated, userEditedGenerated
}

enum SummaryPeriod: String, Codable, Sendable {
    case daily, weekly
}

enum SummaryOrigin: String, Codable, Sendable {
    case manual, generatedDraft, userEditedGenerated
}
