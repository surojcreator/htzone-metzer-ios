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
        var collected: [JSONValue] = []
        var seen = Set<String>()
        for key in ["sub_categories", "categories"] {
            guard let value = object[key] else { continue }
            let values: [JSONValue]
            if let array = value.arrayValue {
                values = array
            } else if let map = value.objectValue {
                values = map.keys.sorted(by: JSONCollections.numericOrder).compactMap { map[$0] }
            } else {
                values = []
            }
            for entry in values {
                let id = entry["id"]?.stringValue ?? UUID().uuidString
                guard seen.insert(id).inserted else { continue }
                collected.append(entry)
            }
        }
        return collected
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
    /// The product exposes selectable variants (the API's `collected` flag).
    let isCollected: Bool
    /// Number of values in the widest variant dimension (0 when there are none).
    let optionCount: Int

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
        isCollected = (object["collected"]?.boolValue ?? false)
            || !((object["collectedIds"]?.isNull) ?? true)
        optionCount = Item.featureOptionCount(object["features"])
        imageURL = Item.makeURL(object["img"]?.stringValue, mediaServer: mediaServer)
    }

    /// `features` arrives as `{groupId: [valueId, ...]}` (or a keyed map); the
    /// largest group is how many selectable options the card should advertise.
    private static func featureOptionCount(_ value: JSONValue?) -> Int {
        guard let value else { return 0 }
        if let map = value.objectValue {
            var best = 0
            for entry in map.values {
                if let array = entry.arrayValue {
                    best = max(best, array.count)
                } else if let object = entry.objectValue {
                    best = max(best, object.count)
                } else if let number = entry.intValue {
                    best = max(best, number)
                }
            }
            return best
        }
        return value.arrayValue?.count ?? 0
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

// MARK: - Full item detail

struct FeatureGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let values: [String]
}

/// One selectable value of a variant dimension (for example a colour).
struct VariantOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// A selectable variant dimension.
///
/// The API only guarantees one such dimension: the "collected" one used by
/// `items_stock`. Every other feature group stays a plain specification.
struct VariantGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let options: [VariantOption]
}

/// One purchasable row of a collected product, as reported by `items_stock`.
struct StockVariant: Identifiable, Hashable {
    let id: String
    let collectedId: String
    let stock: Int
    let price: Double?
    let fullPrice: Double?
}

/// Intermediate parse result before a group is classified as spec or variant.
private struct ParsedFeatureGroup {
    let id: String
    let title: String
    let options: [VariantOption]
}

struct DeliveryOption: Identifiable, Hashable {
    let id: String
    let title: String
    let price: Double
}

struct ItemDetail: Hashable {
    let id: String
    let title: String
    let subtitle: String
    let brief: String
    let contentHTML: String
    let images: [URL]
    let features: [FeatureGroup]
    let variantGroups: [VariantGroup]
    let stockVariants: [StockVariant]
    let defaultCollectedId: String?
    let isCollected: Bool
    let productType: String
    let delivery: [DeliveryOption]
    let warranty: String
    let supplierId: String
    let inStock: Bool
    let outOfStockMessage: String
    let itemURL: URL?
    let price: Double?
    let fullPrice: Double?

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
        brief = object["brief"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let content = object["content"]?.stringValue ?? ""
        let content1 = object["content1"]?.stringValue ?? ""
        contentHTML = [content, content1]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "<hr/>")

        images = ItemDetail.parseImages(object["mediaGroupsArr"], mediaServer: mediaServer)

        let collectedFlag = object["collected"]?.boolValue ?? false
        let hasCollectedIds = !((object["collectedIds"]?.isNull) ?? true)
        let collected = collectedFlag || hasCollectedIds
        isCollected = collected
        productType = object["product_type"]?.stringValue
            ?? object["type_id"]?.stringValue
            ?? ""

        let priceObject = ItemDetail.priceObject(object["priceArr"])
        let stocks = ItemDetail.parseStock(object["items_stock"])
        stockVariants = stocks

        // `collected_id` is the variant the server is currently pricing; "0"
        // is the sentinel used by products that have no variant dimension.
        var resolvedCollectedId: String?
        if let explicit = priceObject?["collected_id"]?.stringValue?.nonEmpty,
           explicit != "0" {
            resolvedCollectedId = explicit
        } else if let first = stocks.first, first.collectedId != "0" {
            resolvedCollectedId = first.collectedId
        }
        defaultCollectedId = resolvedCollectedId

        let parsedGroups = ItemDetail.parseFeatureGroups(extra: object["extra_features"],
                                                         featureIds: object["features"])
        let specs = parsedGroups.map { group in
            FeatureGroup(id: group.id, title: group.title, values: group.options.map(\.title))
        }

        var variant: VariantGroup?
        if collected, stocks.count > 1 {
            let candidates = parsedGroups.filter { $0.options.count > 1 }
            let aligned = candidates.filter { $0.options.count == stocks.count }
            func isColour(_ group: ParsedFeatureGroup) -> Bool {
                let title = group.title.lowercased()
                return title.contains("צבע") || title.contains("color") || title.contains("colour")
            }
            let chosen = aligned.first(where: isColour)
                ?? aligned.first
                ?? candidates.first(where: isColour)
                ?? candidates.max { $0.options.count < $1.options.count }
            if let chosen {
                variant = VariantGroup(id: chosen.id, title: chosen.title, options: chosen.options)
            }
        }
        variantGroups = variant.map { [$0] } ?? []
        features = specs.filter { $0.id != (variant?.id ?? "") }

        delivery = ItemDetail.parseDelivery(object["delivery_arr"])
        warranty = object["warranty"]?.stringValue ?? ""
        supplierId = object["supplier_id"]?.stringValue ?? ""
        inStock = !(object["stock_empty"]?.boolValue ?? false)
        outOfStockMessage = object["out_of_stock_msg"]?.stringValue ?? ""
        itemURL = object["itemUrl"]?.stringValue.flatMap { URL(string: $0) }

        let selectedPriceObject = ItemDetail.priceObject(object["priceArr"],
                                                         collectedId: resolvedCollectedId)
        let pricedVariant = resolvedCollectedId.flatMap { id in
            stocks.first { $0.collectedId == id }
        }
        price = pricedVariant?.price
            ?? selectedPriceObject?["price"]?.doubleValue
            ?? object["price"]?.doubleValue
        fullPrice = pricedVariant?.fullPrice
            ?? selectedPriceObject?["full_price"]?.doubleValue
            ?? object["full_price"]?.doubleValue
    }

    // MARK: - Variant helpers

    /// Index the server is currently pricing the product at.
    var defaultVariantIndex: Int {
        guard let defaultCollectedId,
              let index = stockVariants.firstIndex(where: { $0.collectedId == defaultCollectedId }) else {
            return 0
        }
        return index
    }

    /// `collectedId` for an option index, aligned with `items_stock` order.
    func collectedId(at index: Int) -> String? {
        guard stockVariants.indices.contains(index) else { return nil }
        return stockVariants[index].collectedId
    }

    func stockCount(at index: Int) -> Int? {
        guard stockVariants.indices.contains(index) else { return nil }
        return stockVariants[index].stock
    }

    func variantPrice(at index: Int) -> Double? {
        guard stockVariants.indices.contains(index) else { return nil }
        return stockVariants[index].price
    }

    var hasVariants: Bool { !variantGroups.isEmpty }

    private static func parseImages(_ value: JSONValue?, mediaServer: String) -> [URL] {
        var urls: [URL] = []
        var main: URL?
        for entry in JSONCollections.array(value) {
            guard let object = entry.objectValue else { continue }
            let raw = object["path"]?.stringValue ?? object["img"]?.stringValue
            guard let url = Item.makeURL(raw, mediaServer: mediaServer) else { continue }
            if object["main_picture"]?.stringValue == "1" {
                main = url
            } else {
                urls.append(url)
            }
        }
        if let main { urls.insert(main, at: 0) }
        return urls
    }

    /// `extra_features` carries the human labels; `features` carries the canonical
    /// option order per group (`{featureId: [featureValueId, ...]}`).
    private static func parseFeatureGroups(extra: JSONValue?,
                                           featureIds: JSONValue?) -> [ParsedFeatureGroup] {
        let featureMap = featureIds?.objectValue ?? [:]
        guard let extraMap = extra?.objectValue else { return [] }

        var groups: [ParsedFeatureGroup] = []
        for key in extraMap.keys.sorted(by: JSONCollections.numericOrder) {
            guard let entry = extraMap[key]?.objectValue else { continue }
            let title = entry["show_title"]?.stringValue?.nonEmpty
                ?? entry["title"]?.stringValue?.nonEmpty
                ?? ""
            guard !title.isEmpty else { continue }
            let groupId = entry["id"]?.stringValue?.nonEmpty ?? key

            // Stable (id, label) pairs in declaration order.
            var labelled: [(id: String, title: String)] = []
            var seen = Set<String>()
            let rawValues = entry["values"]
            if let valueMap = rawValues?.objectValue {
                for valueKey in valueMap.keys.sorted(by: JSONCollections.numericOrder) {
                    guard let value = valueMap[valueKey]?.objectValue else { continue }
                    ItemDetail.appendLabel(value, fallbackId: valueKey, into: &labelled, seen: &seen)
                }
            } else if let valueArray = rawValues?.arrayValue {
                for (index, value) in valueArray.enumerated() {
                    guard let object = value.objectValue else { continue }
                    let fallback = object["feature_value_id"]?.stringValue
                        ?? object["id"]?.stringValue
                        ?? String(index)
                    ItemDetail.appendLabel(object, fallbackId: fallback, into: &labelled, seen: &seen)
                }
            }
            guard !labelled.isEmpty else { continue }

            var byId: [String: String] = [:]
            for item in labelled { byId[item.id] = item.title }

            // Respect the published order when it covers our labels; otherwise
            // fall back to declaration order.
            var optionIds: [String] = []
            if let declared = featureMap[groupId]?.arrayValue {
                for value in declared {
                    guard let optionId = value.stringValue,
                          byId[optionId] != nil,
                          !optionIds.contains(optionId) else { continue }
                    optionIds.append(optionId)
                }
            }
            if optionIds.isEmpty {
                optionIds = labelled.map { $0.id }
            }

            let options = optionIds.map {
                VariantOption(id: $0, title: byId[$0] ?? $0)
            }
            groups.append(ParsedFeatureGroup(id: groupId, title: title, options: options))
        }
        return groups
    }

    private static func appendLabel(_ value: [String: JSONValue],
                                    fallbackId: String,
                                    into labelled: inout [(id: String, title: String)],
                                    seen: inout Set<String>) {
        let label = value["value"]?.stringValue?.nonEmpty
            ?? value["title"]?.stringValue?.nonEmpty
            ?? value["name"]?.stringValue?.nonEmpty
        guard let label else { return }
        let optionId = value["feature_value_id"]?.stringValue?.nonEmpty ?? fallbackId
        guard seen.insert(optionId).inserted else { return }
        labelled.append((id: optionId, title: label))
    }

    /// `items_stock` is keyed by a numeric row id; the numeric key order matches
    /// the order of the variant dimension's options.
    private static func parseStock(_ value: JSONValue?) -> [StockVariant] {
        JSONCollections.array(value).compactMap { entry in
            guard let object = entry.objectValue else { return nil }
            let collectedId = object["item_collected_id"]?.stringValue?.nonEmpty
                ?? object["collected_id"]?.stringValue?.nonEmpty
            guard let collectedId else { return nil }
            let stock = object["total_active_items"]?.intValue
                ?? object["stock"]?.intValue
                ?? 0
            let id = object["item_collected_id"]?.stringValue
                ?? object["id"]?.stringValue
                ?? collectedId
            return StockVariant(
                id: id,
                collectedId: collectedId,
                stock: stock,
                price: object["price"]?.doubleValue
                    ?? object["sale_price"]?.doubleValue
                    ?? object["final_price"]?.doubleValue,
                fullPrice: object["full_price"]?.doubleValue
            )
        }
    }

    private static func priceObject(_ value: JSONValue?,
                                    collectedId: String? = nil) -> [String: JSONValue]? {
        if let object = value?.objectValue { return object }
        let rows = JSONCollections.array(value).compactMap { $0.objectValue }
        if let collectedId,
           let match = rows.first(where: { $0["collected_id"]?.stringValue == collectedId }) {
            return match
        }
        return rows.first
    }

    private static func parseDelivery(_ value: JSONValue?) -> [DeliveryOption] {
        guard let items = value?["delivery_items"]?.objectValue else { return [] }
        return items.keys.sorted(by: JSONCollections.numericOrder).compactMap { key in
            guard let object = items[key]?.objectValue,
                  let title = object["title"]?.stringValue?.nonEmpty else { return nil }
            return DeliveryOption(id: key, title: title, price: object["sum"]?.doubleValue ?? 0)
        }
    }
}

// MARK: - Category metadata

struct PromoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let brand: String

    static func list(from value: JSONValue?) -> [PromoItem] {
        JSONCollections.array(value).compactMap { entry in
            guard let object = entry.objectValue,
                  let title = object["title"]?.stringValue?.nonEmpty else { return nil }
            let brand = object["brand_title"]?.stringValue ?? ""
            return PromoItem(
                id: object["id"]?.stringValue ?? "\(brand)-\(title)",
                title: title,
                subtitle: object["sub_title"]?.stringValue ?? "",
                brand: brand
            )
        }
    }
}

struct CategoryInfo: Hashable {
    let id: String
    let title: String
    let children: [CategoryNode]
    let total: Int?
    let promos: [PromoItem]

    init(id: String, title: String, children: [CategoryNode], total: Int?, promos: [PromoItem]) {
        self.id = id
        self.title = title
        self.children = children
        self.total = total
        self.promos = promos
    }

    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        id = object["id"]?.stringValue ?? ""
        title = object["title"]?.stringValue ?? ""
        children = JSONCollections.array(object["connected_categories"]).compactMap {
            CategoryNode.node(from: $0, level: 2)
        }
        total = object["total_items"]?.intValue
        promos = PromoItem.list(from: object["connected_items"])
    }
}

// MARK: - Home banners

struct Banner: Identifiable, Hashable {
    let id: String
    let title: String
    let imageURL: URL?
    let categoryId: String?
    let webURL: URL?

    static func list(from declaration: JSONValue?, mediaServer: String) -> [Banner] {
        guard let host = declaration?["home_page_bannersArr"] else { return [] }
        var output: [Banner] = []

        for entry in JSONCollections.array(host["tv_banners"]) {
            guard let object = entry.objectValue else { continue }
            let id = object["id"]?.stringValue ?? UUID().uuidString
            let title = object["banner_alt"]?.stringValue?.nonEmpty
                ?? object["name"]?.stringValue
                ?? ""
            let raw = object["mobile_img"]?.stringValue?.nonEmpty
                ?? object["banner_img"]?.stringValue
            let web = object["href"]?.stringValue.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
            output.append(Banner(
                id: "tv-\(id)",
                title: title,
                imageURL: Item.makeURL(raw, mediaServer: mediaServer),
                categoryId: object["category_id"]?.stringValue,
                webURL: web
            ))
        }

        for entry in JSONCollections.array(host["elipses"]) {
            guard let object = entry.objectValue else { continue }
            let id = object["id"]?.stringValue ?? UUID().uuidString
            let raw = object["mobile_img"]?.stringValue?.nonEmpty
                ?? object["image"]?.stringValue
            output.append(Banner(
                id: "el-\(id)",
                title: object["text"]?.stringValue ?? "",
                imageURL: Item.makeURL(raw, mediaServer: mediaServer),
                categoryId: object["category_id"]?.stringValue ?? categoryId(from: object["href"]?.stringValue),
                webURL: nil
            ))
        }
        return output.filter { $0.imageURL != nil }
    }

    private static func categoryId(from href: String?) -> String? {
        guard let href else { return nil }
        for part in href.split(separator: "/").reversed() where part.allSatisfy({ $0.isNumber }) {
            return String(part)
        }
        return nil
    }
}

// MARK: - Paged items

struct ItemsPage {
    let items: [Item]
    let total: Int?
    let rawCount: Int
    let pageSize: Int
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
