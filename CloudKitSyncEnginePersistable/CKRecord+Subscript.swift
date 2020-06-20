import Foundation
import CloudKit

public extension CKRecord {
  subscript<Key: RawRepresentable>(key: Key) -> Any? where Key.RawValue == String {
    get {
      return self[key.rawValue]
    }
    set {
      self[key.rawValue] = newValue as? CKRecordValue
    }
  }
}
