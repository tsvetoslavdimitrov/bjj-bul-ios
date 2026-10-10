import Foundation
import CryptoKit

/// Nonce helpers for Sign in with Apple.
enum Nonce {
    static func random(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        var result = ""
        for _ in 0..<length {
            let index = Int.random(in: 0..<characters.count, using: &generator)
            result.append(characters[index])
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
