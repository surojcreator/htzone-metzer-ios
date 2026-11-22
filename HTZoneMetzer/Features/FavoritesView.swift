//
//  FavoritesView.swift
//  HTZoneMetzer
//

import SwiftUI

/// Heart control placed on top of a product card.
struct FavoriteButton: View {
    let item: Item

    @EnvironmentObject private var library: LibraryStore

    private var isFavorite: Bool { library.isFavorite(item.id) }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                library.toggleFavorite(item)
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.danger : Color.white)
                .padding(7)
                .background(Color.black.opacity(0.38), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "הסר ממועדפים" : "הוסף למועדפים")
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var library: LibraryStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if library.favorites.isEmpty {
                    EmptyStateView(
                        icon: "heart",
                        title: "אין מועדפים",
                        message: "לחץ על הלב בכרטיס מוצר כדי לשמור אותו כאן."
                    )
                    .frame(height: 320)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(library.favorites) { entry in
                            ProductCell(item: entry.item)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("מועדפים")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Card plus favourite heart, laid out as one grid/horizontal cell.
struct ProductCell: View {
    let item: Item
    var width: CGFloat?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                ItemDetailView(item: item)
            } label: {
                ItemCard(item: item)
            }
            .buttonStyle(.plain)

            FavoriteButton(item: item)
                .padding(14)
        }
        .frame(width: width)
    }
}
