import CoreLocation
import FirebaseFirestore
import Foundation

struct User: Identifiable, Codable, Equatable, Hashable {
  @DocumentID var id: String?
  var username: String
  var email: String
  var fullName: String
  var bio: String?
  var isPrivate: Bool = false
  var isDatingEnabled: Bool = false
  var profileImageURL: String?
  var location: GeoPoint?
  var gender: Gender
  var interestedIn: [Gender]
  var maxDistance: Double = 50  // miles
  var ageRangeMin: Int = 18
  var ageRangeMax: Int = 100
  var followersCount: Int = 0
  var followingCount: Int = 0
  var createdAt: Date = Date()
  var datingImages: [String] = []  // URLs, max 5
  var birthday: Date?  // New field for birthday

  // Computed properties for search
  var username_lowercase: String {
    username.lowercased()
  }

  var fullName_lowercase: String {
    fullName.lowercased()
  }

  var age: Int? {
    guard let birthday = birthday else { return nil }
    return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
  }

  var ageRange: ClosedRange<Int> {
    get {
      ageRangeMin...ageRangeMax
    }
    set {
      ageRangeMin = newValue.lowerBound
      ageRangeMax = newValue.upperBound
    }
  }

  init(
    username: String,
    email: String,
    fullName: String,
    bio: String? = nil,
    isPrivate: Bool = false,
    isDatingEnabled: Bool = false,
    profileImageURL: String? = nil,
    location: GeoPoint? = nil,
    gender: Gender,
    interestedIn: [Gender] = [],
    maxDistance: Double = 50,
    ageRangeMin: Int = 18,
    ageRangeMax: Int = 100,
    followersCount: Int = 0,
    followingCount: Int = 0,
    createdAt: Date = Date(),
    datingImages: [String] = [],
    birthday: Date? = nil
  ) {
    self.username = username
    self.email = email
    self.fullName = fullName
    self.bio = bio
    self.isPrivate = isPrivate
    self.isDatingEnabled = isDatingEnabled
    self.profileImageURL = profileImageURL
    self.location = location
    self.gender = gender
    self.interestedIn = interestedIn
    self.maxDistance = maxDistance
    self.ageRangeMin = ageRangeMin
    self.ageRangeMax = ageRangeMax
    self.followersCount = followersCount
    self.followingCount = followingCount
    self.createdAt = createdAt
    self.datingImages = datingImages
    self.birthday = birthday
  }

  enum Gender: String, Codable, CaseIterable, Identifiable {
    case male = "male"
    case female = "female"
    case nonBinary = "nonBinary"
    case other = "other"

    var id: String { rawValue }
  }

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case email
    case fullName
    case bio
    case isPrivate
    case isDatingEnabled
    case profileImageURL
    case location
    case gender
    case interestedIn
    case maxDistance
    case ageRangeMin = "ageRange.min"
    case ageRangeMax = "ageRange.max"
    case followersCount
    case followingCount
    case createdAt
    case datingImages
    case username_lowercase
    case fullName_lowercase
    case birthday
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = decoder.userInfo[.decodingDefaultsKey] as? [String: Any] ?? [:]

    // Handle DocumentID field
    self.id = try container.decodeIfPresent(String.self, forKey: .id)

    // Decode required fields
    self.username = try container.decode(String.self, forKey: .username)
    self.email = try container.decode(String.self, forKey: .email)
    self.fullName = try container.decode(String.self, forKey: .fullName)
    self.gender = try container.decode(Gender.self, forKey: .gender)

    // Decode optional fields with default values
    self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
    self.isPrivate =
      try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
      ?? (defaults["isPrivate"] as? Bool ?? false)
    self.isDatingEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .isDatingEnabled)
      ?? (defaults["isDatingEnabled"] as? Bool ?? false)
    self.profileImageURL = try container.decodeIfPresent(String.self, forKey: .profileImageURL)
    self.location = try container.decodeIfPresent(GeoPoint.self, forKey: .location)

    // Handle interestedIn array with defaults
    if let interestedInStrings = try? container.decode([String].self, forKey: .interestedIn) {
      self.interestedIn = interestedInStrings.compactMap { Gender(rawValue: $0) }
    } else if let genderArray = try? container.decode([Gender].self, forKey: .interestedIn) {
      self.interestedIn = genderArray
    } else {
      self.interestedIn = []
    }

    self.maxDistance =
      try container.decodeIfPresent(Double.self, forKey: .maxDistance)
      ?? (defaults["maxDistance"] as? Double ?? 50.0)
    self.ageRangeMin =
      try container.decodeIfPresent(Int.self, forKey: .ageRangeMin)
      ?? (defaults["ageRangeMin"] as? Int ?? 18)
    self.ageRangeMax =
      try container.decodeIfPresent(Int.self, forKey: .ageRangeMax)
      ?? (defaults["ageRangeMax"] as? Int ?? 100)
    self.followersCount =
      try container.decodeIfPresent(Int.self, forKey: .followersCount)
      ?? (defaults["followersCount"] as? Int ?? 0)
    self.followingCount =
      try container.decodeIfPresent(Int.self, forKey: .followingCount)
      ?? (defaults["followingCount"] as? Int ?? 0)
    self.datingImages =
      try container.decodeIfPresent([String].self, forKey: .datingImages)
      ?? (defaults["datingImages"] as? [String] ?? [])

    // Handle createdAt with default value
    if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
      self.createdAt = timestamp.dateValue()
    } else if let defaultDate = defaults["createdAt"] as? Date {
      self.createdAt = defaultDate
    } else {
      self.createdAt = Date()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    // Don't encode id if it's nil
    if let id = id {
      try container.encode(id, forKey: .id)
    }

    try container.encode(username, forKey: .username)
    try container.encode(email, forKey: .email)
    try container.encode(fullName, forKey: .fullName)
    try container.encodeIfPresent(bio, forKey: .bio)
    try container.encode(isPrivate, forKey: .isPrivate)
    try container.encode(isDatingEnabled, forKey: .isDatingEnabled)
    try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
    try container.encodeIfPresent(location, forKey: .location)
    try container.encode(gender, forKey: .gender)
    try container.encode(interestedIn, forKey: .interestedIn)
    try container.encode(maxDistance, forKey: .maxDistance)
    try container.encode(ageRangeMin, forKey: .ageRangeMin)
    try container.encode(ageRangeMax, forKey: .ageRangeMax)
    try container.encode(followersCount, forKey: .followersCount)
    try container.encode(followingCount, forKey: .followingCount)
    try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    try container.encode(datingImages, forKey: .datingImages)
    try container.encode(username_lowercase, forKey: .username_lowercase)
    try container.encode(fullName_lowercase, forKey: .fullName_lowercase)
    try container.encode(birthday, forKey: .birthday)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: User, rhs: User) -> Bool {
    lhs.id == rhs.id
  }
}

// Since DocumentID isn't Sendable, we need to implement Sendable manually
extension User: @unchecked Sendable {
  // All properties are either value types or optional String,
  // which are all safe for concurrent access
}

extension CodingUserInfoKey {
  static let decodingDefaultsKey = CodingUserInfoKey(rawValue: "decodingDefaults")!
}
