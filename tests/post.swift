// Sends one test command to a running Menu Bar Guard (no window, no focus).
import Foundation
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.solomon.MenuBarGuard.test"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
