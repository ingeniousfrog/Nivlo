public struct ImageEditSession: Sendable, Equatable {
  public let initialSnapshot: ImageEditSnapshot
  public private(set) var currentSnapshot: ImageEditSnapshot
  private var undoSnapshots: [ImageEditSnapshot]
  private var redoSnapshots: [ImageEditSnapshot]
  private let historyLimit: Int

  public init(
    initialSnapshot: ImageEditSnapshot = ImageEditSnapshot(),
    historyLimit: Int = 100
  ) {
    self.initialSnapshot = initialSnapshot
    currentSnapshot = initialSnapshot
    undoSnapshots = []
    redoSnapshots = []
    self.historyLimit = max(1, historyLimit)
  }

  public var hasChanges: Bool {
    currentSnapshot != initialSnapshot
  }

  public var canUndo: Bool {
    !undoSnapshots.isEmpty
  }

  public var canRedo: Bool {
    !redoSnapshots.isEmpty
  }

  public mutating func replaceCurrent(with snapshot: ImageEditSnapshot) {
    guard snapshot != currentSnapshot else { return }
    recordUndoSnapshot()
    currentSnapshot = snapshot
    redoSnapshots.removeAll()
  }

  public mutating func update(
    _ transform: (inout ImageEditSnapshot) -> Void
  ) {
    var snapshot = currentSnapshot
    transform(&snapshot)
    replaceCurrent(with: snapshot)
  }

  public mutating func undo() {
    guard let snapshot = undoSnapshots.popLast() else { return }
    redoSnapshots.append(currentSnapshot)
    currentSnapshot = snapshot
  }

  public mutating func redo() {
    guard let snapshot = redoSnapshots.popLast() else { return }
    recordUndoSnapshot()
    currentSnapshot = snapshot
  }

  public mutating func revert() {
    replaceCurrent(with: initialSnapshot)
  }

  private mutating func recordUndoSnapshot() {
    undoSnapshots.append(currentSnapshot)
    if undoSnapshots.count > historyLimit {
      undoSnapshots.removeFirst(undoSnapshots.count - historyLimit)
    }
  }
}
