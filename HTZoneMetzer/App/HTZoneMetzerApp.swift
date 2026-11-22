//
//  HTZoneMetzerApp.swift
//  HTZoneMetzer
//

import SwiftUI

@main
struct HTZoneMetzerApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}
