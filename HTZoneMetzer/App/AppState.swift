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
        let forest = CategoryNode.forest(from: value)
        if !forest.isEmpty { categories = forest }
        if let server = value["media_server"]?.stringValue?.nonEmpty {
            mediaServer = server
        }
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

    func fetchItems(categoryId: String, page: Int, sortById: Int) async throws -> (items: [Item], total: Int) {
        let data = try await api.items(categoryId: categoryId, page: page, sortById: sortById)
        let payload = data[categoryId] ?? data.objectValue?.values.first ?? .null
        let items = JSONCollections.array(payload["itemsArr"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }
        let total = payload["total_items"]?.intValue ?? items.count
        return (items, total)
    }

    func search(_ query: String) async throws -> [Item] {
        let data = try await api.search(query)
        return JSONCollections.array(data["res"]).compactMap {
            Item(json: $0, mediaServer: mediaServer)
        }
    }

    func cart() async throws -> CartSummary? {
        let data = try await api.cart()
        return CartSummary(json: data, mediaServer: mediaServer)
    }

    func addToCart(itemId: String, quantity: Int) async throws -> PopupRequest? {
        let data = try await api.addToCart(itemId: itemId, quantity: quantity)
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
            .filter { seen.insert($0.id).inserted }
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
