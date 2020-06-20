import Foundation
import AppModels

public enum AppAction {
  case addBookmark(URL)
  case removeBookmarks(Set<UUID>)
  case cloudUpdated(Set<Bookmark>)
  case fetchChanges
}
