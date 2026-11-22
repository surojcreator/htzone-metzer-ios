//
//  CartView.swift
//  HTZoneMetzer
//

import SwiftUI

struct CartView: View {
    @EnvironmentObject private var app: AppState
    @State private var cart: CartSummary?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showCheckout = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let error {
                    ErrorBanner(message: error) {
                        Task { await load() }
                    }
                }

                if isLoading, cart == nil {
                    LoadingView(text: "טוען סל…")
                        .frame(height: 240)
                }

                if let cart {
                    if cart.lines.isEmpty {
                        EmptyStateView(
                            icon: "cart",
                            title: "הסל ריק",
                            message: "הוסף מוצרים מהקטלוג או מהחיפוש."
                        )
                        .frame(height: 320)
                    } else {
                        ForEach(cart.lines) { line in
                            cartRow(line)
                        }
                        totalCard(cart)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("סל")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
        .alert("רכישה במצ״ר", isPresented: $showCheckout) {
            Button("הבנתי", role: .cancel) {}
        } message: {
            Text("השלמת הזמנה מחייבת כרטיס מצ״ר רשום ומאומת. האפליקציה מציגה את הסל ואינה מבצעת תשלום.")
        }
    }

    private func cartRow(_ line: CartLine) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: line.imageURL)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("כמות \(line.quantity)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let price = Format.price(line.price) {
                        Text(price)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }

            Spacer()

            Button {
                Task { await remove(line) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.danger)
                    .padding(8)
            }
        }
        .padding(12)
        .cardContainer()
    }

    private func totalCard(_ cart: CartSummary) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("סה״כ")
                    .font(.headline)
                Spacer()
                Text(Format.price(cart.total) ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.gold)
            }

            Button {
                showCheckout = true
            } label: {
                Text("מעבר לתשלום")
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !cart.lines.isEmpty))
        }
        .padding(16)
        .cardContainer()
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            cart = try await app.cart()
            await app.refreshCart()
        } catch {
            self.error = app.message(for: error)
        }
    }

    @MainActor
    private func remove(_ line: CartLine) async {
        do {
            try await app.removeFromCart(itemKey: line.id)
            await load()
        } catch {
            self.error = app.message(for: error)
        }
    }
}
