extension MessageMetadata {
  func asDictionary() -> [String: Any] {
    var dict: [String: Any] = [:]
    if let videoId = videoId {
      dict["videoId"] = videoId
    }
    if let videoThumbnail = videoThumbnail {
      dict["videoThumbnail"] = videoThumbnail
    }
    if let videoCaption = videoCaption {
      dict["videoCaption"] = videoCaption
    }
    if let profileUsername = profileUsername {
      dict["profileUsername"] = profileUsername
    }
    if let profileFullName = profileFullName {
      dict["profileFullName"] = profileFullName
    }
    if let profileBio = profileBio {
      dict["profileBio"] = profileBio
    }
    if let profileImage = profileImage {
      dict["profileImage"] = profileImage
    }
    return dict
  }
}
