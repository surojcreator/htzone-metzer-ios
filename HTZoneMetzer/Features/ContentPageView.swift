//
//  ContentPageView.swift
//  HTZoneMetzer
//

import SwiftUI
import WebKit

struct ContentPageView: View {
    let pageId: String
    let title: String

    @EnvironmentObject private var app: AppState
    @State private var html: String?
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let html, !html.isEmpty {
                HTMLView(html: html)
                    .background(Theme.nav.ignoresSafeArea())
            } else if let error {
                ErrorBanner(message: error) {
                    Task { await load() }
                }
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                LoadingView(text: "טוען תוכן…")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await load()
        }
    }

    @MainActor
    private func load() async {
        do {
            let data = try await app.contentPage(id: pageId)
            let right = data["right_content"]?.stringValue ?? ""
            let left = data["left_content"]?.stringValue ?? ""
            html = [right, left].filter { !$0.isEmpty }.joined(separator: "<hr/>")
            if html?.isEmpty ?? true {
                error = "אין תוכן להצגה"
            }
        } catch {
            self.error = app.message(for: error)
        }
    }
}

struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = """
        <!doctype html>
        <html dir="rtl" lang="he">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root { color-scheme: dark; }
        body {
            background: #021953; color: #ffffff;
            font-family: -apple-system, "Heebo", sans-serif;
            font-size: 16px; line-height: 1.65;
            padding: 16px; margin: 0;
            -webkit-text-size-adjust: 100%;
        }
        img, video, iframe { max-width: 100%; height: auto; }
        a { color: #5b8cff; }
        table { width: 100%; border-collapse: collapse; }
        td, th { padding: 6px; border-bottom: 1px solid rgba(255,255,255,0.12); }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.12); margin: 20px 0; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(document, baseURL: nil)
    }
}
