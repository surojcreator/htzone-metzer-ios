//
//  SearchView.swift
//  HTZoneMetzer
//

import Foundation
import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppState
    var initialQuery: String = ""

    @State private var query = ""
    @State private var results: [Item] = []
    @State private var categoryResults: [CategoryNode] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var recent: [String] = []

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let recentKey = "recentSearches"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchField

                if let error {
                    ErrorBanner(message: error)
                }

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView().tint(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !recent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "חיפושים אחרונים")
                            FlowChips(items: recent) { term in
                                query = term
                            }
                        }
                    }
                } else if results.isEmpty, !isSearching, error == nil {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "לא נמצאו תוצאות",
                        message: "נסה מילה אחרת או בדוק את האיות."
                    )
                }

                if !categoryResults.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "קטגוריות")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categoryResults) { category in
                                    NavigationLink {
                                        CategoryDetailView(node: category)
                                    } label: {
                                        Chip(text: category.title)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { item in
                        ProductCell(item: item)
                    }
                }

                if results.count >= 8 {
                    Text("החיפוש מוגבל לשמונה תוצאות. הוסף מילה כדי לצמצם את הרשימה.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("חיפוש")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if query.isEmpty, !initialQuery.isEmpty {
                query = initialQuery
            }
            recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        }
        .task(id: query) {
            await runSearch()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)

            TextField("מה לחפש?", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    categoryResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .cardContainer()
    }

    @MainActor
    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            results = []
            categoryResults = []
            error = nil
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        isSearching = true
        error = nil
        defer { isSearching = false }

        do {
            let result = try await app.searchResults(term)
            results = result.items
            categoryResults = result.categories
            if !results.isEmpty {
                remember(term)
            }
        } catch {
            self.error = app.message(for: error)
        }
    }

    private func remember(_ term: String) {
        var list = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        list.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        list.insert(term, at: 0)
        list = Array(list.prefix(8))
        UserDefaults.standard.set(list, forKey: recentKey)
        recent = list
    }
}

struct FlowChips: View {
    let items: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        Chip(text: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
