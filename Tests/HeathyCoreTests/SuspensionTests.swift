import HeathyCore

struct SuspensionTests {
    func testWakeCannotResumeCameraWhileScreenIsLocked() {
        var gate = SuspensionGate()
        gate.suspend(.screenLock)
        gate.suspend(.sleep)
        gate.resume(.sleep)
        expect(gate.isSuspended)
        gate.resume(.screenLock)
        expect(!gate.isSuspended)
    }
    func testDuplicateAndUnrelatedLifecycleEventsAreSafe() {
        var gate = SuspensionGate()
        gate.suspend(.screenLock)
        gate.suspend(.screenLock)
        gate.resume(.sleep)
        expect(gate.isSuspended)
        gate.resume(.screenLock)
        expect(!gate.isSuspended)
    }

}
