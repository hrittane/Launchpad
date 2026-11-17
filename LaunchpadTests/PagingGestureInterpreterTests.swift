import CoreGraphics
import Testing

@testable import Launchpad

struct PagingGestureInterpreterTests {
    private func swipe(_ interpreter: inout PagingGestureInterpreter, dx: [CGFloat]) -> [Int] {
        var steps: [Int] = []
        for (index, value) in dx.enumerated() {
            let phase: PagingGestureInterpreter.Phase = index == 0 ? .began : .changed
            steps.append(interpreter.consume(deltaX: value, deltaY: 0, isPrecise: true, phase: phase))
        }
        steps.append(interpreter.consume(deltaX: 0, deltaY: 0, isPrecise: true, phase: .ended))
        return steps
    }
    @Test
    func leftSwipeTurnsToNextPageOnRelease() {
        var interpreter = PagingGestureInterpreter()
        let steps = swipe(&interpreter, dx: [-20, -20, -20])

        #expect(steps.dropLast().allSatisfy { $0 == 0 })
        #expect(steps.last == 1)
    }

    @Test
    func rightSwipeTurnsToPreviousPage() {
        var interpreter = PagingGestureInterpreter()
        let steps = swipe(&interpreter, dx: [20, 25, 20])

        #expect(steps.last == -1)
    }

    @Test
    func shortSwipeDoesNotTurn() {
        var interpreter = PagingGestureInterpreter()
        let steps = swipe(&interpreter, dx: [-10, -10])

        #expect(steps.allSatisfy { $0 == 0 })
    }

    @Test
    func verticalScrollIsIgnored() {
        var interpreter = PagingGestureInterpreter()
        _ = interpreter.consume(deltaX: 5, deltaY: 60, isPrecise: true, phase: .began)
        _ = interpreter.consume(deltaX: 5, deltaY: 80, isPrecise: true, phase: .changed)
        let step = interpreter.consume(deltaX: 0, deltaY: 0, isPrecise: true, phase: .ended)

        #expect(step == 0)
    }

    @Test
    func cancelledGestureStillTurnsThePage() {
        var interpreter = PagingGestureInterpreter()
        _ = interpreter.consume(deltaX: -30, deltaY: 0, isPrecise: true, phase: .began)
        _ = interpreter.consume(deltaX: -30, deltaY: 0, isPrecise: true, phase: .changed)
        let step = interpreter.consume(deltaX: 0, deltaY: 0, isPrecise: true, phase: .cancelled)

        #expect(step == 1)
    }

    @Test
    func wheelAccumulatesSmallDeltas() {
        var interpreter = PagingGestureInterpreter()
        var steps: [Int] = []
        for _ in 0..<3 {
            steps.append(
                interpreter.consume(deltaX: -2, deltaY: 0, isPrecise: false, phase: .other)
            )
        }

        #expect(steps == [0, 0, 1])
    }

    @Test
    func wheelIgnoresVerticalDeltas() {
        var interpreter = PagingGestureInterpreter()
        var steps: [Int] = []
        for _ in 0..<5 {
            steps.append(
                interpreter.consume(deltaX: -1, deltaY: 4, isPrecise: false, phase: .other)
            )
        }

        #expect(steps.allSatisfy { $0 == 0 })
    }
}
