import Foundation
import CloudKitSyncEngine
import AppModels
import CloudKitSyncEngine

public typealias Reducer = (inout AppState, AppAction) -> Void

public func defaultStore() -> Store {
  let appState = PersistentStore.load()
  return Store(value: appState ?? AppState(), reducer: appReducer)
}

public class Store: ObservableObject {
  @Published public internal(set) var value: AppState
  private let reducer: Reducer

  public init(value: AppState, reducer: @escaping Reducer) {
    self.value = value
    self.reducer = reducer
  }

  public func dispatch(_ action: AppAction) {
    reducer(&value, action)
    value.bookmarks = value.bookmarks.sorted(by: { $0.created > $1.created })
    PersistentStore.save(state: value)
  }
}
