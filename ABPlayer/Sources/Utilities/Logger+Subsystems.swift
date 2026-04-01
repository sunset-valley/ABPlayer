import OSLog

extension Logger {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.ihugo.ABPlayer"

  static let audio = Logger(subsystem: subsystem, category: "audio")
  static let ui = Logger(subsystem: subsystem, category: "ui")
  static let data = Logger(subsystem: subsystem, category: "data")
  static let general = Logger(subsystem: subsystem, category: "general")
}
