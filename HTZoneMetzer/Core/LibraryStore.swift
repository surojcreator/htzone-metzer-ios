//
//  LibraryStore.swift
//  HTZoneMetzer
//

import Foundation
import Combine

/// Cached product snapshot so favourites and history render without a request.
struct LibraryItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let price: Double?
    let fullPrice: Double?
    let imagePath: String
    let brand: String
    let category: String
    let isPriceFrom: Bool
    let textInsteadPrice: String
    let rating: Double
    let reviews: Int
    let isCollected: Bool
    let optionCount: Int

    init(item: Item) {
        id = item.id
        title = item.title
        subtitle = item.subtitle
        price = item.price
        fullPrice = item.fullPrice
        imagePath = item.imageURL?.absoluteString ?? ""
        brand = item.brand
        category = item.category
        isPriceFrom = item.isPriceFrom
        textInsteadPrice = item.textInsteadPrice
        rating = item.rating
        reviews = item.reviews
        isCollected = item.isCollected
        optionCount = item.optionCount
    }

    var imageURL: URL? {
        imagePath.isEmpty ? nil : URL(string: imagePath)
    }

    var item: Item {
        Item(id: id,
             title: title,
             subtitle: subtitle,
             price: price,
             fullPrice: fullPrice,
             imageURL: imageURL,
             brand: brand,
             category: category,
             isPriceFrom: isPriceFrom,
             textInsteadPrice: textInsteadPrice,
             rating: rating,
             reviews: reviews,
             isCollected: isCollected,
             optionCount: optionCount)
    }
}

/// On-device favourites and recently viewed products.
///
/// The server's favourites endpoints reject every parameter shape recovered
/// from the client, so this state lives locally instead of breaking the UI.
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [LibraryItem]
    @Published private(set) var recent: [LibraryItem]

    private let favoritesKey = "library.favorites.v1"
    private let recentKey = "library.recent.v1"
    private let recentLimit = 12
    private let favoritesLimit = 100

    private init() {
        favorites = LibraryStore.load(favoritesKey)
        recent = LibraryStore.load(recentKey)
    }

    func isFavorite(_ id: String) -> Bool {
        favorites.contains { $0.id == id }
    }

    func toggleFavorite(_ item: Item) {
        if let index = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(LibraryItem(item: item), at: 0)
            if favorites.count > favoritesLimit {
                favorites = Array(favorites.prefix(favoritesLimit))
            }
        }
        LibraryStore.save(favorites, favoritesKey)
    }

    func removeFavorite(_ id: String) {
        favorites.removeAll { $0.id == id }
        LibraryStore.save(favorites, favoritesKey)
    }

    func recordViewed(_ item: Item) {
        recent.removeAll { $0.id == item.id }
        recent.insert(LibraryItem(item: item), at: 0)
        if recent.count > recentLimit {
            recent = Array(recent.prefix(recentLimit))
        }
        LibraryStore.save(recent, recentKey)
    }

    func clearRecent() {
        recent = []
        LibraryStore.save(recent, recentKey)
    }

    private static func load(_ key: String) -> [LibraryItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([LibraryItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func save(_ items: [LibraryItem], _ key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
