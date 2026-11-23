//
//  APIClient.swift
//  HTZoneMetzer
//

import Foundation

enum Tenant: String, CaseIterable, Identifiable {
    case metzer
    case htzone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metzer: return "מצ״ר"
        case .htzone: return "HTZone"
        }
    }

    var baseURL: URL {
        switch self {
        case .metzer: return URL(string: "https://api.htzone.co.il/api/app/metzer/android/1.6/")!
        case .htzone: return URL(string: "https://api.htzone.co.il/api/android/1.6/")!
        }
    }
}

struct APIError: LocalizedError {
    let code: Int?
    let message: String

    var errorDescription: String? { message }
    var isAuthRequired: Bool { code == 150 }
    var isTenantDenied: Bool { code == 2011 }
    var isBadCredentials: Bool { code == 208 || code == 203 }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private(set) var tenant: Tenant = .metzer

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = [
            "User-Agent": "okhttp/4.9.2",
            "Accept": "application/json"
        ]
        session = URLSession(configuration: configuration)
    }

    func setTenant(_ newTenant: Tenant) {
        tenant = newTenant
    }

    func call(_ method: String, data: [String: Any] = [:]) async throws -> JSONValue {
        guard let url = URL(string: tenant.baseURL.absoluteString + method + "/") else {
            throw APIError(code: nil, message: "כתובת לא תקינה")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("okhttp/4.9.2", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

        let (raw, response): (Data, URLResponse)
        do {
            (raw, response) = try await session.data(for: request)
        } catch {
            throw APIError(code: nil, message: "שגיאת רשת: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(code: nil, message: "תגובה לא תקינה")
        }
        if http.statusCode == 403 {
            throw APIError(code: nil, message: "הבקשה נחסמה על ידי Cloudflare")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(code: http.statusCode, message: "שגיאת שרת (\(http.statusCode))")
        }

        guard let root = JSONValue.decodeResponse(raw) else {
            if raw.isEmpty {
                throw APIError(code: nil, message: "השרת החזיר תגובה ריקה. נסה שוב.")
            }
            if JSONValue.responseLooksLikeHTML(raw) {
                throw APIError(code: nil, message: "השרת החזיר דף חסימה. נסה שוב בעוד רגע.")
            }
            throw APIError(code: nil, message: "לא ניתן לקרוא את תגובת השרת")
        }

        if let err = root["err"], !err.isNull {
            if let object = err.objectValue {
                let code = object["id"]?.intValue
                let message = object["content"]?.stringValue ?? ""
                if code != nil || !message.isEmpty {
                    throw APIError(code: code, message: message.isEmpty ? "שגיאה" : message)
                }
            } else if let message = err.stringValue, !message.isEmpty {
                throw APIError(code: nil, message: message)
            }
        }

        let status = root["status"]?.intValue
        let hasError = !(root["err"]?.isNull ?? true)
        if status != 1, status != nil || hasError {
            let message = root["msg"]?.stringValue
                ?? root["message"]?.stringValue
                ?? "הפעולה נכשלה"
            throw APIError(code: status, message: message)
        }

        return root["data"] ?? .null
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> JSONValue {
        let encryptedEmail = try CredentialCrypto.encrypt(email)
        let encryptedPassword = try CredentialCrypto.encrypt(password)
        return try await call("loginUser", data: [
            "email": encryptedEmail,
            "password": encryptedPassword
        ])
    }

    func logout() async {
        _ = try? await call("logout")
    }

    func clearCookies() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }

    // MARK: - Catalog

    func declaration() async throws -> JSONValue {
        try await call("generalDeclaration")
    }

    func category(id: String) async throws -> JSONValue {
        try await call("getCategory", data: ["categoryId": id])
    }

    func items(categoryId: String, page: Int, sortById: Int? = nil) async throws -> JSONValue {
        var payload: [String: Any] = ["categoryId": categoryId, "page": page]
        if let sortById { payload["sortById"] = sortById }
        return try await call("getItems", data: payload)
    }

    func search(_ query: String) async throws -> JSONValue {
        try await call("searchQuery", data: ["q": query])
    }

    func salePage(id: String, page: Int = 1) async throws -> JSONValue {
        try await call("getSalePage", data: ["id": numeric(id), "page": page])
    }

    func contentPage(id: String) async throws -> JSONValue {
        try await call("getContentPage", data: ["pageId": id])
    }

    func popularSearches() async throws -> JSONValue {
        try await call("getPopularSearches")
    }

    func itemComments(itemId: String) async throws -> JSONValue {
        try await call("getItemComments", data: ["itemId": numeric(itemId)])
    }

    func itemMoreProducts(itemId: String) async throws -> JSONValue {
        try await call("getItemMoreProducts", data: ["itemId": numeric(itemId)])
    }

    func item(itemId: String) async throws -> JSONValue {
        try await call("getItem", data: ["itemId": numeric(itemId)])
    }

    // MARK: - Favourites / public reference data

    func favorites() async throws -> JSONValue {
        try await call("getUserFavorites")
    }

    /// The official client sends exactly `{ itemId, itemType }`;
    /// `itemType` is the product's `type_id` (1 for regular products).
    func addFavorite(itemId: String, itemType: String) async throws -> JSONValue {
        try await call("addToFavorites", data: [
            "itemId": numeric(itemId),
            "itemType": numeric(itemType)
        ])
    }

    func removeFavorite(itemId: String, itemType: String) async throws -> JSONValue {
        try await call("removeFromFavorites", data: [
            "itemId": numeric(itemId),
            "itemType": numeric(itemType)
        ])
    }

    func companies() async throws -> JSONValue {
        try await call("getCompanies")
    }

    func cities() async throws -> JSONValue {
        try await call("getCities")
    }

    func chitaboxList() async throws -> JSONValue {
        try await call("getChitaboxList")
    }

    func boxitAreas() async throws -> JSONValue {
        try await call("getBoxitAreas")
    }

    func boxitCities(areaId: String) async throws -> JSONValue {
        try await call("getBoxitCities", data: ["areaId": numeric(areaId)])
    }

    func boxitLockers(cityCode: String) async throws -> JSONValue {
        try await call("getBoxitLockers", data: ["cityCode": numeric(cityCode)])
    }

    func streets(cityId: String) async throws -> JSONValue {
        try await call("getStreets", data: ["cityId": numeric(cityId)])
    }

    func hostURL() async throws -> JSONValue {
        try await call("getHostUrl")
    }

    // MARK: - Cart

    func cart() async throws -> JSONValue {
        try await call("getCart")
    }

    func addToCart(itemId: String, quantity: Int, collectedId: String? = nil) async throws -> JSONValue {
        var payload: [String: Any] = [
            "itemId": numeric(itemId),
            "quantity": quantity
        ]
        // The official client sends `collectedIds` only for "collected"
        // (multi-variant) products; each entry selects one purchasable row.
        if let collectedId, !collectedId.isEmpty, collectedId != "0" {
            payload["collectedIds"] = [
                ["collectedId": numeric(collectedId), "quantity": quantity]
            ]
        }
        return try await call("addToCart", data: payload)
    }

    func removeFromCart(itemKey: String) async throws -> JSONValue {
        try await call("removeFromCart", data: ["itemKey": itemKey])
    }

    func popupValidate(responseKey: String, fields: [String: String]) async throws -> JSONValue {
        var payload: [String: Any] = ["response_key": responseKey]
        for (key, value) in fields { payload[key] = value }
        return try await call("popup_validate", data: payload)
    }

    // MARK: - Account

    func orders() async throws -> JSONValue {
        try await call("getUserOrders")
    }

    func order(id: String) async throws -> JSONValue {
        try await call("getUserOrder", data: ["orderId": numeric(id)])
    }

    private func numeric(_ value: String) -> Any {
        if let int = Int(value) { return int }
        return value
    }

    func wallet() async throws -> JSONValue {
        try await call("getUserWallet")
    }

    func cards() async throws -> JSONValue {
        try await call("getUserCards")
    }

    func proState() async throws -> JSONValue {
        try await call("checkProState")
    }
}
