//
//  ItemsView.swift
//  HTZoneMetzer
//

import SwiftUI

struct ItemsView: View {
    let categoryId: String
    let title: String

    @EnvironmentObject private var app: AppState
    @State private var items: [Item] = []
    @State private var page = 1
    @State private var total = 0
    @State private var sort = 1
    @State private var isLoading = false
    @State private var error: String?
    @State private var didLoad = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var canLoadMore: Bool {
        !isLoading && items.count < total
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let error {
                    ErrorBanner(message: error) {
                        Task { await load(reset: true) }
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            ItemCard(item: item)
                        }
                        .buttonStyle(.plain)
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
            total = result.total
            page = nextPage + 1
        } catch {
            self.error = app.message(for: error)
        }
    }
}

struct ItemCard: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(height: 36, alignment: .topLeading)

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
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .cardContainer()
    }
}
