import Foundation
import HeathyCore

struct RestScheduleTests {
    private let start = Date(timeIntervalSince1970: 6_000)

    func testDefaultRestNeedsFiveMinutesAndConfirmation() {
        let engine = ReminderEngine()
        engine.beginRest(at: start)
        expect(engine.restRemaining(at: start) == 300)
        expect(engine.finishRest(at: start.addingTimeInterval(120)).isEmpty)
        expect(engine.restRemaining(at: start.addingTimeInterval(299)) == 1)
        expect(engine.finishRest(at: start.addingTimeInterval(299)).isEmpty)
        expect(engine.finishRest(at: start.addingTimeInterval(300)) == [.rested])
        expect(engine.finishRest(at: start.addingTimeInterval(301)).isEmpty)
    }

    func testSelectedRestDurationControlsTheCompletionBoundary() {
        for duration: TimeInterval in [60, 600, 1_200] {
            let engine = ReminderEngine()
            engine.restDuration = duration
            engine.beginRest(at: start)
            expect(engine.restRemaining(at: start) == duration)
            expect(engine.finishRest(at: start.addingTimeInterval(duration - 1)).isEmpty)
            expect(engine.restRemaining(at: start.addingTimeInterval(duration)) == 0)
            expect(engine.finishRest(at: start.addingTimeInterval(duration)) == [.rested])
            expect(engine.finishRest(at: start.addingTimeInterval(duration + 1)).isEmpty)
        }
    }

    func testChangingDurationOnlyAffectsTheNextRest() {
        for (original, next): (TimeInterval, TimeInterval) in [(600, 60), (60, 600)] {
            let engine = ReminderEngine()
            engine.restDuration = original
            engine.beginRest(at: start)
            engine.restDuration = next
            expect(engine.restRemaining(at: start.addingTimeInterval(30)) == original - 30)
            expect(engine.finishRest(at: start.addingTimeInterval(original - 1)).isEmpty)
            expect(engine.finishRest(at: start.addingTimeInterval(original)) == [.rested])
            let again = start.addingTimeInterval(original + 1)
            engine.beginRest(at: again)
            expect(engine.restRemaining(at: again) == next)
        }
    }

    func testCancelingCustomRestPreservesWorkAndNextRestUsesNewTarget() {
        let engine = ReminderEngine()
        for second in 0...10 { _ = engine.tick(at: start.addingTimeInterval(Double(second)), working: true) }
        engine.restDuration = 600
        engine.beginRest(at: start.addingTimeInterval(10))
        engine.restDuration = 300
        engine.cancelRest()
        expect(engine.workDuration == 10 && engine.restRemaining(at: start.addingTimeInterval(11)) == 0)
        expect(engine.finishRest(at: start.addingTimeInterval(1_000)).isEmpty)
        engine.beginRest(at: start.addingTimeInterval(12))
        expect(engine.restRemaining(at: start.addingTimeInterval(12)) == 300)
        expect(engine.finishRest(at: start.addingTimeInterval(312)) == [.rested])
        expect(engine.workDuration == 0)
    }
}
