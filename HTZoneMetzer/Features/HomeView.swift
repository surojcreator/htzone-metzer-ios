//
//  HomeView.swift
//  HTZoneMetzer
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var popular: [String] = []
    @State private var loaded = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting
                if !app.banners.isEmpty {
                    bannerCarousel
                }
                if !app.ellipses.isEmpty {
                    ellipseRow
                }
                searchLink

                if !app.categories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "קטגוריות")
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(Array(app.categories.prefix(8))) { node in
                                NavigationLink {
                                    CategoryDetailView(node: node)
                                } label: {
                                    CategoryCard(node: node)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        NavigationLink {
                            CatalogView()
                        } label: {
                            HStack {
                                Text("כל \(app.categories.count) הקטגוריות")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                Spacer()
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !library.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "נצפו לאחרונה", actionTitle: "נקה") {
                            library.clearRecent()
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(library.recent) { entry in
                                    ProductCell(item: entry.item, width: 160)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                if !popular.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "חיפושים פופולריים")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(popular, id: \.self) { term in
                                    NavigationLink {
                                        SearchView(initialQuery: term)
                                    } label: {
                                        Chip(text: term)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                }

                NavigationLink {
                    ContentPageView(pageId: "1", title: "אודות")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Theme.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("אודות מצ״ר")
                                .font(.subheadline.weight(.semibold))
                            Text("מידע, תנאים ופרטי קשר")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .cardContainer()
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("בית")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.refreshConfig()
            await loadPopular()
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await loadPopular()
        }
    }

    @MainActor
    private func loadPopular() async {
        guard let data = try? await app.api.popularSearches() else { return }
        popular = HomeView.parsePopular(data)
    }

    /// The payload shape has varied between a plain list and a wrapped list.
    static func parsePopular(_ data: JSONValue) -> [String] {
        var terms: [String] = []
        let candidates: [JSONValue?] = [
            data,
            data["terms"],
            data["searches"],
            data["popular"],
            data["results"]
        ]
        for candidate in candidates {
            for entry in JSONCollections.array(candidate) {
                if let term = entry.stringValue?.nonEmpty {
                    terms.append(term)
                } else if let term = entry["term"]?.stringValue?.nonEmpty
                    ?? entry["title"]?.stringValue?.nonEmpty
                    ?? entry["value"]?.stringValue?.nonEmpty
                    ?? entry["name"]?.stringValue?.nonEmpty {
                    terms.append(term)
                }
            }
            if !terms.isEmpty { break }
        }
        var seen = Set<String>()
        return Array(terms.filter { seen.insert($0).inserted }.prefix(12))
    }

    private var ellipseRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(app.ellipses) { item in
                    ellipseCell(item)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    @ViewBuilder
    private func ellipseCell(_ item: EllipseItem) -> some View {
        if let categoryId = item.categoryId, categoryId != "0" {
            let node = app.categoryNode(id: categoryId)
                ?? CategoryNode(id: categoryId, title: item.title, level: 1, children: [])
            NavigationLink {
                CategoryDetailView(node: node)
            } label: {
                ellipseLabel(item)
            }
            .buttonStyle(.plain)
        } else if let url = item.webURL {
            Link(destination: url) {
                ellipseLabel(item)
            }
        } else {
            ellipseLabel(item)
        }
    }

    private func ellipseLabel(_ item: EllipseItem) -> some View {
        VStack(spacing: 6) {
            RemoteImage(url: item.imageURL)
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            if let title = item.title.nonEmpty {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 78, alignment: .top)
            }
        }
        .frame(width: 78)
    }

    private var bannerCarousel: some View {
        TabView {
            ForEach(app.banners) { banner in
                bannerCard(banner)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 190)
    }

    @ViewBuilder
    private func bannerCard(_ banner: Banner) -> some View {
        if let categoryId = banner.categoryId, categoryId != "0" {
            let node = app.categoryNode(id: categoryId)
                ?? CategoryNode(id: categoryId, title: banner.title, level: 1, children: [])
            NavigationLink {
                CategoryDetailView(node: node)
            } label: {
                bannerContent(banner)
            }
            .buttonStyle(.plain)
        } else if let url = banner.webURL {
            Link(destination: url) {
                bannerContent(banner)
            }
        } else {
            bannerContent(banner)
        }
    }

    private func bannerContent(_ banner: Banner) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: banner.imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            if let title = banner.title.nonEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var greeting: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("שלום, \(app.profile?.firstName ?? "")")
                    .font(.title2.weight(.bold))
                if let company = app.profile?.companyName, !company.isEmpty {
                    Text(company)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            ZStack {
                Circle().fill(Theme.cardStrong)
                Circle().stroke(Theme.stroke, lineWidth: 1)
                Text(app.profile?.initials ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
        }
        .padding(16)
        .cardContainer()
    }

    private var searchLink: some View {
        NavigationLink {
            SearchView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                Text("חיפוש מוצרים…")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(14)
            .cardContainer()
        }
        .buttonStyle(.plain)
    }
}
