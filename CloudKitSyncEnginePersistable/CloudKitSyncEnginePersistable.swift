import Foundation
import CloudKit

public protocol CloudKitSyncEnginePersistable {
  var id: UUID { get }

  /// Used to store the encoded `CKRecord.ID` so that local records can be matched with
  /// records on the server. This ensures updates don't cause duplication of records.
  var ckData: Data? { get set }
//  static var customZoneID: CKRecordZone.ID { get }
  static var recordType: CKRecord.RecordType { get }

  func toCKRecord() -> CKRecord
  init(record: CKRecord) throws

  static func resolveConflict(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord?
}

public extension CloudKitSyncEnginePersistable {
  func emptyRecord<T>(for class: T.Type) -> CKRecord {
    let zoneID = CKRecordZone.ID(zoneName: String(describing: T.self), ownerName: CKCurrentUserDefaultName)
    let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    return CKRecord(recordType: Self.recordType, recordID: recordID)
  }
}
