import Foundation
import CloudKit
import CloudKitSyncEnginePersistable
import Combine
import os.log

public final class CloudKitSyncEngine<Persistable: CloudKitSyncEnginePersistable> {

  public enum ModelChange {
    case deleted(Set<UUID>)
    case updated(Set<Persistable>)
  }

  // MARK: - Public Properties

  /// Called when models are updated or deleted remotely. No thread guarantees.
  public private(set) lazy var modelsChanged = modelsChangedSubject.eraseToAnyPublisher()

  /// Called when the user's iCloud account status changes.
  @Published public internal(set) var accountStatus: CheckedAccountStatus = .notChecked {
    willSet {
      // Force a sync if the user account status changes to available while the app is running
      if case let .checked(status) = newValue,
        status == .available,
        accountStatus != CheckedAccountStatus.notChecked {
        forceSync()
      }
    }
  }

  // MARK: - Internal Properties

  lazy var log = OSLog(
    subsystem: "com.jayhickey.CloudKitSync.\(zoneIdentifier.zoneName)",
    category: String(describing: CloudKitSyncEngine.self)
  )

  lazy var privateSubscriptionIdentifier = "\(zoneIdentifier.zoneName).subscription"
  lazy var privateChangeTokenKey = "TOKEN-\(zoneIdentifier.zoneName)"
  lazy var createdPrivateSubscriptionKey = "CREATEDSUBDB-\(zoneIdentifier.zoneName))"
  lazy var createdCustomZoneKey = "CREATEDZONE-\(zoneIdentifier.zoneName))"
  lazy var deleteBufferKey = "DELETEBUFFER-\(zoneIdentifier.zoneName))"

  let workQueue = DispatchQueue(label: "CloudKitSyncEngine.Work", qos: .userInitiated)
  private let cloudQueue = DispatchQueue(label: "CloudKitSyncEngine.Cloud", qos: .userInitiated)

  let defaults: UserDefaults
  let recordType: CKRecord.RecordType
  let zoneIdentifier: CKRecordZone.ID

  lazy var container: CKContainer = CKContainer.default()

  lazy var privateDatabase: CKDatabase = container.privateCloudDatabase

  var uploadBuffer: [Persistable]
  var cancellables = Set<AnyCancellable>()
  let modelsChangedSubject = PassthroughSubject<ModelChange, Never>()

  lazy var cloudOperationQueue: OperationQueue = {
    let queue = OperationQueue()

    queue.underlyingQueue = cloudQueue
    queue.name = "CloudKitSyncEngine.Cloud"
    queue.maxConcurrentOperationCount = 1

    return queue
  }()

  /// - Parameters:
  ///   - defaults: The `UserDefaults` used to store sync state information
  ///   - zoneIdentifier: An identifier that will be used to create a custom private zone for the CloudKit data
  ///   - initialItems: An initial array of items to sync
  ///
  /// `initialItems` is used to perform a sync of any local models that don't yet exist in CloudKit. The engine uses the
  /// presence of data in `ckData` to determine what models to upload. Alternatively, you can do this yourself and page items
  /// into `upload(_:)` instead.
  public init(defaults: UserDefaults, zoneIdentifier: CKRecordZone.ID, initialItems: [Persistable]) {
    self.defaults = defaults
    self.recordType = String(describing: Persistable.self)
    self.zoneIdentifier = zoneIdentifier
    self.uploadBuffer = initialItems

    observeAccountStatus()
    setupCloudEnvironment()
  }

  // MARK: - Public Methods

  /// Forces a data synchronization with CloudKit.
  ///
  /// This method performs the following actions on CloutKit in this order:
  /// 1. Deletes any items that were deleted locally.
  /// 2. Uploads any items that were added locally.
  /// 3. Fetches for any remote changes.
  public func forceSync() {
    os_log("%{public}@", log: log, type: .debug, #function)

    workQueue.async {
      self.deleteCloudDataNotDeletedYet()
      self.uploadLocalDataNotUploadedYet()
      self.fetchRemoteChanges()
    }
  }


  // Uploads a CloudKitSyncEnginePersistable to iCloud
  public func upload(_ item: Persistable) {
    os_log("%{public}@", log: log, type: .debug, #function)

    workQueue.async {
      self.uploadBuffer.append(item)
      self.uploadRecords([item.toCKRecord()])
    }
  }

  // Deletes a CloudKitSyncEnginePersistable from iCloud
  public func delete(_ item: Persistable) {
    os_log("%{public}@", log: log, type: .debug, #function)

    let recordID = item.toCKRecord().recordID

    workQueue.async {
      self.deleteBuffer.append(recordID)
      self.deleteRecords([recordID])
    }
  }

  @discardableResult public func processSubscriptionNotification(with userInfo: [AnyHashable : Any]) -> Bool {
    os_log("%{public}@", log: log, type: .debug, #function)

    guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
      os_log("Not a CKNotification", log: self.log, type: .error)
      return false
    }

    guard notification.subscriptionID == privateSubscriptionIdentifier else {
      os_log("Not our subscription ID", log: self.log, type: .debug)
      return false
    }

    os_log("Received remote CloudKit notification for user data", log: log, type: .debug)

    self.workQueue.async { [weak self] in
      self?.fetchRemoteChanges()
    }

    return true
  }

  // MARK: - Private Methods

  private func setupCloudEnvironment() {
    workQueue.async { [weak self] in
      guard let self = self else { return }

      // Initialize CloudKit with private custom zone, but bail early if we fail
      guard self.initializeZone(with: self.cloudOperationQueue) else {
        os_log("Unable to initialize zone, bailing from setup early", log: self.log, type: .error)
        return
      }

      // Subscribe to CloudKit changes, but bail early if we fail
      guard self.initializeSubscription(with: self.cloudOperationQueue) else {
        os_log("Unable to initialize subscription to changes, bailing from setup early", log: self.log, type: .error)
        return
      }

      os_log("Cloud environment preparation done", log: self.log, type: .debug)

      self.uploadLocalDataNotUploadedYet()
      self.fetchRemoteChanges()
    }
  }
}
