import SwiftUI
import AppModels
import CryptoKit
import CloudKit

struct MultipleSelectionRow<Content: View>: View {
  var childView: Content
  var isSelected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: self.action) {
      HStack {
        childView
        if self.isSelected {
          Spacer()
          Image(systemName: "checkmark")
        }
      }
    }
  }
}

struct BookmarkRow: View {
  @State var bookmark: Bookmark

  var body: some View {
    VStack(alignment: .leading) {
      Text("\(bookmark.url.path)")

      Text(bookmark.id.uuidString)
        .fontWeight(.medium)
        .scaledToFill()

      Text({ () -> String in
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd @ hh:mm:ss.SSS"
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        return formatter.string(from: bookmark.created)
      }())
        .font(.system(size: 12))
        .bold()

      Text(bookmark.title)
        .font(.system(size: 12))
        .fontWeight(.light)
    }
  }
}

struct ContentView: View {
  @ObservedObject var store: Store
  var syncManager: AppSyncManager
  @State private var accountStatus: CKAccountStatus = .couldNotDetermine
  @State private var selections: [Bookmark] = []

  init(store: Store, syncManager: AppSyncManager) {
    self.store = store
    self.syncManager = syncManager
    self.accountStatus = syncManager.engine.accountStatus
  }

  var body: some View {
    NavigationView {
      VStack {
        VStack(alignment: .leading) {
          Text("iCloud Account Status: \(state(for: accountStatus))")
          Text("Hash: \(store.value.hash)")
          HStack {
            Text("Total Count: \(store.value.bookmarks.count)")
            if self.selections.count > 0 {
              Text("Selected: \(selections.count)")
            }
          }
        }
        .padding([.leading], 20)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .foregroundColor(.gray)
        List {
          ForEach(store.value.bookmarks, id: \.id) { bookmark in
            MultipleSelectionRow(childView: BookmarkRow(bookmark: bookmark), isSelected: self.selections.contains(bookmark)) {
              if self.selections.contains(bookmark) {
                self.selections.removeAll(where: { $0 == bookmark })
              }
              else {
                self.selections.append(bookmark)
              }
            }
          }
          .onDelete(perform: delete)
        }
        Button("Add Bookmark") {
          if let element = testURLs.randomElement() {
            self.addBookmark(element)
          }
        }
        .padding()
      }
      .navigationBarTitle(Text("Bookmarks"))
      .navigationBarItems(leading:
        Button(action: {
          self.store.dispatch(.fetchChanges)
        }) {
          Text("Force Sync")
        }, trailing:
        !selections.isEmpty
          ? Button(action: {
            self.delete(bookmarks: self.selections)
            self.selections = []
          }) {
              Text("Delete")
            }
          : nil
      )
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .onReceive(syncManager.engine.$accountStatus) { status in
      self.accountStatus = status
    }
  }

  func state(for status: CKAccountStatus) -> String {
    switch status {
    case .available:
      return "Available"
    case .couldNotDetermine:
      return "Could not determine"
    case .noAccount:
      return "No account"
    case .restricted:
      return "Restricted"
    @unknown default:
      return "Unknown"
    }
  }

  func delete(at offsets: IndexSet) {
    if let index = offsets.first {
      let bookmark = store.value.bookmarks[index]
      store.dispatch(.removeBookmarks([bookmark.id]))
    }
  }

  func delete(bookmarks: [Bookmark]) {
    store.dispatch(.removeBookmarks(bookmarks.map(\.id)))
  }

  func addBookmark(_ url: URL) {
    store.dispatch(.addBookmark(url))
  }

  func addBookmark() {
    if let url = testURLs.randomElement() {
      store.dispatch(.addBookmark(url))
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static let store = defaultStore()
  static var previews: some View {
    ContentView(store: store, syncManager: AppSyncManager(store: store))
  }
}
