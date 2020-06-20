import Foundation
import CloudKit
import os.log

extension CloudKitSyncEngine {

  // MARK: - Internal

  func uploadLocalDataNotUploadedYet() {
    os_log("%{public}@", log: log, type: .debug, #function)

    let itemsToUpload = uploadBuffer.filter({ $0.ckData == nil })

    guard !itemsToUpload.isEmpty else { return }

    os_log("Found %d local items(s) which haven't been uploaded yet.", log: self.log, type: .debug, itemsToUpload.count)

    let records = itemsToUpload.map { $0.toCKRecord() }

    uploadRecords(records)
  }

  func uploadRecords(_ records: [CKRecord]) {
    guard !records.isEmpty else { return }

    os_log("%{public}@ with %d record(s)", log: log, type: .debug, #function, records.count)

    let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)

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
        self.uploadRecords([resolvedRecord])
      }
    }

    operation.modifyRecordsCompletionBlock = { [weak self] serverRecords, _, error in
      guard let self = self else { return }

      if let error = error {
        os_log("Failed to upload records: %{public}@", log: self.log, type: .error, String(describing: error))

        self.workQueue.async {
          self.handleUploadError(error, records: records)
        }
      } else {
        os_log("Successfully uploaded %{public}d record(s)", log: self.log, type: .info, records.count)

        self.workQueue.async {
          guard let serverRecords = serverRecords else { return }
          self.emitUpdatedModelsAfterUpload(with: serverRecords)
        }
      }
    }

    operation.savePolicy = .changedKeys
    operation.qualityOfService = .userInitiated
    operation.database = privateDatabase

    cloudOperationQueue.addOperation(operation)
  }

  // MARK: - Private

  private func handleUploadError(_ error: Error, records: [CKRecord]) {
    guard let ckError = error as? CKError else {
      os_log("Error was not a CKError, giving up: %{public}@", log: self.log, type: .fault, String(describing: error))
      return
    }

    if ckError.code == CKError.Code.limitExceeded {
      os_log("CloudKit batch limit exceeded, sending records in chunks", log: self.log, type: .error)

      let firstHalf = Array(records[0 ..< records.count / 2])
      let secondHalf = Array(records[records.count / 2 ..< records.count])
      let results = [firstHalf, secondHalf].map { splitRecords in
        error.retryCloudKitOperationIfPossible(self.log, queue: self.workQueue) { self.uploadRecords(splitRecords) }
      }

      if !results.allSatisfy({ $0 == true }) {
        os_log("Error is not recoverable: %{public}@", log: self.log, type: .error, String(describing: error))
      }
    } else {
      let result = error.retryCloudKitOperationIfPossible(self.log, queue: self.workQueue) { self.uploadRecords(records) }

      if !result {
        os_log("Error is not recoverable: %{public}@", log: self.log, type: .error, String(describing: error))
      }
    }
  }

  private func emitUpdatedModelsAfterUpload(with records: [CKRecord]) {
    let models: Set<Persistable> = Set(records.compactMap { r in
      guard var model = uploadBuffer.first(where: { $0.id.uuidString == r.recordID.recordName }) else { return nil }

      model.ckData = r.encodedSystemFields

      return model
    })

    workQueue.async {
      self.modelsChangedSubject.send(.updated(models))
      self.uploadBuffer = []
    }
  }

}
