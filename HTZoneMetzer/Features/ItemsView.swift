//
//  ItemsView.swift
//  HTZoneMetzer
//

import SwiftUI

struct ItemsView: View {
    let categoryId: String
    let title: String
    var promos: [PromoItem] = []

    @EnvironmentObject private var app: AppState
    @State private var items: [Item] = []
    @State private var page = 1
    @State private var total: Int?
    @State private var sort = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var didLoad = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var canLoadMore: Bool {
        hasMore && !isLoading
    }

    private var promosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "הטבות")
            ForEach(promos) { promo in
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let error {
                    ErrorBanner(message: error) {
                        Task { await load(reset: true) }
                    }
                }

                if !promos.isEmpty {
                    promosSection
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        ProductCell(item: item)
                            .onAppear {
                                if item.id == items.last?.id, canLoadMore {
                                    Task { await load(reset: false) }
                                }
                            }
                    }
                }

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding()
                }

                if !items.isEmpty, hasMore, !isLoading {
                    Button {
                        Task { await load(reset: false) }
                    } label: {
                        Text("טען עוד")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let total, total > 0, !items.isEmpty {
                    Text("מציג \(items.count) מתוך \(total)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 2)
                }

                if items.isEmpty, !isLoading, error == nil {
                    EmptyStateView(
                        icon: "bag",
                        title: "אין מוצרים",
                        message: "לא נמצאו מוצרים בקטגוריה זו."
                    )
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(reset: true) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach([1, 2, 3], id: \.self) { value in
                        Button {
                            sort = value
                            Task { await load(reset: true) }
                        } label: {
                            if sort == value {
                                Label(app.sortTitle(value), systemImage: "checkmark")
                            } else {
                                Text(app.sortTitle(value))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load(reset: true)
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let nextPage = reset ? 1 : page
        do {
            let result = try await app.fetchItems(categoryId: categoryId, page: nextPage, sortById: sort)
            if reset {
                items = result.items
            } else {
                let existing = Set(items.map(\.id))
                items += result.items.filter { !existing.contains($0.id) }
            }
            total = result.total ?? total
            page = nextPage + 1

            if let listTotal = result.total {
                hasMore = items.count < listTotal
            } else {
                hasMore = result.rawCount > 0 && result.rawCount >= result.pageSize
            }
            if result.rawCount == 0 || nextPage >= 60 {
                hasMore = false
            }
        } catch {
            self.error = app.message(for: error)
        }
    }
}

struct ItemCard: View {
    let item: Item

    private var subtitle: String? { item.subtitle.nonEmpty }

    private var showsOptions: Bool { item.isCollected && item.optionCount > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(height: 34, alignment: .topLeading)

            // Reserved line so cards with and without a distinct sub-title align.
            Text(subtitle ?? " ")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(height: 13, alignment: .topLeading)

            HStack(spacing: 4) {
                if showsOptions {
                    StatusBadge(text: "\(item.optionCount) אפשרויות", color: Theme.gold)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 24, alignment: .leading)

            Spacer(minLength: 0)

            if let text = item.textInsteadPrice.nonEmpty {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else {
                PriceView(price: item.price, fullPrice: item.fullPrice, isFrom: item.isPriceFrom)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 248, alignment: .topLeading)
        .cardContainer()
    }
}
