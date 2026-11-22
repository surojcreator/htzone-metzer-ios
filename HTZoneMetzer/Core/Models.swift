//
//  Models.swift
//  HTZoneMetzer
//

import Foundation

// MARK: - Profile

struct Profile: Codable, Hashable {
    var id: String
    var firstName: String
    var lastName: String
    var email: String
    var companyName: String
    var companyId: String
    var addressLines: [String]
    var authcode: String?

    var displayName: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? email : name
    }

    var initials: String {
        let letters = [firstName, lastName].compactMap { $0.first }
        if letters.isEmpty { return "מ" }
        return String(letters.prefix(2)).uppercased()
    }

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue else { return nil }

        self.id = id
        firstName = object["first_name"]?.stringValue ?? ""
        lastName = object["last_name"]?.stringValue ?? ""
        email = object["email"]?.stringValue ?? object["main_email"]?.stringValue ?? ""
        companyName = object["company_name"]?.stringValue ?? object["company_inserted_name"]?.stringValue ?? ""
        companyId = object["company_id"]?.stringValue ?? ""
        authcode = object["authcode"]?.stringValue

        var lines: [String] = []
        if let address = object["address"]?.stringValue?.nonEmpty { lines.append(address) }
        if let city = object["city"]?.stringValue?.nonEmpty { lines.append(city) }
        if let list = object["address_list"]?.objectValue {
            for key in list.keys.sorted(by: JSONCollections.numericOrder) {
                if let value = list[key]?.stringValue?.nonEmpty,
                   value.count > 3,
                   !value.hasPrefix("{") {
                    lines.append(value)
                }
            }
        }
        var seen = Set<String>()
        addressLines = lines.filter { seen.insert($0).inserted }
    }
}

enum ProfileStore {
    private static let key = "profile.v1"

    static func save(_ profile: Profile) {
        var safe = profile
        safe.authcode = nil
        guard let data = try? JSONEncoder().encode(safe) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Config cache

final class ConfigCache {
    private let folder: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("HTZoneMetzer", isDirectory: true)

    private var fileURL: URL? {
        folder?.appendingPathComponent("declaration.json")
    }

    func load() -> JSONValue? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    func save(_ value: JSONValue) {
        guard let folder, let fileURL else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Categories

struct CategoryNode: Identifiable, Hashable {
    let id: String
    let title: String
    let level: Int
    var children: [CategoryNode]

    static func forest(from declaration: JSONValue?) -> [CategoryNode] {
        guard let declaration,
              let categories = declaration["categoriesArr"],
              let top = categories["top_categories"] else { return [] }
        return JSONCollections.array(top).compactMap { node(from: $0, level: 1) }
    }

    static func node(from value: JSONValue, level: Int) -> CategoryNode? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue else { return nil }
        let title = object["title"]?.stringValue ?? ""
        let children = childValues(of: object).compactMap { node(from: $0, level: level + 1) }
        return CategoryNode(id: id, title: title, level: level, children: children)
    }

    private static func childValues(of object: [String: JSONValue]) -> [JSONValue] {
        for key in ["sub_categories", "categories"] {
            if let value = object[key] {
                if let array = value.arrayValue, !array.isEmpty { return array }
                if let map = value.objectValue, !map.isEmpty {
                    return map.keys.sorted(by: JSONCollections.numericOrder).compactMap { map[$0] }
                }
            }
        }
        return []
    }
}

// MARK: - Item

struct Item: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let price: Double?
    let fullPrice: Double?
    let imageURL: URL?
    let brand: String
    let category: String
    let isPriceFrom: Bool
    let textInsteadPrice: String
    let rating: Double
    let reviews: Int

    init?(json: JSONValue, mediaServer: String) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue else { return nil }
        self.id = id
        title = object["title_override"]?.stringValue?.nonEmpty
            ?? object["title"]?.stringValue
            ?? ""
        subtitle = object["sub_title_override"]?.stringValue?.nonEmpty
            ?? object["sub_title"]?.stringValue
            ?? ""
        price = object["price"]?.doubleValue
        fullPrice = object["full_price"]?.doubleValue
        brand = object["brand_title"]?.stringValue ?? ""
        category = object["item_category3"]?.stringValue?.nonEmpty
            ?? object["item_category2"]?.stringValue
            ?? object["item_category"]?.stringValue
            ?? ""
        isPriceFrom = object["is_price_starts_from"]?.boolValue ?? false
        textInsteadPrice = object["text_instead_price"]?.stringValue ?? ""
        rating = object["review_avg"]?.doubleValue ?? object["avg_rating"]?.doubleValue ?? 0
        reviews = object["reviews"]?.intValue ?? 0
        imageURL = Item.makeURL(object["img"]?.stringValue, mediaServer: mediaServer)
    }

    static func makeURL(_ raw: String?, mediaServer: String) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let base = mediaServer.hasSuffix("/") ? String(mediaServer.dropLast()) : mediaServer
        let path = raw.hasPrefix("/") ? raw : "/" + raw
        return URL(string: base + path)
    }
}

// MARK: - Cart

struct CartLine: Identifiable, Hashable {
    let id: String
    let title: String
    let price: Double
    let quantity: Int
    let imageURL: URL?

    init?(json: JSONValue, mediaServer: String) {
        guard let object = json.objectValue else { return nil }
        id = object["itemKey"]?.stringValue
            ?? object["item_key"]?.stringValue
            ?? object["id"]?.stringValue
            ?? UUID().uuidString
        title = object["item_title"]?.stringValue?.nonEmpty
            ?? object["title"]?.stringValue
            ?? ""
        price = object["price"]?.doubleValue ?? 0
        quantity = object["quantity"]?.intValue
            ?? object["total_items"]?.intValue
            ?? object["num_of_items"]?.intValue
            ?? 1
        imageURL = Item.makeURL(object["item_img"]?.stringValue ?? object["img"]?.stringValue,
                                mediaServer: mediaServer)
    }
}

struct CartSummary: Hashable {
    var lines: [CartLine]
    var total: Double
    var totalItems: Int

    init?(json: JSONValue, mediaServer: String) {
        guard let object = json.objectValue else { return nil }
        lines = JSONCollections.array(object["itemsArr"]).compactMap {
            CartLine(json: $0, mediaServer: mediaServer)
        }
        total = object["total"]?.doubleValue ?? 0
        totalItems = object["total_items"]?.intValue ?? lines.reduce(0) { $0 + $1.quantity }
    }
}

// MARK: - Orders

struct OrderSummary: Identifiable, Hashable {
    let id: String
    let status: Int
    let date: String
    let total: Double?
    let totalItems: Int

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let id = object["id"]?.stringValue ?? object["order_number"]?.stringValue else {
            return nil
        }
        self.id = id
        status = object["order_status"]?.intValue ?? object["status2"]?.intValue ?? 0
        date = object["order_date"]?.stringValue ?? ""
        total = object["total_price"]?.doubleValue
        totalItems = object["total_items"]?.intValue ?? 0
    }

    static func list(from data: JSONValue) -> [OrderSummary] {
        JSONCollections.array(data["user_orders_array"]).compactMap { OrderSummary(json: $0) }
    }
}

struct SupplierTotal: Identifiable, Hashable {
    let id: String
    let supplierId: String
    let total: Double
    let delivery: Double
}

struct OrderLine: Identifiable, Hashable {
    let id: String
    let title: String
    let quantity: Int
    let price: Double
    let supplierName: String
    let imageURL: URL?
    let orderDate: String?

    init?(json: JSONValue, mediaServer: String) {
        guard let object = json.objectValue else { return nil }
        id = object["id"]?.stringValue ?? UUID().uuidString
        title = object["item_title"]?.stringValue?.nonEmpty
            ?? object["title"]?.stringValue
            ?? ""
        quantity = object["total_items"]?.intValue ?? 1
        price = object["total_price"]?.doubleValue ?? 0
        supplierName = object["supplier_name"]?.stringValue ?? ""
        imageURL = Item.makeURL(object["item_img"]?.stringValue, mediaServer: mediaServer)
        orderDate = Format.unixDate(object["order_date"]?.intValue)
    }
}

struct OrderDetail: Hashable {
    let id: String
    let status: Int
    let total: Double?
    let toPay: Double?
    let payments: Int
    let lines: [OrderLine]
    let suppliers: [SupplierTotal]

    init?(json: JSONValue, mediaServer: String) {
        guard let object = json.objectValue else { return nil }
        let pro = object["PRO_details"]
        let summary = pro?["summary"]
        id = summary?["id"]?.stringValue ?? UUID().uuidString
        status = object["order_status"]?.intValue ?? 0
        total = object["total_order_price"]?.doubleValue
        toPay = object["total_order_price_to_pay"]?.doubleValue
        payments = object["number_of_payments"]?.intValue ?? 1
        lines = JSONCollections.array(object["itemsArr"]).compactMap {
            OrderLine(json: $0, mediaServer: mediaServer)
        }
        suppliers = JSONCollections.array(pro?["rows"]).compactMap { row in
            guard let object = row.objectValue else { return nil }
            return SupplierTotal(
                id: object["order_supplier_id"]?.stringValue ?? UUID().uuidString,
                supplierId: object["supplier_id"]?.stringValue ?? "",
                total: object["total_sum"]?.doubleValue ?? 0,
                delivery: object["total_delivery"]?.doubleValue ?? 0
            )
        }
    }
}

// MARK: - Wallet / cards

struct WalletInfo: Hashable {
    let total: Double
    let obligo: Double

    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        total = object["total"]?.doubleValue ?? 0
        obligo = object["more"]?["ObligoList"]?["ALL"]?.doubleValue ?? 0
    }
}

struct CardInfo: Identifiable, Hashable {
    let id: String
    let lastDigits: String
    let company: String
    let expiry: String
    let masked: String

    static func list(from data: JSONValue) -> [CardInfo] {
        JSONCollections.array(data["cards_arr"]).compactMap { value in
            guard let object = value.objectValue else { return nil }
            let id = object["id"]?.stringValue ?? UUID().uuidString
            return CardInfo(
                id: id,
                lastDigits: object["last_digits"]?.stringValue ?? "",
                company: object["creditCompany"]?.stringValue ?? "",
                expiry: object["cardExpiration"]?.stringValue ?? "",
                masked: object["cardMask"]?.stringValue ?? ""
            )
        }
    }
}

// MARK: - Comments

struct ItemComment: Identifiable, Hashable {
    let id: String
    let text: String
    let author: String
    let rating: Double

    static func list(from data: JSONValue) -> [ItemComment] {
        JSONCollections.array(data["commentsArr"]).compactMap { value in
            guard let object = value.objectValue else { return nil }
            let text = object["comment"]?.stringValue?.nonEmpty
                ?? object["text"]?.stringValue?.nonEmpty
                ?? object["content"]?.stringValue?.nonEmpty
                ?? ""
            guard !text.isEmpty else { return nil }
            return ItemComment(
                id: object["id"]?.stringValue ?? UUID().uuidString,
                text: text,
                author: object["user_name"]?.stringValue
                    ?? object["name"]?.stringValue
                    ?? "",
                rating: object["rating"]?.doubleValue ?? 0
            )
        }
    }
}

// MARK: - Popup (metzer credit gate)

struct PopupInput: Identifiable, Hashable {
    let id: String
    let placeholder: String

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let name = object["inputName"]?.stringValue else { return nil }
        id = name
        placeholder = object["placeHolder"]?.stringValue ?? name
    }
}

struct PopupRequest: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let buttonText: String
    let responseKey: String
    let inputs: [PopupInput]

    init?(json: JSONValue) {
        guard let object = json.objectValue,
              let responseKey = object["response_key"]?.stringValue else { return nil }
        title = object["title"]?.stringValue ?? ""
        subtitle = object["subtitle"]?.stringValue ?? ""
        buttonText = object["buttonText"]?.stringValue ?? "המשך"
        self.responseKey = responseKey
        inputs = JSONCollections.array(object["inputs"]).compactMap { PopupInput(json: $0) }
    }
}

// MARK: - Formatting

enum Format {
    static func price(_ value: Double?) -> String? {
        guard let value else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "ILS"
        formatter.currencySymbol = "₪"
        formatter.locale = Locale(identifier: "he_IL")
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value))
    }

    static func unixDate(_ value: Int?) -> String? {
        guard let value, value > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(value)))
    }
}
