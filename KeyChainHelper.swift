//
//  KeyChainHelper.swift
//  PlexDAPCompanion
//
//  Created by Sebastian Lidbetter on 2026-01-29.
//

import Foundation
import Security

struct KeychainHelper {
    // Unique identifiers for your app's entry in the Keychain
    static let service = "com.plex.dapcompanion"
    static let account = "plexAuthToken"

    /// Saves the token to the encrypted macOS Keychain
    static func save(_ token: String) {
            let data = Data(token.utf8)
            
            // This is the "Base Query" used to find the existing item
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]

            // 1. Define the attributes to update
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]

            // 2. Try to update the existing item
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

            // 3. If it doesn't exist (errSecItemNotFound), add it as a new item
            if status == errSecItemNotFound {
                var addQuery = query
                addQuery[kSecValueData as String] = data
                SecItemAdd(addQuery as CFDictionary, nil)
            } else if status != errSecSuccess {
                print("🔑 Keychain Update Error: \(status)")
            }
        }

    /// Retrieves the token from the Keychain if it exists
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Clears the token (useful for a "Logout" button)
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
