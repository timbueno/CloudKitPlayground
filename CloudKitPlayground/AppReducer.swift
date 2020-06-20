import Foundation
import AppModels
import CloudKitSyncEngine
import AppSpecificCloudKitRecords

public func appReducer(appState: inout AppState, actions: AppAction) {
  switch actions {
  case let .addBookmark(url):
    let bookmark = Bookmark(created: Date(), siteName: url.host ?? "Some Site Name", title: url.host ?? "New Bookmark", url: url)
    appState.bookmarks.append(bookmark)
    syncManager?.engine.upload(bookmark)
  case .removeBookmarks(let identifiers):
    let bookmarksToDelete = appState.bookmarks.filter { identifiers.contains($0.id) }
    appState.bookmarks.removeAll(where: { identifiers.contains($0.id) })
    if let manager = syncManager {
      bookmarksToDelete.forEach(manager.engine.delete)
    }
  case .cloudUpdated(let bookmarks):
    bookmarks.forEach { updatedBookmark in
        guard let idx = appState.bookmarks.firstIndex(where: { $0.id == updatedBookmark.id }) else { return }
        appState.bookmarks[idx] = updatedBookmark
    }
    let newBookmarks = bookmarks
      .filter { !appState.bookmarks.contains($0) }
    appState.bookmarks = appState.bookmarks + newBookmarks
  case .fetchChanges:
    syncManager?.engine.forceSync()
  }
}
