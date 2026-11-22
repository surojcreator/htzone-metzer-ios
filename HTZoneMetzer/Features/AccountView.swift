//
//  AccountView.swift
//  HTZoneMetzer
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var app: AppState
    @State private var wallet: WalletInfo?
    @State private var cards: [CardInfo] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showLogout = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let error {
                    ErrorBanner(message: error) {
                        Task { await load() }
                    }
                }

                walletCard
                cardsCard
                addressesCard
                linksCard
                logoutButton
                footer
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("חשבון")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
        .alert("התנתקות", isPresented: $showLogout) {
            Button("התנתק", role: .destructive) {
                Task { await app.logout() }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("האם להתנתק מהחשבון?")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.gold)
                Text(app.profile?.initials ?? "")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.nav)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.profile?.displayName ?? "")
                    .font(.headline)
                Text(app.profile?.email ?? "")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let company = app.profile?.companyName, !company.isEmpty {
                    Text(company)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .cardContainer()
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "ארנק")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("יתרה")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.price(wallet?.total ?? 0) ?? "₪0")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("התחייבויות")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.price(wallet?.obligo ?? 0) ?? "₪0")
                        .font(.headline)
                }
            }
        }
        .padding(16)
        .cardContainer()
    }

    private var cardsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "כרטיסים שמורים")
            if cards.isEmpty {
                Text("אין כרטיסים שמורים.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(cards) { card in
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.masked.isEmpty ? "•••• \(card.lastDigits)" : card.masked)
                                .font(.subheadline.weight(.semibold))
                            Text("\(card.company) · \(card.expiry)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .cardContainer()
    }

    private var addressesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "כתובות")
            if let lines = app.profile?.addressLines, !lines.isEmpty {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.textSecondary)
                        Text(line)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            } else {
                Text("אין כתובות שמורות.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .cardContainer()
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                OrdersView()
            } label: {
                linkRow(icon: "shippingbox.fill", title: "ההזמנות שלי")
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.stroke)

            NavigationLink {
                ContentPageView(pageId: "1", title: "אודות")
            } label: {
                linkRow(icon: "info.circle.fill", title: "אודות מצ״ר")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .cardContainer()
    }

    private func linkRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: "chevron.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private var logoutButton: some View {
        Button {
            showLogout = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("התנתקות")
            }
            .font(.headline)
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.danger.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("HTZone · מצ״ר · גרסה \(appVersion)")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text("אפליקציה עצמאית. אינה קשורה ל־HTZone או לרפאל.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            wallet = try await app.wallet()
            cards = try await app.cards()
        } catch {
            self.error = app.message(for: error)
        }
    }
}
