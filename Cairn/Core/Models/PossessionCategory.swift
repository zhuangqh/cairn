import Foundation
import SwiftUI

/// Stable persistence tokens for physical-possession categories (PRD §4.7, v1.1).
///
/// Raw values are written to the store and MUST NOT be changed without a migration.
/// User-facing labels come from the String Catalog (`possession.category.*`).
public enum PossessionCategory: String, Codable, CaseIterable, Sendable {
    case realEstate
    case vehicle
    case electronics
    case other

    /// Localization key for the user-facing name of the category.
    public var localizationKey: String {
        switch self {
        case .realEstate: return "possession.category.realEstate"
        case .vehicle: return "possession.category.vehicle"
        case .electronics: return "possession.category.electronics"
        case .other: return "possession.category.other"
        }
    }

    /// Default SF Symbol used to represent the category.
    public var iconName: String {
        switch self {
        case .realEstate: return "house.fill"
        case .vehicle: return "car.fill"
        case .electronics: return "laptopcomputer"
        case .other: return "shippingbox.fill"
        }
    }

    /// Category hue for badges and icon tiles, from `Color.categoryPalette`.
    public var tint: Color {
        switch self {
        case .realEstate: return .accent
        case .vehicle: return .mist
        case .electronics: return .terracotta
        case .other: return .brass
        }
    }
}
