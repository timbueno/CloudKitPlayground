import Foundation
import CloudKit
import CloudKitSyncEnginePersistable
import Combine
import os.log

public final class CloudKitSyncEngine<Persistable: CloudKitSyncEnginePersistable> {

  // MARK: - Public Properties

  /// Called after models are updated with CloudKit data. No thread guarantees.
  public private(set) lazy var modelsUpdated = modelsUpdatedSubject.eraseToAnyPublisher()

  /// Called when models are deleted remotely. No thread guarantees.
  public private(set) lazy var modelsDeleted = modelsDeletedSubject.eraseToAnyPublisher()

  /// Called when the user's iCloud account status changes.
  @Published public internal(set) var accountStatus: CKAccountStatus = .couldNotDetermine {
    willSet {
      // Force a sync if the user account status changes to available while the app is running
      if accountStatus != .available
        && hasSetFetchedAccountStatus
        && newValue == .available {
        forceSync()
      }
    }
  }

  // MARK: - Internal Properties

  let log = OSLog(
    subsystem: "com.jayhickey.CloudKitSync",
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
  let modelsUpdatedSubject = PassthroughSubject<[Persistable], Never>()
  let modelsDeletedSubject = PassthroughSubject<[String], Never>()
  var hasSetFetchedAccountStatus = false

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


  public func upload(_ item: Persistable) {
    os_log("%{public}@", log: log, type: .debug, #function)

    workQueue.async {
      self.uploadBuffer.append(item)
      self.uploadRecords([item.toCKRecord()])
    }
  }

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

      // Initialize CloudKit with private custom zone
      self.initializeZone(with: self.cloudOperationQueue)

      // Subscribe to CloudKit changes
      self.initializeSubscription(with: self.cloudOperationQueue)

      os_log("Cloud environment preparation done", log: self.log, type: .debug)

      self.uploadLocalDataNotUploadedYet()
      self.fetchRemoteChanges()
    }
  }
}
