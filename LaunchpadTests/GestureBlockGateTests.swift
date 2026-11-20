import Testing

@testable import Launchpad

struct GestureBlockGateTests {
    @Test
    func changeWaitsWhileTheTrackpadIsTouched() {
        var gate = GestureBlockGate()

        #expect(gate.request(true, contactsActive: true) == nil)
        #expect(gate.isDeferred)
        #expect(!gate.applied)
    }

    @Test
    func aNewContactSequenceSettlesTheWaitingChange() {
        var gate = GestureBlockGate()
        _ = gate.request(true, contactsActive: true)

        // Blocking at the first frame of the next sequence keeps that whole
        // sequence away from the Dock instead of cutting it in half.
        #expect(gate.applyPendingChange() == true)
        #expect(gate.applied)
        #expect(!gate.isDeferred)
        #expect(gate.applyPendingChange() == nil)
    }

    @Test
    func aClearTrackpadAppliesTheChangeRightAway() {
        var gate = GestureBlockGate()

        #expect(gate.request(true, contactsActive: false) == true)
        #expect(gate.applied)
        #expect(!gate.isDeferred)

        #expect(gate.request(false, contactsActive: false) == false)
        #expect(!gate.applied)
    }

    @Test
    func releasingWaitsForTheBoundaryToo() {
        var gate = GestureBlockGate(applied: true)

        #expect(gate.request(false, contactsActive: true) == nil)
        #expect(gate.isDeferred)
        #expect(gate.applied)

        #expect(gate.applyPendingChange() == false)
        #expect(!gate.applied)
    }

    @Test
    func closingAgainCancelsAPendingEnable() {
        var gate = GestureBlockGate()
        _ = gate.request(true, contactsActive: true)

        // The panel was hidden again before the fingers lifted: there is
        // nothing left to do, and the applied state already matches.
        #expect(gate.request(false, contactsActive: true) == nil)
        #expect(!gate.isDeferred)
        #expect(gate.applyPendingChange() == nil)
        #expect(!gate.applied)
    }

    @Test
    func aRequestForTheAppliedStateIsANoOp() {
        var gate = GestureBlockGate(applied: true)

        #expect(gate.request(true, contactsActive: true) == nil)
        #expect(gate.request(true, contactsActive: false) == nil)
        #expect(!gate.isDeferred)
        #expect(gate.applied)
    }
}
