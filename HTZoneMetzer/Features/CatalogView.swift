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
            CategoryIcon(node: node, size: 46)

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
            CategoryIcon(node: node, size: 38)

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

/// Category artwork from `categoriesImages`, with the initial as a fallback.
struct CategoryIcon: View {
    let node: CategoryNode
    var size: CGFloat

    @EnvironmentObject private var app: AppState

    var body: some View {
        if let url = app.categoryImage(id: node.id) {
            RemoteImage(url: url)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        } else {
            ZStack {
                Circle().fill(Theme.cardStrong)
                Text(String(node.title.prefix(1)))
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: size, height: size)
        }
    }
}

struct CategoryDetailView: View {
    let node: CategoryNode

    @EnvironmentObject private var app: AppState
    @State private var info: CategoryInfo?
    @State private var loadError: String?
    @State private var didLoad = false

    private var title: String {
        if let info, let value = info.title.nonEmpty { return value }
        return node.title
    }

    private var effectiveChildren: [CategoryNode] {
        if let info, !info.children.isEmpty {
            return info.children.filter { $0.id != "0" }
        }
        return node.children.filter { $0.id != "0" }
    }

    var body: some View {
        Group {
            if let info {
                if effectiveChildren.isEmpty {
                    ItemsView(categoryId: info.id.isEmpty ? node.id : info.id, title: title, promos: info.promos)
                } else {
                    CategoryLanding(node: node, info: info, children: effectiveChildren, title: title)
                }
            } else if let loadError {
                VStack(spacing: 12) {
                    ErrorBanner(message: loadError) { Task { await load() } }
                    if effectiveChildren.isEmpty {
                        ItemsView(categoryId: node.id, title: node.title)
                    } else {
                        CategoryLanding(
                            node: node,
                            info: CategoryInfo(id: node.id, title: node.title,
                                               children: effectiveChildren, total: nil, promos: []),
                            children: effectiveChildren,
                            title: node.title
                        )
                    }
                }
                .padding()
            } else {
                LoadingView(text: "טוען קטגוריה…")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
    }

    @MainActor
    private func load() async {
        do {
            info = try await app.categoryInfo(id: node.id)
            loadError = nil
        } catch {
            loadError = app.message(for: error)
        }
    }
}

struct CategoryLanding: View {
    let node: CategoryNode
    let info: CategoryInfo
    let children: [CategoryNode]
    let title: String

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    ItemsView(categoryId: info.id.isEmpty ? node.id : info.id, title: "כל \(title)")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("כל המוצרים ב\(title)")
                                .font(.subheadline.weight(.semibold))
                            if let total = info.total, total > 0 {
                                Text("\(total) מוצרים")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .cardContainer()
                }
                .buttonStyle(.plain)

                if !info.promos.isEmpty {
                    promosSection
                }

                SectionHeader(title: "תתי־קטגוריות")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(children) { child in
                        NavigationLink {
                            CategoryDetailView(node: child)
                        } label: {
                            CategoryCard(node: child)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ItemsPreview(categoryId: info.id.isEmpty ? node.id : info.id, title: title)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var promosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "הטבות")
            ForEach(info.promos) { promo in
                NavigationLink {
                    SearchView(initialQuery: promo.title)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promo.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            if let subtitle = promo.subtitle.nonEmpty {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .cardContainer()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ItemsPreview: View {
    let categoryId: String
    let title: String

    @EnvironmentObject private var app: AppState
    @State private var items: [Item] = []
    @State private var didLoad = false

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "מוצרים")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(items.prefix(8))) { item in
                                ProductCell(item: item, width: 160)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    NavigationLink {
                        ItemsView(categoryId: categoryId, title: title)
                    } label: {
                        Text("לכל המוצרים")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            if let page = try? await app.fetchItems(categoryId: categoryId, page: 1, sortById: 1) {
                items = page.items
            }
        }
    }
}
