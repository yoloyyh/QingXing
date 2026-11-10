import Foundation
import HeathyCore

struct RestEscalationTests {
    private let start = Date(timeIntervalSince1970: 4_000)
    private func engine() -> ReminderEngine { let engine = ReminderEngine(); engine.restInterval = 2; return engine }
    private func work(_ engine: ReminderEngine, through second: Int) {
        for index in 0...second { _ = engine.tick(at: start.addingTimeInterval(Double(index)), working: true) }
    }

    func testRestReminderEscalatesOnceAtThreeAndTenMinutes() {
        let engine = engine()
        var changes: [(Int, RestReminderLevel)] = []
        for second in 0...610 {
            let time = start.addingTimeInterval(Double(second))
            if engine.tick(at: time, working: true) == [.reminder(.rest)] {
                changes.append((second, engine.restReminderLevel(at: time)))
            }
        }
        expect(changes.map { $0.0 } == [2, 182, 602])
        expect(changes.map { $0.1 } == [.due, .overdue, .urgent])
    }

    func testRestSnoozeWaitsFiveMinutesAndReturnsAtCurrentLevel() {
        let engine = engine()
        work(engine, through: 182)
        engine.snoozeRest(at: start.addingTimeInterval(182))
        expect(engine.restReminderLevel(at: start.addingTimeInterval(183)) == .none)
        for second in 183..<482 {
            expect(engine.tick(at: start.addingTimeInterval(Double(second)), working: true).isEmpty)
        }
        expect(engine.tick(at: start.addingTimeInterval(482), working: true) == [.reminder(.rest)])
        expect(engine.restReminderLevel(at: start.addingTimeInterval(482)) == .overdue)
    }

    func testStartingRestClearsUrgencyAndEarlyReturnCanRemindAgain() {
        let engine = engine()
        work(engine, through: 182)
        engine.beginRest(at: start.addingTimeInterval(182))
        expect(engine.restReminderLevel(at: start.addingTimeInterval(183)) == .none)
        engine.cancelRest()
        expect(engine.tick(at: start.addingTimeInterval(184), working: true) == [.reminder(.rest)])
        expect(engine.restReminderLevel(at: start.addingTimeInterval(184)) == .overdue)
    }

    func testCompletedRestClearsEscalationAndRewardsOnce() {
        let engine = engine()
        engine.restDuration = 120
        work(engine, through: 602)
        engine.beginRest(at: start.addingTimeInterval(602))
        expect(engine.finishRest(at: start.addingTimeInterval(722)) == [.rested])
        expect(engine.workDuration == 0 && engine.restReminderLevel(at: start.addingTimeInterval(722)) == .none)
        expect(engine.finishRest(at: start.addingTimeInterval(723)).isEmpty)
    }

    func testRearmingRestPreservesTheSnoozeAndWorkDuration() {
        let engine = engine()
        work(engine, through: 602)
        engine.rearmRestReminder()
        expect(engine.workDuration == 602)
        expect(engine.tick(at: start.addingTimeInterval(603), working: true) == [.reminder(.rest)])
        engine.snoozeRest(at: start.addingTimeInterval(603))
        engine.rearmRestReminder()
        expect(engine.tick(at: start.addingTimeInterval(604), working: true).isEmpty)
    }

    func testClockGapCannotEscalateAnIgnoredRestReminder() {
        let engine = engine()
        work(engine, through: 2)
        expect(engine.tick(at: start.addingTimeInterval(3_602), working: true).isEmpty)
        expect(engine.workDuration == 2 && engine.restReminderLevel(at: start.addingTimeInterval(3_602)) == .due)
    }

    func testRestSnoozeDoesNotSuppressPostureOrDistanceAnalysis() {
        let engine = engine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "camera")
        engine.snoozeRest(at: start)
        for second in 0..<3 { _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))) }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(3)) == [.reminder(.distance)])
    }
}
