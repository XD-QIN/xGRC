import CameraKit
import Foundation
#if canImport(Security)
import Security
#endif

/// Small secrets keyed by account name.
public protocol SecretStore: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data?, for account: String) throws
}

public enum SecretStoreError: Error, Hashable, Sendable {
    case keychain(status: Int32)
}

/// Process-local store for tests and non-Apple builds.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func set(_ data: Data?, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = data
    }
}

#if canImport(Security)
/// Generic-password items, `AfterFirstUnlockThisDeviceOnly` (background
/// reconnects work after the first unlock) and never synchronised, so iCloud
/// Keychain cannot give the phone and the watch the same identity.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw SecretStoreError.keychain(status: status)
        }
    }

    public func set(_ data: Data?, for account: String) throws {
        let query = baseQuery(account)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecretStoreError.keychain(status: status)
            }
            return
        }
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status: status) }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
#endif

/// `ClientIdentity` and per-camera `CameraIdentity` on top of a `SecretStore`.
public struct IdentityStore: Sendable {
    public let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// Our identity as cameras see it, generated on first use.
    public func clientIdentity() throws -> ClientIdentity {
        if let data = try secrets.data(for: "client-identity"),
           let identity = try? JSONDecoder().decode(ClientIdentity.self, from: data) {
            return identity
        }
        let identity = ClientIdentity.generate()
        try secrets.set(try JSONEncoder().encode(identity), for: "client-identity")
        return identity
    }

    public func cameraIdentity(for recordID: UUID) throws -> CameraIdentity? {
        try secrets.data(for: "camera-\(recordID.uuidString)")
            .flatMap { try? JSONDecoder().decode(CameraIdentity.self, from: $0) }
    }

    public func setCameraIdentity(_ identity: CameraIdentity?, for recordID: UUID) throws {
        try secrets.set(try identity.map { try JSONEncoder().encode($0) }, for: "camera-\(recordID.uuidString)")
    }
}
