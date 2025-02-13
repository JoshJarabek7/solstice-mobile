import FirebaseFirestore
import SwiftUI

struct UserAvatar: View {
  let user: User
  var size: CGFloat = 60

  var body: some View {
    AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      Image(systemName: "person.circle.fill")
        .resizable()
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

#Preview {
  UserAvatar(
    user: User(
      username: "preview",
      email: "preview@example.com",
      fullName: "Preview User",
      bio: "Preview bio",
      isPrivate: false,
      isDatingEnabled: false,
      profileImageURL: nil,
      location: GeoPoint(latitude: 0, longitude: 0),
      gender: .other,
      interestedIn: [.other],
      maxDistance: 50,
      ageRangeMin: 18,
      ageRangeMax: 100,
      followersCount: 0,
      followingCount: 0,
      createdAt: Date(),
      datingImages: []
    )
  )
}
