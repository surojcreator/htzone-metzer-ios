//
//  OrdersView.swift
//  HTZoneMetzer
//

import SwiftUI

struct OrdersView: View {
    @EnvironmentObject private var app: AppState
    @State private var orders: [OrderSummary] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error {
                    ErrorBanner(message: error) {
                        Task { await load() }
                    }
                }

                if isLoading, orders.isEmpty {
                    LoadingView(text: "טוען הזמנות…")
                        .frame(height: 260)
                }

                if orders.isEmpty, !isLoading, error == nil {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "אין הזמנות",
                        message: "ההזמנות שלך יופיעו כאן לאחר רכישה."
                    )
                    .frame(height: 320)
                }

                ForEach(orders) { order in
                    NavigationLink {
                        OrderDetailView(orderId: order.id)
                    } label: {
                        orderRow(order)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("הזמנות")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
    }

    private func orderRow(_ order: OrderSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("הזמנה #\(order.id)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusBadge(text: app.statusText(order.status), color: color(for: order.status))
            }

            HStack(spacing: 14) {
                Label(order.date, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Label("\(order.totalItems) פריטים", systemImage: "bag")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let total = Format.price(order.total) {
                    Text(total)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .padding(14)
        .cardContainer()
    }

    private func color(for status: Int) -> Color {
        switch status {
        case 1: return Theme.danger
        case 2, 3: return Theme.success
        case 8, 9: return Theme.accent
        default: return Theme.gold
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            orders = try await app.orders()
        } catch {
            self.error = app.message(for: error)
        }
    }
}
