import Foundation
import CloudKitSyncEnginePersistable
import CloudKit
import AppModels

enum BookmarkKey: String {
  case url
  case title
  case siteName
  case created
  case modifiedDate
}

extension Bookmark: CloudKitSyncEnginePersistable {

//  public static var customZoneID: CKRecordZone.ID { AppSyncConstants.customZoneID }
  public static var recordType: CKRecord.RecordType { String(describing: Bookmark.self) }

  public init(record: CKRecord) throws {
    guard let id = UUID(uuidString: record.recordID.recordName) else {
      throw RecordError.missingIdentifier(record)
    }
    guard let created = record[BookmarkKey.created] as? Date else {
        throw RecordError.missingKey(BookmarkKey.created)
    }
    guard let title = record[BookmarkKey.title] as? String else {
        throw RecordError.missingKey(BookmarkKey.title)
    }
    guard let urlString = record[BookmarkKey.url] as? String,
      let url = URL(string: urlString) else {
        throw RecordError.missingKey(BookmarkKey.url)
    }
    guard let siteName = record[BookmarkKey.siteName] as? String else {
        throw RecordError.missingKey(BookmarkKey.siteName)
    }

    self.init(created: created, id: id, siteName: siteName, title: title, url: url)
    self.ckData = record.encodedSystemFields
  }

  public static func resolveConflict(clientRecord: CKRecord, serverRecord: CKRecord) -> CKRecord? {
    if let clientModificationDate = clientRecord[BookmarkKey.modifiedDate] as? Date,
      let serverModificationDate = clientRecord[BookmarkKey.modifiedDate] as? Date {
      return clientModificationDate > serverModificationDate ? clientRecord : serverRecord
    }
    return serverRecord
  }

  public func toCKRecord() -> CKRecord {
    let record = emptyRecord(for: Bookmark.self)
    record[BookmarkKey.url] = url.absoluteString
    record[BookmarkKey.title] = title
    record[BookmarkKey.siteName] = siteName
    record[BookmarkKey.created] = created
    record[BookmarkKey.modifiedDate] = Date()
    return record
  }
}
