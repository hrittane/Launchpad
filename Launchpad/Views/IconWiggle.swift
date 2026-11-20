import Foundation
import SwiftUI

/// The edit-mode jiggle, modelled on the iOS Home Screen.
///
/// The iOS effect is a small rotation with four properties that matter:
///
/// - it swings both ways by roughly ±2°, not a one-sided tilt;
/// - one swing takes about 0.13–0.15 s with an ease-in on the way out and an
///   ease-out on the way back (a sine is exactly that shape);
/// - the pivot sits above the icon's centre, so the bottom edge travels
///   further than the top. That off-centre swing is what makes it read as a
///   wobble instead of a metronome;
/// - no two neighbouring icons share a period, amplitude, pivot or phase.
///
/// A very small vertical bounce runs on its own, slower clock. Everything is
/// a pure function of the timeline date, so leaving edit mode returns every
/// icon to 0° with no animation left running.
enum IconWiggle {
    /// The timeline refresh rate. 60 Hz keeps a 0.24 s swing smooth.
    static let framesPerSecond: Double = 60

    struct Motion {
        /// Seconds for one full left-right cycle (two swings).
        let period: Double
        /// Peak rotation in degrees.
        let amplitude: Double
        /// Pivot of the rotation inside the icon's bounds.
        let anchor: UnitPoint
        /// Offset into the cycle, in turns (0..<1).
        let phase: Double
        /// Seconds for one full bounce cycle.
        let bouncePeriod: Double
        /// Offset into the bounce cycle, in turns (0..<1).
        let bouncePhase: Double
        /// Peak vertical travel in points.
        let bounce: CGFloat
    }

    /// Deterministic per-icon variation, the Swift equivalent of the CSS
    /// `nth-child` variants plus inline negative delays used by recreations
    /// of the Home Screen effect.
    static func motion(seed: Double) -> Motion {
        Motion(
            period: 0.24 + unit(seed, 1) * 0.06,
            amplitude: 1.8 + unit(seed, 2) * 0.4,
            anchor: UnitPoint(
                x: 0.36 + unit(seed, 3) * 0.28,
                y: 0.06 + unit(seed, 4) * 0.08
            ),
            phase: unit(seed, 5),
            bouncePeriod: 0.30 + unit(seed, 6) * 0.12,
            bouncePhase: unit(seed, 7),
            bounce: 0.5 + unit(seed, 8) * 0.6
        )
    }

    static func angle(at date: Date, motion: Motion) -> Double {
        let turns = date.timeIntervalSinceReferenceDate / motion.period + motion.phase
        return sin(turns * 2 * .pi) * motion.amplitude
    }

    static func offset(at date: Date, motion: Motion) -> CGFloat {
        let turns = date.timeIntervalSinceReferenceDate / motion.bouncePeriod
            + motion.bouncePhase
        return sin(turns * 2 * .pi) * motion.bounce
    }

    /// Stable pseudo-random value in 0..<1 for a seed and a salt. A
    /// SplitMix64-style avalanche keeps adjacent slots from sharing a phase
    /// (a plain `sin(seed · k)` hash left the first icons in lockstep).
    private static func unit(_ seed: Double, _ salt: UInt64) -> Double {
        var x = seed.bitPattern &* 0x9E37_79B9_7F4A_7C15
        x ^= salt &* 0xD1B5_4A32_D192_ED03
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / 9_007_199_254_740_992.0
    }
}
