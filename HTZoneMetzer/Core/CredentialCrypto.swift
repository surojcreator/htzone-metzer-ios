//
//  CredentialCrypto.swift
//  HTZoneMetzer
//
//  Login fields are encrypted client-side before they leave the device.
//
//  Recovered scheme (verified against api.htzone.co.il):
//    key      = PBKDF2-HMAC-SHA256(staticKey, salt, 32767, dkLen 16)
//    nonce    = 12 random bytes
//    blob     = salt(16) || nonce(12) || AES-GCM ciphertext || tag(16)
//    wire     = base64(blob)
//
//  staticKey is the value returned by
//  Java_il_co_inmanage_base_data_BaseEncryption_encryptionKey in libndkMethods.so.
//

import Foundation
import CryptoKit
import CommonCrypto
import Security

enum CredentialCrypto {
    static let staticKey = Data("1inmahtzonenage2".utf8)
    static let saltLength = 16
    static let nonceLength = 12
    static let keyLength = 16
    static let rounds = 32_767

    enum CryptoError: LocalizedError {
        case random
        case pbkdf2(Int32)

        var errorDescription: String? {
            switch self {
            case .random: return "יצירת מספר אקראי נכשלה"
            case .pbkdf2(let status): return "גזירת מפתח נכשלה (\(status))"
            }
        }
    }

    static func encrypt(_ plaintext: String) throws -> String {
        var salt = Data(count: saltLength)
        var nonce = Data(count: nonceLength)

        let saltStatus = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!)
        }
        guard saltStatus == errSecSuccess else { throw CryptoError.random }

        let nonceStatus = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, nonceLength, $0.baseAddress!)
        }
        guard nonceStatus == errSecSuccess else { throw CryptoError.random }

        let key = try pbkdf2(password: staticKey, salt: salt, rounds: rounds, length: keyLength)
        let nonceBox = try AES.GCM.Nonce(data: nonce)
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: SymmetricKey(data: key), nonce: nonceBox)

        var blob = Data()
        blob.append(salt)
        blob.append(nonce)
        blob.append(sealed.ciphertext)
        blob.append(sealed.tag)
        return blob.base64EncodedString()
    }

    static func pbkdf2(password: Data, salt: Data, rounds: Int, length: Int) throws -> Data {
        var derived = Data(count: length)
        let status: Int32 = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.pbkdf2(status) }
        return derived
    }
}
