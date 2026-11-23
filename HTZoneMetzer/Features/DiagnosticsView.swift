//
//  DiagnosticsView.swift
//  HTZoneMetzer
//

import Foundation
import SwiftUI

/// Runs every read-only endpoint the client uses and reports pass/fail with
/// latency, so API health can be checked on the device without a debugger.
struct DiagnosticsView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var log = APILog.shared

    @State private var rows: [Row] = []
    @State private var isRunning = false

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let ok: Bool
        let ms: Int
    }

    private struct Check {
        let name: String
        let run: () async throws -> String
    }

    private var passed: Int { rows.filter(\.ok).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("בודק את נקודות הקצה שהאפליקציה משתמשת בהן. הבדיקות קוראות בלבד ואינן משנות נתונים.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await runAll() }
                } label: {
                    HStack {
                        if isRunning { ProgressView().tint(.white) }
                        Text(isRunning ? "בודק…" : "הרץ בדיקה")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !isRunning))
                .disabled(isRunning)

                if !rows.isEmpty {
                    Text("\(passed) מתוך \(rows.count) עברו")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(passed == rows.count ? Theme.success : Theme.gold)
                }

                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(row.ok ? Theme.success : Theme.danger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text("\(row.ms) ms")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .cardContainer()
                }

                if !log.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "כשלים אחרונים", actionTitle: "נקה") {
                            log.clear()
                        }
                        ForEach(log.entries, id: \.self) { entry in
                            Text(entry)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .cardContainer()
                        }
                    }
                }

                if !rows.isEmpty, !isRunning {
                    Text("פעולות כתיבה (סל, מועדפים, כתובות, הזמנות) אינן נבדקות כדי לא לשנות נתונים.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("בדיקת API")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        rows = []
        defer { isRunning = false }

        for check in checks() {
            let started = Date()
            do {
                let detail = try await check.run()
                rows.append(Row(name: check.name,
                                detail: detail,
                                ok: true,
                                ms: Int(Date().timeIntervalSince(started) * 1000)))
            } catch {
                rows.append(Row(name: check.name,
                                detail: app.message(for: error),
                                ok: false,
                                ms: Int(Date().timeIntervalSince(started) * 1000)))
            }
        }
    }

    private func checks() -> [Check] {
        let firstCategory = app.categories.first?.id
        var list: [Check] = []

        list.append(Check(name: "generalDeclaration") {
            let data = try await app.api.declaration()
            return "\(data.objectValue?.count ?? 0) מפתחות"
        })

        list.append(Check(name: "getCategory") {
            guard let id = firstCategory else { throw Self.missingCategory }
            let data = try await app.api.category(id: id)
            return "\(data.objectValue?.count ?? 0) מפתחות"
        })

        list.append(Check(name: "getItems") {
            let payload = try await Self.firstItemsPage(app.api, categoryId: firstCategory)
            return "\(JSONCollections.array(payload["itemsArr"]).count) פריטים"
        })

        list.append(Check(name: "getItem") {
            let payload = try await Self.firstItemsPage(app.api, categoryId: firstCategory)
            guard let itemId = JSONCollections.array(payload["itemsArr"]).first?["id"]?.stringValue else {
                throw APIError(code: nil, message: "אין פריטים")
            }
            let detail = try await app.api.item(itemId: itemId)
            return detail["title"]?.stringValue ?? "פריט \(itemId)"
        })

        list.append(Check(name: "searchQuery") {
            let data = try await app.api.search("sam")
            return "\(JSONCollections.array(data["res"]).count) תוצאות"
        })

        list.append(Check(name: "getPopularSearches") {
            let data = try await app.api.popularSearches()
            return "\(JSONCollections.array(data).count) מונחים"
        })

        list.append(Check(name: "getContentPage") {
            let data = try await app.api.contentPage(id: "1")
            return "\(data.objectValue?.count ?? 0) מפתחות"
        })

        list.append(Check(name: "getUserFavorites") {
            let data = try await app.api.favorites()
            return "\(JSONCollections.array(data["favorites_itemsArr"]).count) מועדפים"
        })

        list.append(Check(name: "getCart") {
            let data = try await app.api.cart()
            return "\(JSONCollections.array(data["itemsArr"]).count) פריטים"
        })

        list.append(Check(name: "getUserWallet") {
            let data = try await app.api.wallet()
            return data["total"]?.stringValue ?? "—"
        })

        list.append(Check(name: "getUserCards") {
            let data = try await app.api.cards()
            return "\(JSONCollections.array(data).count) כרטיסים"
        })

        list.append(Check(name: "getUserOrders") {
            let data = try await app.api.orders()
            return "\(JSONCollections.array(data).count) הזמנות"
        })

        list.append(Check(name: "checkProState") {
            _ = try await app.api.proState()
            return "ok"
        })

        list.append(Check(name: "getCompanies") {
            let data = try await app.api.companies()
            return "\(JSONCollections.array(data).count) חברות"
        })

        list.append(Check(name: "getCities") {
            let data = try await app.api.cities()
            return "\(JSONCollections.array(data["citiesArr"]).count) ערים"
        })

        list.append(Check(name: "getChitaboxList") {
            _ = try await app.api.chitaboxList()
            return "ok"
        })

        list.append(Check(name: "getBoxitAreas") {
            let data = try await app.api.boxitAreas()
            return "\(JSONCollections.array(data["areas"]).count) אזורים"
        })

        list.append(Check(name: "getHostUrl") {
            let data = try await app.api.hostURL()
            return data.stringValue ?? "ok"
        })

        return list
    }

    private static let missingCategory = APIError(code: nil, message: "אין קטגוריות טעונות")

    private static func firstItemsPage(_ api: APIClient, categoryId: String?) async throws -> JSONValue {
        guard let categoryId else { throw missingCategory }
        let data = try await api.items(categoryId: categoryId, page: 1)
        return data[categoryId] ?? data.objectValue?.values.first ?? .null
    }
}
