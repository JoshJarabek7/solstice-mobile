//
//  solsticeApp.swift
//  solstice
//
//  Created by Woof on 2/7/25.
//

import FirebaseAnalytics
import FirebaseCore
import FirebaseInAppMessaging
import FirebaseMessaging
import SwiftUI
import UserNotifications

@main
struct SolsticeApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
  var fcmToken: String?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()

    // Configure Analytics
    Analytics.setAnalyticsCollectionEnabled(true)

    // Configure In-App Messaging
    InAppMessaging.inAppMessaging().automaticDataCollectionEnabled = true

    // Configure Push Notifications
    configureNotifications(application)

    return true
  }

  private func configureNotifications(_ application: UIApplication) {
    // Set notification delegates
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    // Request authorization
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    Task {
      do {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
          options: authOptions)
        if granted {
          await MainActor.run {
            application.registerForRemoteNotifications()
          }
        }
      } catch {
        print("Error requesting notification authorization: \(error)")
      }
    }
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("Failed to register for remote notifications: \(error)")
  }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
  // Handle notification when app is in foreground
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("Received notification in foreground: \(userInfo)")
    completionHandler([[.banner, .sound]])
  }

  // Handle notification tap
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("Handling notification response: \(userInfo)")
    completionHandler()
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  nonisolated func messaging(
    _ messaging: Messaging,
    didReceiveRegistrationToken fcmToken: String?
  ) {
    guard let token = fcmToken else { return }
    print("Firebase registration token: \(token)")

    Task { @MainActor in
      self.fcmToken = token
      NotificationCenter.default.post(
        name: Notification.Name("FCMToken"),
        object: nil,
        userInfo: ["token": token]
      )
    }
  }
}
