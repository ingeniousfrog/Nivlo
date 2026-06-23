import Foundation
import NivloImaging
import Testing

@Suite("External process runner")
struct ExternalProcessRunnerTests {
  @Test("reports a missing external tool")
  func missingExecutable() async {
    await #expect(throws: ExternalProcessError.self) {
      _ = try await ExternalProcessRunner().run(
        ExternalProcessRequest(
          executable: URL(filePath: "/tmp/nivlo-does-not-exist")
        )
      )
    }
  }

  @Test("reports a real nonzero external tool exit")
  func nonzeroExit() async {
    await #expect(throws: ExternalProcessError.self) {
      _ = try await ExternalProcessRunner().run(
        ExternalProcessRequest(executable: URL(filePath: "/usr/bin/false"))
      )
    }
  }
}
