//
//  OrderDetailView.swift
//  HTZoneMetzer
//

import SwiftUI

struct OrderDetailView: View {
    let orderId: String

    @EnvironmentObject private var app: AppState
    @State private var detail: OrderDetail?
    @State private var isLoading = false
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error {
                    ErrorBanner(message: error) {
                        Task { await load() }
                    }
                }

                if isLoading, detail == nil {
                    LoadingView(text: "טוען הזמנה…")
                        .frame(height: 260)
                }

                if let detail {
                    summary(detail)
                    itemsSection(detail)
                    if !detail.suppliers.isEmpty {
                        suppliersSection(detail)
                    }
                    Text("פרטי כרטיס האשראי אינם מוצגים באפליקציה.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("הזמנה #\(orderId)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
    }

    private func summary(_ detail: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("סטטוס")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusBadge(text: app.statusText(detail.status), color: Theme.accent)
            }

            HStack {
                Text("סה״כ")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Format.price(detail.total) ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.gold)
            }

            if let toPay = detail.toPay, let total = detail.total, abs(toPay - total) > 0.01 {
                HStack {
                    Text("לתשלום")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(Format.price(toPay) ?? "—")
                        .font(.headline)
                }
            }

            HStack {
                Text("תשלומים")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(detail.payments)")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .cardContainer()
    }

    private func itemsSection(_ detail: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "פריטים")
            ForEach(detail.lines) { line in
                HStack(spacing: 12) {
                    RemoteImage(url: line.imageURL)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if let supplier = line.supplierName.nonEmpty {
                                Text(supplier)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Text("×\(line.quantity)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    Text(Format.price(line.price) ?? "—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
                .padding(12)
                .cardContainer()
            }
        }
    }

    private func suppliersSection(_ detail: OrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "ספקים")
            ForEach(detail.suppliers) { supplier in
                HStack {
                    Text("ספק \(supplier.supplierId)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if supplier.delivery > 0, let delivery = Format.price(supplier.delivery) {
                        Text("משלוח \(delivery)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(Format.price(supplier.total) ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
                .padding(12)
                .cardContainer()
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            detail = try await app.orderDetail(id: orderId)
        } catch {
            self.error = app.message(for: error)
        }
    }
}
