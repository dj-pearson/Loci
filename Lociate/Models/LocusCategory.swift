import SwiftUI

enum LocusCategory: String, Codable, CaseIterable, Identifiable {
    case general
    case food
    case shopping
    case parking
    case health
    case travel
    case tip
    case warning
    case home
    case outdoor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: String(localized: "General")
        case .food: String(localized: "Food")
        case .shopping: String(localized: "Shopping")
        case .parking: String(localized: "Parking")
        case .health: String(localized: "Health")
        case .travel: String(localized: "Travel")
        case .tip: String(localized: "Tip")
        case .warning: String(localized: "Warning")
        case .home: String(localized: "Home")
        case .outdoor: String(localized: "Outdoor")
        }
    }

    var systemImageName: String {
        switch self {
        case .general: "mappin"
        case .food: "fork.knife"
        case .shopping: "cart"
        case .parking: "car"
        case .health: "heart"
        case .travel: "airplane"
        case .tip: "lightbulb"
        case .warning: "exclamationmark.triangle"
        case .home: "house"
        case .outdoor: "leaf"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(.systemBlue)
        case .food: Color(.systemOrange)
        case .shopping: Color(.systemPurple)
        case .parking: Color(.systemIndigo)
        case .health: Color(.systemRed)
        case .travel: Color(.systemTeal)
        case .tip: Color(.systemYellow)
        case .warning: Color(.systemPink)
        case .home: Color(.systemGreen)
        case .outdoor: Color(.systemMint)
        }
    }
}
