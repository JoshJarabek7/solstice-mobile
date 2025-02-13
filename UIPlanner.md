# Solstice UI/UX Planning Document

## Core Navigation Structure
- Bottom Tab Bar (5 items):
  1. Home (Feed)
  2. Discover (Search + Explore + Dating)
  3. Create (+)
  4. Messages (DMs + Notifications)
  5. Profile

## Feed View (Home Tab)
### Main Features
- Full-screen immersive video player (max 2 minutes)
- Vertical swipe navigation with snap-to-screen
- Following/For You toggle at top
- Floating action buttons on right side:
  - Creator profile picture (with link)
  - Like counter
  - Comments counter
  - Share button (DM only + Download)
  - Bookmark button
- Bottom overlay with:
  - Creator username
  - Video caption
  - Hashtags
  - Background gradient for readability
- Non-intrusive progress bar at bottom
  - Draggable for seeking
  - Shows video progress
- Real-time counter for likes, comments, and views

### Comments System
- Comment sorting options:
  - Top (most liked)
  - Newest
  - Following first (always)
    - Followed users' comments appear at top
    - Sorted within by selected sort method
- Single-level replies
  - One level deep only
  - No nested threading
- Mention system:
  - Username autocomplete (@username)
  - Mentions in:
    - Comments
    - Comment replies
    - Video captions
  - Real-time mention suggestions
    - Priority order:
      1. Following
      2. Followers
      3. Recent interactions
      4. Other users
- Comment actions:
  - Like/unlike
  - Reply
  - Report
  - Delete (own comments only)
- Deep linking:
  - From notifications to specific comments
  - From notifications to specific replies
  - From mentions to source content

### Technical Considerations
- Edge-to-edge video rendering
- Smart video fitting:
  - Portrait: Snap vertically
  - Landscape: Snap horizontally
  - Dynamic padding color based on video content
- Landscape mode support with rotation
- Video management:
  - Store video ratio in database (landscape/portrait/square)
  - Only one video playing at a time
  - Remember playback position for each video
  - Autoplay next video on completion
  - Cache previous videos for quick backwards navigation
  - Prioritized loading:
    1. Current video
    2. Next video
    3. Subsequent videos (limited concurrent loads)

## Discover Tab
### Main Layout
- Segmented control at top:
  1. Explore
  2. Dating (if enabled)
  3. Search

### Explore Section
- Trending hashtags horizontal scroll
- Recommended users section
- Trending videos grid:
  - Based on interaction rate
  - Exponential decay by recency
- Category-based content exploration
- Location-based content suggestions

### Dating Section
- Only visible if dating is enabled for user
- Card-style interface for dating profiles
- Smart recommendation algorithm based on:
  - Similar video likes
  - Following patterns
  - Interaction history
  - Geographic proximity
  - Mutual interests (derived from content interaction)
- Dating filters:
  - Gender preferences (6-month change restriction)
  - Distance range
  - Age range
  - Active status
- Swiping interface:
  - Right to like
  - Left to pass
  - Up to super-like
  - Profile preview with key info
  - Expandable for full profile view

### Search Section
- Universal search bar for:
  - Users
  - Videos
  - Hashtags
  - Locations
- Real-time search suggestions
- Recent searches
- Trending searches
- Filter options:
  - Content type
  - Date range
  - Popularity
  - Verification status

## Create Tab (+)
### Video Creation
- Hold-to-record functionality:
  - Dynamic progress bar (0-2 minutes)
  - Release to stop recording
- Camera view with:
  - Flip camera option
  - Basic filters
  - Timer options
  - Upload from gallery
- Simple editing features:
  - Trim video
  - Add caption
  - Add hashtags
  - Set thumbnail
  - Tag other users

## Messages Tab
### Direct Messages
- Two-tab structure:
  - All Messages
  - Dating Matches
- Unread indicators per tab
- Match-to-DM conversion:
  - Mutual opt-in required
  - Match indicator in regular DMs
- Share via DM:
  - Recent contacts
  - Smart user search:
    1. Following (highest weight)
    2. Followers (medium weight)
    3. Geographic proximity (lower weight)
  - Full-text search on username/full name

## Profile Tab
### Main Profile
- Profile picture
- Bio
- Stats (following, followers, likes)
- Education info (optional)
- Video sections:
  - Posted videos
  - Tagged videos (respecting privacy settings)
  - Liked videos
- Settings access
- Dating profile toggle (if enabled)

### Dating Profile Integration
- Up to 5 dating profile images
- Like/Dislike buttons (when both users have dating enabled)
- Extended bio for dating
- Education info
- Mutual follows count and viewer
- Shared content showcase:
  - Mutual liked videos
  - Common follows
- Visibility rules:
  - Only visible if both users have dating enabled
  - Must match each other's interest filters
  - Private profiles require following

## Common UI Elements
### Video Player
- Full screen by default
- Double tap to like
- Swipe gestures
- Progress bar with seek functionality
- Volume control
- Rotation support

### Action Buttons
- Consistent styling
- Haptic feedback
- Animation on interaction
- Badge indicators for notifications

### Navigation
- Gesture-based navigation
- Smooth transitions
- Loading states
- Error handling

### Dating Card Interface
- Full-screen swipeable cards
- Profile preview with:
  - Main photo
  - Name and age
  - Distance
  - Basic info preview
- Expandable for full profile
- Quick action buttons:
  - Like/Dislike
  - Super Like
  - Profile expansion
- Mutual content indicators
- Shared interests visualization
- Match percentage based on content similarity

## Dating-Specific Features
### Profile Viewing
- Like/Dislike from profile
- Match indicators
- Distance information
- Mutual content/connections display
- Education info

### Matching System
- Bilateral opt-in required
- Filter compliance check
- Geographic radius check
- Match notification:
  - Modal popup with confetti
  - Profile picture display
  - Basic info (name, age, distance)
  - Auto-creates dating chat
- Gender preference restrictions:
  - 6-month change cooldown
  - Prevents abuse/unwanted viewing

## Privacy Considerations
- Private account support
- Follow request system:
  - Request notifications
  - Acceptance notifications
- Content visibility rules
- Blocked users management
- Dating profile visibility control:
  - Mutual opt-in required
  - Filter alignment check
  - Following status check for private accounts

## Technical Requirements
- Firebase integration
- Real-time updates
- Efficient data caching
- Video transcoding
- Geolocation services
- Push notification support
- Smart notification grouping:
  - Group by instance not type
  - E.g., "John, Cindy, and 265 others liked your post"
  - Deep linking to relevant content

## Notifications
### Comment Notifications
- New comment on your video
- Reply to your comment
- Mention in:
  - Video caption
  - Comment
  - Comment reply
- Deep linking to exact content:
  - Direct to specific comment
  - Direct to specific reply
  - Scroll to relevant mention
- Grouping:
  - Group by content instance
  - E.g., "John, Sarah, and 5 others commented on your video"
  - E.g., "Alex, Maria, and 3 others mentioned you in comments"
