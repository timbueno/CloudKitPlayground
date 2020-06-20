import Foundation
import CloudKit
import CloudKitSyncEngine
import CloudKitSyncEnginePersistable
import AppSpecificCloudKitRecords
import AppModels
import Combine

public class AppSyncManager {
  let appCustomZoneID = CKRecordZone.ID(zoneName: "CloudKitSyncEngineZone", ownerName: CKCurrentUserDefaultName)
  public lazy var engine = CloudKitSyncEngine<Bookmark>(
    defaults: .standard,
    zoneIdentifier: CKRecordZone.ID(zoneName: String(describing: Bookmark.self), ownerName: CKCurrentUserDefaultName),
    initialItems: store.value.bookmarks
  )

  private let store: Store
  private var cancellables = Set<AnyCancellable>()

  public init(store: Store) {
    self.store = store

    engine.modelsUpdated
      .receive(on: DispatchQueue.main)
      .sink { [weak self] models in
      self?.store.dispatch(.cloudUpdated(models))
    }
    .store(in: &cancellables)

    engine.modelsDeleted
      .receive(on: DispatchQueue.main)
      .sink { [weak self] identifiers in
      self?.store.dispatch(.removeBookmarks(identifiers.compactMap(UUID.init(uuidString:))))
    }
    .store(in: &cancellables)
  }
}
