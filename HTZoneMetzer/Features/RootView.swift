//
//  RootView.swift
//  HTZoneMetzer
//

import Foundation
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch app.phase {
            case .loading:
                SplashView()
            case .loggedOut:
                LoginView()
            case .loggedIn:
                MainTabView()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
        .task { await app.bootstrap() }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.gold)
                    .frame(width: 92, height: 92)
                Text("מצ״ר")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.nav)
            }
            Text("HTZone · מצ״ר")
                .font(.headline)
                .foregroundStyle(.white)
            ProgressView()
                .tint(.white)
                .padding(.top, 8)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var app: AppState

    @State private var email = ""
    @State private var password = ""
    @State private var remember = true
    @State private var tenant: Tenant = .metzer
    @State private var showPassword = false
    @State private var prefilled = false

    private var isValid: Bool {
        email.contains("@") && password.count >= 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                VStack(spacing: 14) {
                    TextField("דואר אלקטרוני", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 1)
                        )

                    HStack {
                        Group {
                            if showPassword {
                                TextField("סיסמה", text: $password)
                            } else {
                                SecureField("סיסמה", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1)
                    )

                    Picker("סביבה", selection: $tenant) {
                        ForEach(Tenant.allCases) { tenant in
                            Text(tenant.title).tag(tenant)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("שמור פרטי התחברות ב־Keychain", isOn: $remember)
                    .font(.footnote)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.textSecondary)

                if let message = app.errorMessage {
                    ErrorBanner(message: message)
                }

                Button {
                    Task {
                        await app.login(email: email, password: password, remember: remember, tenant: tenant)
                    }
                } label: {
                    HStack {
                        if app.isBusy {
                            ProgressView().tint(.white)
                        }
                        Text(app.isBusy ? "מתחבר…" : "התחברות")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: isValid && !app.isBusy))
                .disabled(!isValid || app.isBusy)

                Text("הסיסמה מוצפנת ב־AES‑GCM לפני השליחה ואינה נשמרת אלא אם בחרת לשמור אותה ב־Keychain.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            guard !prefilled else { return }
            prefilled = true
            if let raw = UserDefaults.standard.string(forKey: "tenant"),
               let saved = Tenant(rawValue: raw) {
                tenant = saved
            }
            if let saved = Keychain.load() {
                email = saved.email
                password = saved.password
            } else if let last = UserDefaults.standard.string(forKey: "lastEmail") {
                email = last
                password = ""
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.gold)
                    .frame(width: 88, height: 88)
                Text("מצ״ר")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.nav)
            }
            Text("HTZone · מצ״ר")
                .font(.title2.weight(.bold))
            Text("אפליקציה חלופית לחשבון שלך")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 20)
    }
}
