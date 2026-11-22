//
//  Theme.swift
//  HTZoneMetzer
//

import SwiftUI

enum Theme {
    static let nav = Color(red: 0.008, green: 0.098, blue: 0.325)
    static let deep = Color(red: 0.02, green: 0.06, blue: 0.20)
    static let accent = Color(red: 0.36, green: 0.55, blue: 1.0)
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.32)
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.38)
    static let success = Color(red: 0.36, green: 0.82, blue: 0.56)
    static let card = Color.white.opacity(0.07)
    static let cardStrong = Color.white.opacity(0.12)
    static let stroke = Color.white.opacity(0.12)
    static let textSecondary = Color.white.opacity(0.66)
    static let background = LinearGradient(
        colors: [nav, deep],
        startPoint: .top,
        endPoint: .bottom
    )
}
