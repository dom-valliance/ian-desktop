import TestSupport
import Testing

@testable import Attention

@MainActor
private func makeWhisper(_ clock: ManualClock) -> Whisper {
  Whisper(sleep: { try await clock.sleep(for: $0) })
}

@Suite("The whisper")
@MainActor
struct WhisperTests {
  @Test("shows the title for eight seconds and then goes")
  func eightSeconds() async {
    let clock = ManualClock()
    let whisper = makeWhisper(clock)
    whisper.show("Reply to [PERSON]")
    #expect(whisper.title == "Reply to [PERSON]")

    await clock.waitForSleepers()
    await clock.advance(by: .seconds(7))
    #expect(whisper.title == "Reply to [PERSON]")
    await clock.advance(by: .seconds(1))
    #expect(await eventually { await MainActor.run { whisper.title == nil } })
  }

  @Test("a newer whisper replaces it and restarts the eight seconds")
  func replaced() async {
    let clock = ManualClock()
    let whisper = makeWhisper(clock)
    whisper.show("First")
    await clock.waitForSleepers()
    await clock.advance(by: .seconds(5))

    whisper.show("Second")
    #expect(whisper.title == "Second")
    await clock.waitForSleepers()
    await clock.advance(by: .seconds(5))
    // Ten seconds after the first, five after the second.
    #expect(whisper.title == "Second")
    await clock.advance(by: .seconds(3))
    #expect(await eventually { await MainActor.run { whisper.title == nil } })
  }

  @Test("hiding clears it at once")
  func hidden() {
    let whisper = Whisper(sleep: { _ in try await Task.sleep(for: .seconds(60)) })
    whisper.show("Anything")
    whisper.hide()
    #expect(whisper.title == nil)
  }
}
