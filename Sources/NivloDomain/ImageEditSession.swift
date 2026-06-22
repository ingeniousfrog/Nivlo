public struct ImageEditSession: Sendable, Equatable {
  public let initialSnapshot: ImageEditSnapshot
  public private(set) var currentSnapshot: ImageEditSnapshot

  public init(initialSnapshot: ImageEditSnapshot = ImageEditSnapshot()) {
    self.initialSnapshot = initialSnapshot
    currentSnapshot = initialSnapshot
  }

  public var hasChanges: Bool {
    currentSnapshot != initialSnapshot
  }

  public mutating func replaceCurrent(with snapshot: ImageEditSnapshot) {
    currentSnapshot = snapshot
  }

  public mutating func update(
    _ transform: (inout ImageEditSnapshot) -> Void
  ) {
    var snapshot = currentSnapshot
    transform(&snapshot)
    currentSnapshot = snapshot
  }

  public mutating func revert() {
    currentSnapshot = initialSnapshot
  }
}
