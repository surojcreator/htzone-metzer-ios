//
//  Components.swift
//  HTZoneMetzer
//

import Foundation
import SwiftUI

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            case .empty:
                ZStack {
                    placeholder
                    ProgressView().tint(.white)
                }
            @unknown default:
                placeholder
            }
        }
        .background(Color.white.opacity(0.05))
        .clipped()
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PriceView: View {
    let price: Double?
    let fullPrice: Double?
    var isFrom: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let text = Format.price(price) {
                HStack(spacing: 4) {
                    if isFrom {
                        Text("החל מ־")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(text)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            if let full = fullPrice, let price, full > price, let text = Format.price(full) {
                Text(text)
                    .font(.caption)
                    .strikethrough()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct Chip: View {
    let text: String
    var selected: Bool = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.stroke, lineWidth: 1))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.9))
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct LoadingView: View {
    var text: String = "טוען…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("נסה שוב", action: retry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1))
    }
}

struct CardContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardContainer() -> some View {
        modifier(CardContainer())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                (enabled ? Theme.accent : Theme.cardStrong),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }
}
