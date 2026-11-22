//
//  HomeView.swift
//  HTZoneMetzer
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
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
        .task {
            guard !loaded else { return }
            loaded = true
            if let data = try? await app.api.popularSearches() {
                popular = Array(JSONCollections.array(data)
                    .compactMap { $0["term"]?.stringValue }
                    .prefix(12))
            }
        }
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
        if let categoryId = banner.categoryId,
           let node = app.categoryNode(id: categoryId) {
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
