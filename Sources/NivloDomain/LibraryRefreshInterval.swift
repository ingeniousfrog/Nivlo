public enum LibraryRefreshInterval: String, CaseIterable, Identifiable, Sendable {
  case off
  case fiveMinutes
  case fifteenMinutes
  case thirtyMinutes
  case hourly

  public var id: String { rawValue }

  public var seconds: UInt64? {
    switch self {
    case .off:
      nil
    case .fiveMinutes:
      5 * 60
    case .fifteenMinutes:
      15 * 60
    case .thirtyMinutes:
      30 * 60
    case .hourly:
      60 * 60
    }
  }
}
