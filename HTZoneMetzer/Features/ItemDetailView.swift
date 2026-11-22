//
//  ItemDetailView.swift
//  HTZoneMetzer
//

import Foundation
import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @EnvironmentObject private var app: AppState
    @State private var quantity = 1
    @State private var comments: [ItemComment] = []
    @State private var related: [Item] = []
    @State private var popup: PopupRequest?
    @State private var isAdding = false
    @State private var error: String?
    @State private var toast: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RemoteImage(url: item.imageURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                header
                priceBox
                addBox

                if let error {
                    ErrorBanner(message: error)
                }

                if !comments.isEmpty {
                    commentsSection
                }

                if !related.isEmpty {
                    relatedSection
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("מוצר")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $popup) { request in
            MetzerCreditSheet(popup: request) { values in
                try await app.submitPopup(request, values: values)
                await MainActor.run { showToast("הפרטים נשלחו") }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.success.opacity(0.92), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            comments = (try? await app.comments(itemId: item.id)) ?? []
            related = (try? await app.related(itemId: item.id)) ?? []
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = item.subtitle.nonEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let brand = item.brand.nonEmpty {
                    StatusBadge(text: brand, color: Theme.accent)
                }
                if let category = item.category.nonEmpty {
                    StatusBadge(text: category, color: Theme.gold)
                }
                if item.rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                        Text(String(format: "%.1f", item.rating))
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.gold)
                }
            }
            .padding(.top, 2)
        }
    }

    private var priceBox: some View {
        HStack(alignment: .center) {
            if let text = item.textInsteadPrice.nonEmpty {
                Text(text)
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            } else {
                PriceView(price: item.price, fullPrice: item.fullPrice, isFrom: item.isPriceFrom)
            }
            Spacer()
            if item.reviews > 0 {
                Text("\(item.reviews) ביקורות")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .cardContainer()
    }

    private var addBox: some View {
        VStack(spacing: 12) {
            HStack {
                Text("כמות")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Stepper(value: $quantity, in: 1...20) {
                    Text("\(quantity)")
                        .font(.headline)
                        .frame(minWidth: 24)
                }
                .fixedSize()
            }

            Button {
                Task { await addToCart() }
            } label: {
                HStack {
                    if isAdding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "cart.badge.plus")
                    }
                    Text(isAdding ? "מוסיף…" : "הוסף לסל")
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !isAdding))
            .disabled(isAdding)
        }
        .padding(16)
        .cardContainer()
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "ביקורות")
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(comment.author.isEmpty ? "לקוח" : comment.author)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if comment.rating > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.caption2)
                                Text(String(format: "%.0f", comment.rating)).font(.caption2)
                            }
                            .foregroundStyle(Theme.gold)
                        }
                    }
                    Text(comment.text)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .cardContainer()
            }
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "מוצרים נוספים")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(related) { other in
                        NavigationLink {
                            ItemDetailView(item: other)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: other.imageURL)
                                    .frame(width: 140, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(other.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(width: 140, alignment: .leading)
                                if let text = Format.price(other.price) {
                                    Text(text)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.gold)
                                }
                            }
                            .padding(8)
                            .cardContainer()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    @MainActor
    private func addToCart() async {
        isAdding = true
        error = nil
        defer { isAdding = false }

        do {
            if let request = try await app.addToCart(itemId: item.id, quantity: quantity) {
                popup = request
            } else {
                showToast("נוסף לסל")
            }
        } catch {
            self.error = app.message(for: error)
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}

struct MetzerCreditSheet: View {
    let popup: PopupRequest
    let onSubmit: ([String: String]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(popup.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if !popup.subtitle.isEmpty {
                        Text(popup.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    ForEach(popup.inputs) { input in
                        TextField(input.placeholder, text: binding(for: input.id))
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.stroke, lineWidth: 1)
                            )
                    }

                    if let error {
                        ErrorBanner(message: error)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isBusy { ProgressView().tint(.white) }
                            Text(isBusy ? "שולח…" : popup.buttonText)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !isBusy))
                    .disabled(isBusy)
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("אימות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    @MainActor
    private func submit() async {
        isBusy = true
        error = nil
        defer { isBusy = false }

        do {
            try await onSubmit(values)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}
