import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@preconcurrency import FirebaseFirestoreInternal

@Observable
@MainActor
final class FeedViewModel {
    var videos: [Video] = []
    var isLoading = false
    var hasMoreVideos = true
    var errorMessage: String?
    
    let db = Firestore.firestore()
    let limit = 5
    
    private var lastDocument: DocumentSnapshot?
    private var currentFeedType: FeedType = .forYou
    private var isLoadingMore = false
    private var seenVideoIds = Set<String>()
    
    var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private func handleError(_ error: Error) {
        if let nsError = error as? NSError {
            // Check if it's a Firestore index error
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.failedPrecondition.rawValue,
               nsError.localizedDescription.contains("index") {
                // Log to console for clickable index creation link
                print("Firestore Index Error: \(error.localizedDescription)")
                errorMessage = "Unable to load feed. Please try again later."
            } else {
                // Handle other errors normally
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshFeed(type: FeedType) async {
        currentFeedType = type
        videos = []
        lastDocument = nil
        seenVideoIds.removeAll()
        hasMoreVideos = true
        await fetchMoreVideos()
    }
    
    func fetchMoreVideos() async {
        guard !isLoadingMore && hasMoreVideos else { return }
        isLoadingMore = true
        isLoading = true
        
        do {
            var query: Query = db.collection("videos")
            
            switch currentFeedType {
            case .following:
                guard let currentUserId = currentUserId else {
                    isLoadingMore = false
                    isLoading = false
                    return
                }
                
                let followingSnapshot = try await db.collection("users")
                    .document(currentUserId)
                    .collection("following")
                    .getDocuments()
                
                let followingIds = followingSnapshot.documents.map { $0.documentID }
                let allIds = followingIds + [currentUserId]
                
                query = query.whereField("creatorId", in: allIds)
                    .order(by: "createdAt", descending: true)
                
            case .forYou:
                query = query.order(by: "engagementScore", descending: true)
                    .order(by: "createdAt", descending: true)
            }
            
            query = query.limit(to: limit)
            if let last = lastDocument {
                query = query.start(afterDocument: last)
            }
            
            let snapshot = try await query.getDocuments()
            
            let newVideos = snapshot.documents.compactMap { doc -> Video? in
                guard let video = try? doc.data(as: Video.self),
                      let videoId = video.id,
                      !seenVideoIds.contains(videoId) else {
                    return nil
                }
                return video
            }
            
            for video in newVideos {
                if let videoId = video.id {
                    seenVideoIds.insert(videoId)
                }
            }
            
            videos.append(contentsOf: newVideos)
            lastDocument = snapshot.documents.last
            hasMoreVideos = !newVideos.isEmpty && newVideos.count == limit
            isLoadingMore = false
            isLoading = false
            errorMessage = nil
            
        } catch {
            handleError(error)
            isLoadingMore = false
            isLoading = false
        }
    }
    
    func videoViewed(at index: Int) {
        guard index < videos.count else { return }
        let video = videos[index]
        guard let videoId = video.id else { return }
        
        // Calculate score synchronously before async work
        let score = calculateEngagementScore(video)
        
        Task {
            do {
                try await db.collection("videos").document(videoId).updateData([
                    "viewCount": FieldValue.increment(Int64(1)),
                    "engagementScore": score,
                ])
            } catch {
                print("Error updating video stats: \(error)")
            }
        }
    }
    
    private func calculateEngagementScore(_ video: Video) -> Double {
        let viewWeight = 1.0
        let likeWeight = 2.0
        let commentWeight = 3.0
        let shareWeight = 4.0
        let recencyWeight = 5.0
        
        let baseScore = Double(video.viewCount) * viewWeight +
                       Double(video.likes) * likeWeight +
                       Double(video.comments) * commentWeight +
                       Double(video.shares) * shareWeight
        
        let hoursSinceCreation = Date().timeIntervalSince(video.createdAt) / 3600
        let recencyBoost = max(0, 168 - hoursSinceCreation) / 168
        
        return baseScore * (1 + recencyBoost * recencyWeight)
    }
}