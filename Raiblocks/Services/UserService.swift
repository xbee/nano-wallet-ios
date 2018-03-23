//
//  UserService.swift
//  Nano
//
//  Created by Zack Shapiro on 1/23/18.
//  Copyright © 2018 Nano. All rights reserved.
//

import Crashlytics
import RealmSwift


final class UserService {

    static func getKeychainKeyID() -> NSData {
        guard
            let path = Bundle.main.path(forResource: "Common", ofType: "plist"),
            let root = NSDictionary(contentsOfFile: path) as? [String: String],
            let keychainID = root["keychainID"]
        else {
            Crashlytics.sharedInstance().recordError(NanoWalletError.unableToGetKeychainKeyID)

            fatalError("Could not load keychain id")
        }

        // Identifier for our keychain entry - should be unique for your application
        let keychainIdentifier = keychainID
        let keychainIdentifierData = keychainIdentifier.data(using: .utf8, allowLossyConversion: false)!

        // First check in the keychain for an existing key
        var query: [NSString: AnyObject] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keychainIdentifierData as AnyObject,
            kSecAttrKeySizeInBits: 512 as AnyObject,
            kSecReturnData: true as AnyObject
        ]

        // To avoid Swift optimization bug, should use withUnsafeMutablePointer() function to retrieve the keychain item
        // See also: http://stackoverflow.com/questions/24145838/querying-ios-keychain-using-swift/27721328#27721328
        var dataTypeRef: AnyObject?
        var status = withUnsafeMutablePointer(to: &dataTypeRef) { SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0)) }
        if status == errSecSuccess {
            return dataTypeRef as! NSData
        }

        // No pre-existing key from this application, so generate a new one
        let keyData = NSMutableData(length: 64)!
        let result = SecRandomCopyBytes(kSecRandomDefault, 64, keyData.mutableBytes.bindMemory(to: UInt8.self, capacity: 64))
        assert(result == 0, "Failed to get random bytes")

        // Store the key in the keychain
        query = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keychainIdentifierData as AnyObject,
            kSecAttrKeySizeInBits: 512 as AnyObject,
            kSecValueData: keyData
        ]

        status = SecItemAdd(query as CFDictionary, nil)
        assert(status == errSecSuccess, "Failed to insert the new key in the keychain")

        return keyData
    }

    func store(credentials: Credentials, completion: (() -> Void)? = nil) {
        do {
            let realm = try Realm()

            try realm.write {
                realm.add(credentials)

                completion?()
            }
        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.credentialStorageError)
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "LogOut"), object: nil)
        }
    }

    func fetchCredentials() -> Credentials? {
        do {
            let realm = try Realm()

            return realm.objects(Credentials.self).first

        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.unableToFetchCredentials)

            return nil
        }
    }

    /// Used for updating with socketUUID and hasCompletedLegalAgreements
    func update(credentials: Credentials) {
        do {
            let realm = try Realm()

            try realm.write {
                realm.add(credentials, update: true)
                realm.refresh()
            }
        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.unableToUpdateCredentialsWithUUID)
        }
    }

    func updateLegal() {
        guard let credentials = fetchCredentials() else { return }

        do {
            let realm = try Realm()

            try realm.write {
                credentials.hasCompletedLegalAgreements = true
                realm.add(credentials, update: true)

                realm.refresh()
            }
        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.unableToUpdateCredentialsWithLegalAgreement)

            return
        }
    }

    func currentUserSeed() -> String? {
        do {
            let realm = try Realm()

            return realm.objects(Credentials.self).first?.seed
        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.unableToGetCurrentUserSeed)

            return nil
        }
    }

    static func logOut() {
        do {
            let realm = try Realm()

            try realm.write {
                realm.deleteAll()
            }
        } catch {
            Crashlytics.sharedInstance().recordError(NanoWalletError.logOutError)
        }
    }

}
