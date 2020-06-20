import Foundation
import CloudKit
import CloudKitSyncEngine
import CloudKitSyncEnginePersistable
import AppSpecificCloudKitRecords
import AppModels
import Combine

public class AppSyncManager {
  public lazy var engine = CloudKitSyncEngine<Bookmark>(
    defaults: .standard,
    zoneIdentifier: CKRecordZone.ID(zoneName: String(describing: Bookmark.self), ownerName: CKCurrentUserDefaultName),
    initialItems: store.value.bookmarks
  )

  private let store: Store
  private var cancellables = Set<AnyCancellable>()

  public init(store: Store) {
    self.store = store

    engine.modelsChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] change in
        switch change {
        case let .updated(models):
          self?.store.dispatch(.cloudUpdated(models))
        case let .deleted(bookmarkIDs):
          self?.store.dispatch(.removeBookmarks(bookmarkIDs))
        }
    }
    .store(in: &cancellables)
  }
}
