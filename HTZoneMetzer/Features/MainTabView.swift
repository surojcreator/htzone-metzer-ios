//
//  MainTabView.swift
//  HTZoneMetzer
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("בית", systemImage: "house.fill") }

            NavigationStack {
                CatalogView()
            }
            .tabItem { Label("קטלוג", systemImage: "square.grid.2x2.fill") }

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("חיפוש", systemImage: "magnifyingglass") }

            NavigationStack {
                CartView()
            }
            .tabItem { Label("סל", systemImage: "cart.fill") }
            .badge(app.cartCount)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("חשבון", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.accent)
    }
}
