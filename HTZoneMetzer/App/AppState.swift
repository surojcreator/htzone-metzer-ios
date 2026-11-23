//
//  AppState.swift
//  HTZoneMetzer
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case loading
        case loggedOut
        case loggedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var profile: Profile?
    @Published private(set) var tenant: Tenant = .metzer
    @Published private(set) var categories: [CategoryNode] = []
    @Published private(set) var banners: [Banner] = []
    @Published private(set) var ellipses: [EllipseItem] = []
    @Published private(set) var categoryImages: [String: URL] = [:]
    @Published private(set) var cartCount: Int = 0
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    let api = APIClient.shared

    private let cache = ConfigCache()
    private var declaration: JSONValue?
    private var mediaServer = "https://media.htzone.co.il"

    // MARK: - Bootstrap

    func bootstrap() async {
        await restoreTenant()
        if let cached = cache.load() {
            applyDeclaration(cached)
        }
        await loadDeclaration()

        if let saved = ProfileStore.load() {
            profile = saved
            do {
                _ = try await api.orders()
                phase = .loggedIn
                await refreshCart()
                await refreshFavorites()
            } catch let error as APIError where error.isAuthRequired {
                ProfileStore.clear()
                profile = nil
                phase = .loggedOut
            } catch {
                // Keep the cached profile; the session may still be valid offline.
                phase = .loggedIn
            }
        } else {
            phase = .loggedOut
        }
    }

    private func restoreTenant() async {
        guard let raw = UserDefaults.standard.string(forKey: "tenant"),
              let saved = Tenant(rawValue: raw) else { return }
        tenant = saved
        await api.setTenant(saved)
    }

    private func loadDeclaration() async {
        do {
            let fresh = try await api.declaration()
            cache.save(fresh)
            applyDeclaration(fresh)
        } catch {
            // Cached declaration stays in effect.
        }
    }

    private func applyDeclaration(_ value: JSONValue) {
        declaration = value
        if let server = value["media_server"]?.stringValue?.nonEmpty {
            mediaServer = server
        }
        banners = Banner.list(from: value, mediaServer: mediaServer)
        ellipses = EllipseItem.list(from: value, mediaServer: mediaServer)
        var images: [String: URL] = [:]
        if let map = value["categoriesImages"]?.objectValue {
            for (key, entry) in map {
                if let url = Item.makeURL(entry.stringValue, mediaServer: mediaServer) {
                    images[key] = url
                }
            }
        }
        categoryImages = images
        let forest = CategoryNode.forest(from: value)
        if !forest.isEmpty { categories = forest }
    }

    // MARK: - Auth

    func login(email: String, password: String, remember: Bool, tenant: Tenant) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            await api.setTenant(tenant)
            self.tenant = tenant
            UserDefaults.standard.set(tenant.rawValue, forKey: "tenant")
            let data = try await api.login(email: email, password: password)
            guard let profile = Profile(json: data) else {
                throw APIError(code: nil, message: "לא ניתן לקרוא את פרטי המשתמש")
            }
            self.profile = profile
            ProfileStore.save(profile)
            UserDefaults.standard.set(email, forKey: "lastEmail")
            if remember {
                Keychain.save(email: email, password: password)
            } else {
                Keychain.delete()
            }
            await refreshCart()
            phase = .loggedIn
            await refreshFavorites()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func logout() async {
        await api.logout()
        await api.clearCookies()
        Keychain.delete()
        ProfileStore.clear()
        profile = nil
        cartCount = 0
        phase = .loggedOut
    }

    func refreshCart() async {
        do {
            let data = try await api.cart()
            cartCount = CartSummary(json: data, mediaServer: mediaServer)?.totalItems ?? 0
        } catch {
            cartCount = 0
        }
    }

    // MARK: - Catalog

    func fetchItems(categoryId: String, page: Int, sortById: Int) async throws -> ItemsPage {
        let data = try await api.items(categoryId: categoryId, page: page, sortById: sortById)
        let payload = data[categoryId] ?? data.objectValue?.values.first ?? .null
        let mapped = JSONCollections.array(payload["itemsArr"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }
        let items = mapped.filter { !$0.isBanner }
        let total = payload["total_items"]?.intValue
        let from = payload["from"]?.intValue
        let to = payload["to"]?.intValue
        let pageSize: Int
        if let from, let to, to > from {
            pageSize = to - from
        } else {
            pageSize = 100
        }
        return ItemsPage(items: items, total: total, rawCount: mapped.count, pageSize: pageSize)
    }

    func categoryInfo(id: String) async throws -> CategoryInfo? {
        let data = try await api.category(id: id)
        return CategoryInfo(json: data)
    }

    func itemDetail(id: String, itemType: String = "1") async throws -> ItemDetail? {
        let raw = try await api.item(itemId: id, itemType: itemType)
        let payload: JSONValue
        if let array = raw.arrayValue {
            payload = array.first ?? .null
        } else {
            payload = raw
        }
        guard !payload.isNull else {
            throw APIError(code: nil, message: "המוצר אינו זמין כרגע")
        }
        return ItemDetail(json: payload, mediaServer: mediaServer)
    }

    func categoryImage(id: String) -> URL? {
        categoryImages[id]
    }

    func categoryNode(id: String) -> CategoryNode? {
        func search(_ nodes: [CategoryNode]) -> CategoryNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = search(node.children) { return found }
            }
            return nil
        }
        return search(categories)
    }

    func search(_ query: String) async throws -> [Item] {
        let data = try await api.search(query)
        return JSONCollections.array(data["res"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }.filter { !$0.isBanner }
    }

    func searchResults(_ query: String) async throws -> (items: [Item], categories: [CategoryNode]) {
        let data = try await api.search(query)
        let items = JSONCollections.array(data["res"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }.filter { !$0.isBanner }
        let categories = JSONCollections.array(data["categories"]).compactMap {
            CategoryNode.node(from: $0, level: 2)
        }
        return (items, categories)
    }

    func cart() async throws -> CartSummary? {
        let data = try await api.cart()
        let summary = CartSummary(json: data, mediaServer: mediaServer)
        cartCount = summary?.totalItems ?? 0
        return summary
    }

    /// Re-fetches the declaration so banners and the category tree refresh.
    func refreshConfig() async {
        await loadDeclaration()
    }

    func addToCart(itemId: String, quantity: Int, collectedId: String? = nil) async throws -> PopupRequest? {
        let data = try await api.addToCart(itemId: itemId, quantity: quantity, collectedId: collectedId)
        await refreshCart()
        if let popupValue = data["popupObject"] ?? data["popup"],
           let popup = PopupRequest(json: popupValue) {
            return popup
        }
        return nil
    }

    func removeFromCart(itemKey: String) async throws {
        _ = try await api.removeFromCart(itemKey: itemKey)
        await refreshCart()
    }

    func submitPopup(_ popup: PopupRequest, values: [String: String]) async throws -> JSONValue {
        try await api.popupValidate(responseKey: popup.responseKey, fields: values)
    }

    func comments(itemId: String) async throws -> [ItemComment] {
        let data = try await api.itemComments(itemId: itemId)
        return ItemComment.list(from: data)
    }

    func related(itemId: String) async throws -> [Item] {
        let data = try await api.itemMoreProducts(itemId: itemId)
        let values = JSONCollections.array(data["itemsArr"]) + JSONCollections.array(data["bestSellers"])
        var seen = Set<String>()
        return values.compactMap { Item(json: $0, mediaServer: mediaServer) }
            .filter { !$0.isBanner && seen.insert($0.id).inserted }
    }

    // MARK: - Favourites

    /// Pulls the server's favourites list and refreshes the local cache.
    func refreshFavorites() async {
        guard case .loggedIn = phase else { return }
        do {
            let data = try await api.favorites()
            applyFavorites(data)
        } catch {
            // Keep the cached list when the call fails.
        }
    }

    /// Optimistic favourites change; rolls the local cache back if rejected.
    func syncFavorite(_ item: Item, favorite: Bool) async {
        do {
            let data = favorite
                ? try await api.addFavorite(itemId: item.id, itemType: item.itemType)
                : try await api.removeFavorite(itemId: item.id, itemType: item.itemType)
            applyFavorites(data)
        } catch {
            LibraryStore.shared.setFavorite(item, favorite: !favorite)
            errorMessage = message(for: error)
        }
    }

    private func applyFavorites(_ data: JSONValue) {
        guard data["favorites_itemsArr"] != nil else { return }
        let items = JSONCollections.array(data["favorites_itemsArr"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }
        LibraryStore.shared.replaceFavorites(with: items)
    }

    func contentPage(id: String) async throws -> JSONValue {
        try await api.contentPage(id: id)
    }

    // MARK: - Account

    func orders() async throws -> [OrderSummary] {
        let data = try await api.orders()
        return OrderSummary.list(from: data)
    }

    func orderDetail(id: String) async throws -> OrderDetail? {
        let data = try await api.order(id: id)
        return OrderDetail(json: data, mediaServer: mediaServer)
    }

    func wallet() async throws -> WalletInfo? {
        let data = try await api.wallet()
        return WalletInfo(json: data)
    }

    func cards() async throws -> [CardInfo] {
        let data = try await api.cards()
        return CardInfo.list(from: data)
    }

    // MARK: - Config helpers

    func t(_ key: String, _ fallback: String) -> String {
        guard let declaration,
              let translations = declaration["translationsArr"],
              let translation = translations[key],
              let text = translation["text"]?.stringValue?.nonEmpty else {
            return fallback
        }
        return text
    }

    func statusText(_ status: Int) -> String {
        if let declaration,
           let statuses = declaration["order_list_statuses"],
           let entry = statuses[String(status)],
           let text = entry["text"]?.stringValue?.nonEmpty {
            return text
        }
        return "סטטוס \(status)"
    }

    func sortTitle(_ sort: Int) -> String {
        if let declaration,
           let sorts = declaration["sortArr"],
           let entry = sorts[String(sort)],
           let title = entry["title"]?.stringValue?.nonEmpty {
            return title
        }
        switch sort {
        case 2: return "מחיר מהנמוך לגבוה"
        case 3: return "מחיר מהגבוה לנמוך"
        default: return "הפופולרי ביותר"
        }
    }

    func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.isTenantDenied {
                return "המשתמש אינו מורשה באפליקציית מצ״ר"
            }
            if apiError.isBadCredentials {
                return "מייל או סיסמה לא נכונים"
            }
            return apiError.message.isEmpty ? "שגיאה" : apiError.message
        }
        return error.localizedDescription
    }
}
