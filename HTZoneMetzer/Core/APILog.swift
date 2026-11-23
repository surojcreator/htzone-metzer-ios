//
//  APILog.swift
//  HTZoneMetzer
//

import Foundation
import Combine

/// Bounded, on-device record of failed responses so a user can report exactly
/// which call produced "cannot read the server response".
final class APILog: ObservableObject {
    static let shared = APILog()

    @Published private(set) var entries: [String] = []

    private let limit = 40

    private init() {}

    func record(_ entry: String) {
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.limit {
                self.entries.removeLast(self.entries.count - self.limit)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries = []
        }
    }

    /// Short, single-line preview of a body for diagnostics.
    static func preview(_ data: Data, limit: Int = 80) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return text
    }
}
