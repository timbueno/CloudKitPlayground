import Foundation

public struct Bookmark: Codable, Hashable {
  public var ckData: Data?
  public var archived: Date?
  public var created: Date
  public var description: String
  public var expired: Date?
  public var id: UUID
  public var pinned: Bool
  public var siteName: String
  public var title: String
  public var url: URL

  public init(
    archived: Date? = nil,
    created: Date = Date(),
    description: String = "",
    expired: Date? = nil,
    id: UUID = UUID(),
    pinned: Bool = false,
    siteName: String,
    title: String,
    url: URL
  ) {
    self.archived = archived
    self.created = created
    self.description = description
    self.expired = expired
    self.id = id
    self.pinned = pinned
    self.siteName = siteName
    self.title = title
    self.url = url
  }
}

