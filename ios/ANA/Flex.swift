import Foundation
import CryptoKit
import Security

/// FLEX security on the iPhone: this phone's own signing key (P-256, made once, kept in the Keychain on this
/// device only), signatures on every ledger entry, and sha256. Public keys travel as base64 X.509
/// (SubjectPublicKeyInfo) and signatures as base64 DER: the same forms the Android app (Flex.java) uses,
/// so an iPhone and an Android check each other's entries.
enum Flex {
    private static let service = "ana.flex.sign", account = "p256"
    private static var cached: P256.Signing.PrivateKey?

    private static func key() -> P256.Signing.PrivateKey? {
        if let k = cached { return k }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
           let k = try? P256.Signing.PrivateKey(rawRepresentation: d) {
            cached = k
            return k
        }
        let k = P256.Signing.PrivateKey()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: k.rawRepresentation,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let st = SecItemAdd(add as CFDictionary, nil)
        if st != errSecSuccess { return nil }
        cached = k
        return k
    }

    /// this phone's public key, base64 X.509; "" if the Keychain can't keep one
    static func publicKey() -> String {
        key()?.publicKey.derRepresentation.base64EncodedString() ?? ""
    }

    /// base64 DER signature of the text (ECDSA with SHA-256); "" on failure
    static func sign(_ text: String) -> String {
        guard let k = key(), let s = try? k.signature(for: Data(text.utf8)) else { return "" }
        return s.derRepresentation.base64EncodedString()
    }

    static func verify(_ pub: String, _ text: String, _ sig: String) -> Bool {
        guard let pd = Data(base64Encoded: pub), let sd = Data(base64Encoded: sig),
              let pk = try? P256.Signing.PublicKey(derRepresentation: pd),
              let s = try? P256.Signing.ECDSASignature(derRepresentation: sd) else { return false }
        return pk.isValidSignature(s, for: Data(text.utf8))
    }

    /// The Spec's form (section 1): this phone's raw public key (65 bytes, 04 || X || Y) and a raw low-S
    /// signature (64 bytes, r || s) of msg. nil if the Keychain can't keep a key.
    static func signRaw(_ msg: Data) -> (pub: Data, sig: Data)? {
        guard let k = key(), let s = try? k.signature(for: msg) else { return nil }
        var raw = [UInt8](s.rawRepresentation)
        let n: [UInt8] = [0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                          0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51]
        var half = [UInt8](repeating: 0, count: 32)          // n / 2
        var carry: UInt8 = 0
        for i in 0..<32 { half[i] = (n[i] >> 1) | carry; carry = (n[i] & 1) << 7 }
        let sPart = Array(raw[32..<64])
        if sPart.lexicographicallyPrecedes(half) == false && sPart != half {   // s > n/2: use n - s
            var out = [UInt8](repeating: 0, count: 32)
            var borrow = 0
            for i in stride(from: 31, through: 0, by: -1) {
                var d = Int(n[i]) - Int(sPart[i]) - borrow
                borrow = d < 0 ? 1 : 0
                if d < 0 { d += 256 }
                out[i] = UInt8(d)
            }
            raw.replaceSubrange(32..<64, with: out)
        }
        return (k.publicKey.x963Representation, Data(raw))
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
