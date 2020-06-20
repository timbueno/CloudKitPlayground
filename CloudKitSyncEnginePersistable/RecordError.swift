import Foundation
import CloudKit

public struct RecordError: LocalizedError {
  var localizedDescription: String

  public static func missingKey<Key: RawRepresentable>(_ key: Key) -> RecordError where Key.RawValue == String {
    RecordError(localizedDescription: "Missing required key \(key.rawValue)")
  }

  public static func missingIdentifier(_ record: CKRecord) -> RecordError {
    RecordError(localizedDescription: "Missing required identifier \(record.description)")
  }
}
