import Foundation
import UserNotifications

/// Copy this file into an app-owned Notification Service Extension target.
/// The extension cannot be embedded by a Flutter plugin because its bundle ID,
/// signing, entitlements, and deployment target belong to the host app.
final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?

  private func finish(_ content: UNNotificationContent) {
    guard let contentHandler else { return }
    self.contentHandler = nil
    contentHandler(content)
  }

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      finish(request.content)
      return
    }
    bestAttemptContent = content

    guard
      let value = content.userInfo["image"] as? String,
      let remoteURL = URL(string: value)
    else {
      finish(content)
      return
    }

    URLSession.shared.downloadTask(with: remoteURL) { [weak self] temporaryURL, _, _ in
      guard let self else { return }
      defer { self.finish(content) }
      guard let temporaryURL else { return }
      let targetURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(remoteURL.lastPathComponent.isEmpty ? "attachment" : remoteURL.lastPathComponent)
      do {
        try? FileManager.default.removeItem(at: targetURL)
        try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
        content.attachments = [try UNNotificationAttachment(identifier: "image", url: targetURL)]
      } catch {
        // Deliver the original notification if the attachment is invalid.
      }
    }.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    if let bestAttemptContent {
      finish(bestAttemptContent)
    }
  }
}
