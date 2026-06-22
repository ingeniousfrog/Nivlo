import NivloDomain
import Testing

@Suite("Library refresh interval")
struct LibraryRefreshIntervalTests {
  @Test("refresh choices map to scheduler durations")
  func schedulerDurations() {
    #expect(LibraryRefreshInterval.off.seconds == nil)
    #expect(LibraryRefreshInterval.fiveMinutes.seconds == 300)
    #expect(LibraryRefreshInterval.fifteenMinutes.seconds == 900)
    #expect(LibraryRefreshInterval.thirtyMinutes.seconds == 1_800)
    #expect(LibraryRefreshInterval.hourly.seconds == 3_600)
  }
}
