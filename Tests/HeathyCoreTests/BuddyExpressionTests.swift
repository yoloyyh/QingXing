import HeathyCore

struct BuddyExpressionTests {
    func testDistancePoseAndRestHaveDistinctExpressions() {
        expect(BuddyExpression.reminder(.distance) == .tooClose)
        expect(BuddyExpression.reminder(.posture) == .posture)
        expect(BuddyExpression.reminder(.rest) == .restDue)
    }
    func testHeadDownAndTiltKeepTheirSpecificCause() {
        expect(BuddyExpression.reminder(.posture, change: .headDown) == .headDown)
        expect(BuddyExpression.reminder(.posture, change: .headTilt) == .headTilt)
        expect(BuddyExpression.result(distanceWarning: false, posture: .changed(.headDown)) == .headDown)
        expect(BuddyExpression.result(distanceWarning: false, posture: .changed(.headTilt)) == .headTilt)
    }
    func testDistanceTakesPriorityOverPoseAndUnknownPoseDoesNotClaimAProblem() {
        expect(BuddyExpression.result(distanceWarning: true, posture: .changed(.headDown)) == .tooClose)
        expect(BuddyExpression.result(distanceWarning: true, posture: .unavailable) == .tooClose)
        expect(BuddyExpression.result(distanceWarning: false, posture: .unavailable) == .calm)
        expect(BuddyExpression.result(distanceWarning: false, posture: .needsCalibration) == .calm)
        expect(BuddyExpression.result(distanceWarning: false, posture: .aligned) == .calm)
    }
    func testShoulderAndGeneralHeadChangesDoNotInventForwardNeckDiagnosis() {
        for change: PostureChange in [.forward, .headPosition, .shoulders, .headAngle] {
            expect(BuddyExpression.reminder(.posture, change: change) == .posture)
        }
    }
}
