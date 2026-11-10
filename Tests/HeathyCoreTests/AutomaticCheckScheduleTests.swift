import Foundation
import HeathyCore

struct AutomaticCheckScheduleTests {
    private let start = Date(timeIntervalSince1970: 9_000)
    func testEnabledBackgroundScheduleWaitsThirtyMinutes() {
        expect(AutomaticCheckSchedule.restoredCheck(at: start, previouslyEnabled: true, automatic: true, authorized: true, hasReference: true) == start.addingTimeInterval(1_800))
    }
    func testFirstLaunchCannotEnableCameraFromDefaultAutomaticSwitch() {
        expect(AutomaticCheckSchedule.restoredCheck(at: start, previouslyEnabled: false, automatic: true, authorized: true, hasReference: true) == nil)
    }
    func testMissingPermissionReferenceOrAutomaticChoiceCannotSchedule() {
        expect(AutomaticCheckSchedule.restoredCheck(at: start, previouslyEnabled: true, automatic: true, authorized: false, hasReference: true) == nil)
        expect(AutomaticCheckSchedule.restoredCheck(at: start, previouslyEnabled: true, automatic: true, authorized: true, hasReference: false) == nil)
        expect(AutomaticCheckSchedule.restoredCheck(at: start, previouslyEnabled: true, automatic: false, authorized: true, hasReference: true) == nil)
    }
    func testRestartSchedulesFromNowWithoutCatchingUpMissedScans() {
        let later = start.addingTimeInterval(86_400)
        expect(AutomaticCheckSchedule.restoredCheck(at: later, previouslyEnabled: true, automatic: true, authorized: true, hasReference: true) == later.addingTimeInterval(1_800))
    }
}
