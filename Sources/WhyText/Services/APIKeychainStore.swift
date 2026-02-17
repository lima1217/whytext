import Foundation
import LocalAuthentication
import Security

final class APIKeychainStore {
    private let primaryService: String
    private let legacyServices: [String]

    init(service: String? = nil) {
        let base = service ?? (Bundle.main.bundleIdentifier ?? "WhyText") + ".api-key"

        if service == nil {
            self.primaryService = "\(base).v2"
            self.legacyServices = [base]
        } else {
            self.primaryService = base
            self.legacyServices = []
        }
    }

    func apiKey(for providerID: UUID) -> String? {
        if let value = readAPIKey(for: providerID, service: primaryService) {
            return value
        }

        for legacy in legacyServices {
            guard let value = readAPIKey(for: providerID, service: legacy) else { continue }
            _ = saveAPIKey(value, for: providerID)
            return value
        }

        return nil
    }

    @discardableResult
    func saveAPIKey(_ value: String, for providerID: UUID) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return deleteAPIKey(for: providerID)
        }

        guard let data = trimmed.data(using: .utf8) else { return false }

        var query = baseQuery(for: providerID, service: primaryService)
        query[kSecUseAuthenticationContext as String] = nonInteractiveContext()

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecInteractionNotAllowed {
            _ = deleteItem(for: providerID, service: primaryService)
        } else if updateStatus != errSecItemNotFound {
            return false
        }

        var addQuery = baseQuery(for: providerID, service: primaryService)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func deleteAPIKey(for providerID: UUID) -> Bool {
        var ok = deleteItem(for: providerID, service: primaryService)
        for legacy in legacyServices {
            ok = deleteItem(for: providerID, service: legacy) && ok
        }
        return ok
    }

    private func readAPIKey(for providerID: UUID, service: String) -> String? {
        var query = baseQuery(for: providerID, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = nonInteractiveContext()

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteItem(for providerID: UUID, service: String) -> Bool {
        var query = baseQuery(for: providerID, service: service)
        query[kSecUseAuthenticationContext as String] = nonInteractiveContext()

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(for providerID: UUID, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString,
        ]
    }

    private func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
