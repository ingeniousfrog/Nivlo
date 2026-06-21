@preconcurrency import CoreServices
import Foundation
import NivloDomain

public protocol FileEventWatch: Sendable {
  func stop()
}

public protocol FileEventWatching: Sendable {
  func start(
    rootURL: URL,
    handler: @escaping ([FileSystemEvent]) -> Void
  ) throws -> any FileEventWatch
}

public enum FileEventWatcherError: Error, LocalizedError, Sendable {
  case couldNotCreateStream(URL)
  case invalidEventPayload

  public var errorDescription: String? {
    switch self {
    case .couldNotCreateStream(let url):
      "Could not start watching \(url.path)."
    case .invalidEventPayload:
      "macOS delivered an invalid file event payload."
    }
  }
}

public actor LibraryRootFileEventMonitor {
  private let watcher: any FileEventWatching
  private let scanner: any DirectoryScanning
  private let coalescer: FileEventCoalescer
  private let debounceNanoseconds: UInt64
  private var onDidScan: (@Sendable () async -> Void)?
  private var watches: [URL: any FileEventWatch] = [:]
  private var pendingEvents: [URL: [FileSystemEvent]] = [:]
  private var debounceTasks: [URL: Task<Void, Never>] = [:]

  public init(
    watcher: any FileEventWatching,
    scanner: any DirectoryScanning,
    coalescer: FileEventCoalescer = FileEventCoalescer(),
    debounceNanoseconds: UInt64 = 350_000_000,
    onDidScan: (@Sendable () async -> Void)? = nil
  ) {
    self.watcher = watcher
    self.scanner = scanner
    self.coalescer = coalescer
    self.debounceNanoseconds = debounceNanoseconds
    self.onDidScan = onDidScan
  }

  deinit {
    for task in debounceTasks.values {
      task.cancel()
    }
    for watch in watches.values {
      watch.stop()
    }
  }

  public func start(rootURLs: [URL]) async throws {
    let normalizedRoots = rootURLs.map(\.standardizedFileURL)
    let desiredRoots = Set(normalizedRoots)
    for root in watches.keys where !desiredRoots.contains(root) {
      watches[root]?.stop()
      watches[root] = nil
      pendingEvents[root] = nil
      debounceTasks[root]?.cancel()
      debounceTasks[root] = nil
    }

    for root in normalizedRoots where watches[root] == nil {
      watches[root] = try watcher.start(rootURL: root) { [weak self] events in
        Task {
          await self?.record(events, for: root)
        }
      }
    }
  }

  public func stop() {
    for watch in watches.values {
      watch.stop()
    }
    for task in debounceTasks.values {
      task.cancel()
    }
    watches = [:]
    pendingEvents = [:]
    debounceTasks = [:]
  }

  public func setDidScanHandler(_ handler: (@Sendable () async -> Void)?) {
    onDidScan = handler
  }

  private func record(_ events: [FileSystemEvent], for rootURL: URL) {
    pendingEvents[rootURL, default: []].append(contentsOf: events)
    debounceTasks[rootURL]?.cancel()
    let debounceNanoseconds = debounceNanoseconds
    debounceTasks[rootURL] = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: debounceNanoseconds)
        await self?.flush(rootURL)
      } catch {}
    }
  }

  private func flush(_ rootURL: URL) async {
    let events = pendingEvents[rootURL] ?? []
    pendingEvents[rootURL] = []
    guard !events.isEmpty else {
      return
    }

    let batch = coalescer.coalesce(events, libraryRoot: rootURL)
    do {
      if batch.requiresFullValidation {
        _ = try await scanner.scan(rootURL: rootURL)
      } else {
        for directory in batch.directories {
          _ = try await scanner.scan(scopeURL: directory, under: rootURL)
        }
      }
      await onDidScan?()
    } catch {
      pendingEvents[rootURL, default: []].append(
        FileSystemEvent(url: rootURL, requiresFullValidation: true)
      )
    }
  }
}

public final class FSEventsFileEventWatcher: FileEventWatching {
  public init() {}

  public func start(
    rootURL: URL,
    handler: @escaping ([FileSystemEvent]) -> Void
  ) throws -> any FileEventWatch {
    let callback: FSEventStreamCallback = {
      _,
      contextInfo,
      eventCount,
      eventPaths,
      eventFlags,
      _ in
      guard
        let contextInfo,
        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String],
        paths.count >= eventCount
      else {
        return
      }

      let box = Unmanaged<EventHandlerBox>
        .fromOpaque(contextInfo)
        .takeUnretainedValue()
      let flags = eventFlags
      let events = (0..<eventCount).map { index in
        FileSystemEvent(
          url: URL(filePath: paths[Int(index)]),
          requiresFullValidation:
            FSEventsFileEventWatcher.requiresFullValidation(flags[Int(index)])
        )
      }
      box.handler(events)
    }

    let box = EventHandlerBox(handler: handler)
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passRetained(box).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let flags =
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
      | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
      | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
    guard
      let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        [rootURL.standardizedFileURL.path] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.35,
        flags
      )
    else {
      Unmanaged.passUnretained(box).release()
      throw FileEventWatcherError.couldNotCreateStream(rootURL)
    }

    FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      Unmanaged.passUnretained(box).release()
      throw FileEventWatcherError.couldNotCreateStream(rootURL)
    }
    return FSEventsFileEventWatch(stream: stream, box: box)
  }

  private static func requiresFullValidation(
    _ flags: FSEventStreamEventFlags
  ) -> Bool {
    let validationFlags: [FSEventStreamEventFlags] = [
      FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
      FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
      FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
      FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
      FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
      FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
    ]
    return validationFlags.contains { flags & $0 != 0 }
  }
}

private final class EventHandlerBox: @unchecked Sendable {
  let handler: ([FileSystemEvent]) -> Void

  init(handler: @escaping ([FileSystemEvent]) -> Void) {
    self.handler = handler
  }
}

private final class FSEventsFileEventWatch: FileEventWatch, @unchecked Sendable {
  private let stream: FSEventStreamRef
  private let box: EventHandlerBox
  private let lock = NSLock()
  private var isStopped = false

  init(stream: FSEventStreamRef, box: EventHandlerBox) {
    self.stream = stream
    self.box = box
  }

  deinit {
    stop()
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }
    guard !isStopped else {
      return
    }
    isStopped = true
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    Unmanaged.passUnretained(box).release()
  }
}
