//
//  RealtimeManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseDatabase

class RealtimeManager {
    private let db = Database.database().reference()
    
    // Create a new item with auto-generated ID
    func createItem(at path: String, data: [String: Any]) async throws -> String {
        let ref = db.child(path).childByAutoId()
        try await ref.setValue(data)
        return ref.key ?? ""
    }
    
    // Set data at a specific path
    func setData(at path: String, data: [String: Any]) async throws {
        try await db.child(path).setValue(data)
    }
    
    // Get data at a path
    func getData(at path: String) async throws -> [String: Any]? {
        let snapshot = try await db.child(path).getData()
        return snapshot.value as? [String: Any]
    }
    
    // Update specific fields
    func updateData(at path: String, data: [String: Any]) async throws {
        try await db.child(path).updateChildValues(data)
    }
    
    // Delete data at path
    func deleteData(at path: String) async throws {
        try await db.child(path).removeValue()
    }
    
    // Listen to changes at a path (real-time updates)
    func observe(at path: String, completion: @escaping ([String: Any]) -> Void) -> DatabaseHandle {
        return db.child(path).observe(.value) { snapshot in
            if let value = snapshot.value as? [String: Any] {
                completion(value)
            }
        }
    }
    
    // Remove observer
    func removeObserver(at path: String, handle: DatabaseHandle) {
        db.child(path).removeObserver(withHandle: handle)
    }
    
    // Remove all observers
    func removeAllObservers(at path: String) {
        db.child(path).removeAllObservers()
    }
}

