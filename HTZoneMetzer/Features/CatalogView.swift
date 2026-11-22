//
//  CatalogView.swift
//  HTZoneMetzer
//

import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("כל הקטגוריות")
                    .font(.title3.weight(.semibold))

                if app.categories.isEmpty {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "אין קטגוריות",
                        message: "לא ניתן היה לטעון את הקטלוג. נסה שוב מאוחר יותר."
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(app.categories) { node in
                            NavigationLink {
                                CategoryDetailView(node: node)
                            } label: {
                                CategoryRow(node: node)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("קטלוג")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CategoryRow: View {
    let node: CategoryNode

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.cardStrong)
                Text(String(node.title.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .cardContainer()
    }

    private var subtitle: String {
        if node.children.isEmpty { return "מוצרים" }
        return "\(node.children.count) תתי־קטגוריות"
    }
}

struct CategoryCard: View {
    let node: CategoryNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(Theme.cardStrong)
                Text(String(node.title.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 38, height: 38)

            Text(node.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(node.children.isEmpty ? "מוצרים" : "\(node.children.count) תתי־קטגוריות")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .cardContainer()
    }
}

struct CategoryDetailView: View {
    let node: CategoryNode

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if node.children.isEmpty {
                ItemsView(categoryId: node.id, title: node.title)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NavigationLink {
                            ItemsView(categoryId: node.id, title: "כל \(node.title)")
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.2x2.fill")
                                    .foregroundStyle(Theme.accent)
                                Text("כל המוצרים ב\(node.title)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(14)
                            .cardContainer()
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(node.children.filter { $0.id != "0" }) { child in
                                NavigationLink {
                                    CategoryDetailView(node: child)
                                } label: {
                                    CategoryCard(node: child)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(node.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
