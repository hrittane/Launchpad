import Foundation
import Testing

@testable import Launchpad

struct IconWiggleTests {
    @Test
    func motionStaysInTheTunedRanges() {
        for index in 0..<60 {
            let motion = IconWiggle.motion(seed: Double(index))
            #expect(motion.period >= 0.24 && motion.period <= 0.30)
            #expect(motion.amplitude >= 1.8 && motion.amplitude <= 2.2)
            // Pivot near the top: the bottom edge must travel more than the
            // top, which is what makes it a wobble instead of a spin.
            #expect(motion.anchor.y >= 0.06 && motion.anchor.y <= 0.14)
            #expect(motion.bounce > 0 && motion.bounce <= 1.1)
        }
    }

    @Test
    func neighboursDoNotShareAPhase() {
        let phases = (0..<8).map { IconWiggle.motion(seed: Double($0)).phase }
        for left in phases.indices {
            for right in phases.indices where right > left {
                #expect(abs(phases[left] - phases[right]) > 0.01)
            }
        }
    }

    @Test
    func sameSeedProducesTheSameMotion() {
        let first = IconWiggle.motion(seed: 12)
        let second = IconWiggle.motion(seed: 12)
        #expect(first.period == second.period)
        #expect(first.amplitude == second.amplitude)
        #expect(first.anchor == second.anchor)
        #expect(first.phase == second.phase)
        #expect(first.bouncePeriod == second.bouncePeriod)
        #expect(first.bouncePhase == second.bouncePhase)
        #expect(first.bounce == second.bounce)
    }

    @Test
    func angleReachesTheAmplitudeAndSwingsBothWays() {
        let motion = IconWiggle.motion(seed: 7)
        var highest = 0.0
        var lowest = 0.0
        let steps = Int(motion.period * 2000)
        for step in 0...steps {
            let date = Date(timeIntervalSinceReferenceDate: Double(step) / 2000)
            let angle = IconWiggle.angle(at: date, motion: motion)
            highest = max(highest, angle)
            lowest = min(lowest, angle)
        }
        #expect(abs(highest - motion.amplitude) < 0.01)
        #expect(abs(lowest + motion.amplitude) < 0.01)
    }

    @Test
    func cycleIsFasterThanTheOldCentredWobble() {
        // The first shipped wobble ran at 0.30–0.42 s per cycle; the iOS
        // reference is closer to 0.28 s, so every slot must now be quicker.
        for index in 0..<60 {
            #expect(IconWiggle.motion(seed: Double(index)).period < 0.30)
        }
    }
}
