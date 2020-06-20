import Foundation
import CloudKit
import os.log

extension CloudKitSyncEngine {

  // MARK: - Internal

  func deleteCloudDataNotDeletedYet() {
    os_log("%{public}@", log: log, type: .debug, #function)

    guard !deleteBuffer.isEmpty else { return }

    os_log("Found %d deleted items(s) which haven't been deleted in iCloud yet.", log: self.log, type: .debug, deleteBuffer.count)

    deleteRecords(deleteBuffer)
  }

  func deleteRecords(_ recordIDs: [CKRecord.ID]) {
    guard !recordIDs.isEmpty else { return }

    os_log("%{public}@ with %d record(s)", log: log, type: .debug, #function, recordIDs.count)

    let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)

    operation.perRecordCompletionBlock = { [weak self] record, error in
      guard let self = self else { return }

      // We're only interested in conflict errors here
      guard let error = error, error.isCloudKitConflict else { return }

      os_log("CloudKit conflict with record of type %{public}@", log: self.log, type: .error, record.recordType)

      guard let resolvedRecord = error.resolveConflict(with: Persistable.resolveConflict) else {
        os_log(
          "Resolving conflict with record of type %{public}@ returned a nil record. Giving up.",
          log: self.log,
          type: .error,
          record.recordType
        )
        return
      }

      os_log("Conflict resolved, will retry upload", log: self.log, type: .info)

      self.workQueue.async {
        self.deleteRecords([resolvedRecord.recordID])
      }
    }

    operation.modifyRecordsCompletionBlock = { [weak self] serverRecords, _, error in
      guard let self = self else { return }

      if let error = error {
        os_log("Failed to delete records: %{public}@", log: self.log, type: .error, String(describing: error))

        self.workQueue.async {
          self.handleDeleteError(error, records: recordIDs)
        }
      } else {
        os_log("Successfully deleted %{public}d record(s)", log: self.log, type: .info, recordIDs.count)

        self.workQueue.async {
          guard let serverRecords = serverRecords else { return }
          let recordsSet = Set(
            serverRecords
              .map(\.recordID.recordName)
              .compactMap(UUID.init(uuidString:))
          )
          self.modelsChangedSubject.send(.deleted(recordsSet))
          self.deleteBuffer = []
        }
      }
    }

    operation.qualityOfService = .userInitiated
    operation.savePolicy = .ifServerRecordUnchanged
    operation.database = privateDatabase
    cloudOperationQueue.addOperation(operation)
  }

  var deleteBuffer: [CKRecord.ID] {
    get {
      guard let data = defaults.data(forKey: deleteBufferKey) else { return [] }
      do {
        return try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [CKRecord.ID] ?? []
      } catch {
        os_log("Failed to decode CKRecord.IDs from defaults key deleteBufferKey", log: log, type: .error)
        return []
      }
    }
    set {
      do {
        let data = try NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
        defaults.set(data, forKey: deleteBufferKey)
      } catch {
        os_log("Failed to encode record ids for deletion: %{public}@", log: self.log, type: .error, String(describing: error))
      }
    }
  }

  // MARK: - Private

  private func handleDeleteError(_ error: Error, records: [CKRecord.ID]) {
    guard let ckError = error as? CKError else {
      os_log("Error was not a CKError, giving up: %{public}@", log: self.log, type: .fault, String(describing: error))
      return
    }

    if ckError.code == CKError.Code.limitExceeded {
      os_log("CloudKit batch limit exceeded, sending records in chunks", log: self.log, type: .error)

      let firstHalf = Array(records[0 ..< records.count / 2])
      let secondHalf = Array(records[records.count / 2 ..< records.count])
      let results = [firstHalf, secondHalf].map { splitRecords in
        error.retryCloudKitOperationIfPossible(self.log, queue: self.workQueue) { self.deleteRecords(splitRecords) }
      }

      if !results.allSatisfy({ $0 == true }) {
        os_log("Error is not recoverable: %{public}@", log: self.log, type: .error, String(describing: error))
      }
    } else {
      let result = error.retryCloudKitOperationIfPossible(self.log, queue: self.workQueue) { self.deleteRecords(records) }

      if !result {
        os_log("Error is not recoverable: %{public}@", log: self.log, type: .error, String(describing: error))
      }
    }
  }
}
