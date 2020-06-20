import Foundation
import AppModels

public enum AppAction {
  case addBookmark(URL)
  case removeBookmarks([UUID])
  case cloudUpdated([Bookmark])
  case fetchChanges
}
