import Foundation
import AppModels
import CryptoKit

public struct AppState: Codable {
  public internal(set) var bookmarks: [Bookmark] = []
  public var hash: String {
    do {
      let data = try JSONEncoder().encode(bookmarks.map(\.id))
      return Insecure.MD5.hash(data: data)
        .map {
          String(format: "%02hhx", $0)
      }.joined()
    } catch {
      return "Unknown"
    }
  }
}
