import Foundation
import OpenDirectory
import Security

/// Face Unlock's secret, kept in the login keychain on this Mac: the faceprints from the scan and the Mac password it
/// types at the lock screen, in one item. Nothing here leaves the Mac.
///
/// SAVISUL is signed without an Apple team, so the keychain ties the item to the exact build that wrote it; a new build
/// has to be allowed once, when macOS asks for the keychain password. One item means one question after an update.
enum FaceVault {
    struct Secret: Codable, Equatable {
        /// The recognizer version that made the prints; see `FaceEngine.revision`.
        var revision: Int
        var prints: [[Float]]
        var created: Date
        var password: String
        /// Prints learned at unlocks since the setup; see `FaceLearning`.
        var learned: [[Float]]? = nil
    }

    enum Failure: Error, Equatable {
        /// Nothing stored: Face Unlock was never set up, or was removed.
        case missing
        /// Stored, but this build of SAVISUL wasn't allowed to read it, or nobody was there to allow it.
        case denied
        /// Stored in a shape this version can't read.
        case damaged
    }

    private static let service = "com.savisul.face-unlock"
    private static let account = "face-unlock"
    /// The first version kept the prints and the password apart; they are joined on the first read.
    private static let legacyFaces = "faces"
    private static let legacyPassword = "password"

    /// Something is stored. Asks the keychain without reading anything, so it never prompts.
    static var isSetUp: Bool { exists(account) || (exists(legacyFaces) && exists(legacyPassword)) }

    @discardableResult
    static func save(_ secret: Secret) -> Bool {
        guard let data = try? JSONEncoder().encode(secret) else { return false }
        var item = query(account)
        SecItemDelete(item as CFDictionary)
        item[kSecAttrLabel as String] = "SAVISUL Face Unlock"
        item[kSecValueData as String] = data
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return false }
        SecItemDelete(query(legacyFaces) as CFDictionary)
        SecItemDelete(query(legacyPassword) as CFDictionary)
        return true
    }

    /// The stored secret. At the lock screen nobody can answer a keychain prompt, so `prompt: false` fails instead of asking.
    static func load(prompt: Bool) -> Result<Secret, Failure> {
        switch read(account, prompt: prompt) {
        case .success(let data):
            guard let secret = try? JSONDecoder().decode(Secret.self, from: data) else { return .failure(.damaged) }
            return .success(secret)
        case .failure(.missing):
            return joinLegacy(prompt: prompt)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private struct LegacyFaces: Codable {
        var revision: Int
        var prints: [[Float]]
        var created: Date
    }

    private static func joinLegacy(prompt: Bool) -> Result<Secret, Failure> {
        let faces = read(legacyFaces, prompt: prompt)
        guard case .success(let facesData) = faces else {
            if case .failure(let failure) = faces { return .failure(failure) }
            return .failure(.missing)
        }
        let password = read(legacyPassword, prompt: prompt)
        guard case .success(let passwordData) = password else {
            if case .failure(let failure) = password { return .failure(failure) }
            return .failure(.missing)
        }
        guard let old = try? JSONDecoder().decode(LegacyFaces.self, from: facesData),
              let text = String(data: passwordData, encoding: .utf8) else { return .failure(.damaged) }
        let secret = Secret(revision: old.revision, prints: old.prints, created: old.created, password: text)
        save(secret)
        return .success(secret)
    }

    static func erase() {
        for name in [account, legacyFaces, legacyPassword] { SecItemDelete(query(name) as CFDictionary) }
    }

    /// Whether this is the account's password, checked by the system's directory service. Nothing is unlocked by asking.
    static func verify(_ password: String) -> Bool {
        guard !password.isEmpty,
              let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
    }

    private static func read(_ name: String, prompt: Bool) -> Result<Data, Failure> {
        var item = query(name)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        if !prompt { item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: AnyObject?
        switch SecItemCopyMatching(item as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else { return .failure(.damaged) }
            return .success(data)
        case errSecItemNotFound:
            return .failure(.missing)
        default:
            return .failure(.denied)
        }
    }

    private static func exists(_ name: String) -> Bool {
        var item = query(name)
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(item as CFDictionary, nil) == errSecSuccess
    }
}
