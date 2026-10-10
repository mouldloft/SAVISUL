import CoreGraphics
import Foundation
import Testing
@testable import SAVISUL

private func unit(_ values: [Float]) -> [Float] { FaceMath.unit(values)! }
private let owner = unit([1, 0.2, 0.1, 0])
private let ownerTurned = unit([1, 0.32, 0.05, 0.08])
private let stranger = unit([0.1, 1, 0, 0.3])

/// An eye `height` tall and one wide, as Vision's normalized landmark points.
private func eye(_ height: CGFloat) -> [CGPoint] {
    [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: height / 2), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: -height / 2)]
}

private func frame(_ print: [Float], eyes: Double? = 0.3) -> FaceFrame {
    FaceFrame(print: print, eyes: eyes, size: 0.3)
}

@Test func similarityIsTheCosineOfTwoUnitPrints() {
    #expect(unit([3, 4]) == [0.6, 0.8])
    #expect(abs(FaceMath.similarity(owner, owner) - 1) < 0.0001)
    #expect(abs(FaceMath.similarity(unit([1, 0]), unit([0, 1]))) < 0.0001)
    #expect(FaceMath.similarity(owner, [1, 0]) == -1)
    #expect(FaceMath.unit([0, 0]) == nil)
    #expect(FaceMath.best(owner, among: [stranger, ownerTurned]) == FaceMath.similarity(owner, ownerTurned))
}

@Test func eyesAreMeasuredByTheirShape() {
    #expect(abs((FaceMath.eyeOpenness([eye(0.3), eye(0.3)]) ?? 0) - 0.3) < 0.0001)
    #expect(abs((FaceMath.eyeOpenness([eye(0.3), nil]) ?? 0) - 0.3) < 0.0001)
    #expect(FaceMath.eyeOpenness([nil, nil]) == nil)
}

@Test func aBlinkIsShutForAMomentThenOpenAgain() {
    var tracker = BlinkTracker()
    for value in [0.30, 0.31, 0.29, 0.30, 0.08, 0.07, 0.30] { tracker.add(value) }
    #expect(tracker.blinked)
}

@Test func steadyEyesALongClosureOrNoEyesAreNoBlink() {
    var steady = BlinkTracker()
    for index in 0..<40 { steady.add(0.30 + Double(index % 3) * 0.01) }
    #expect(!steady.blinked)

    var shut = BlinkTracker()
    for value in [0.30, 0.31, 0.30] { shut.add(value) }
    for _ in 0..<20 { shut.add(0.07) }
    shut.add(0.30)
    #expect(!shut.blinked)

    var missing = BlinkTracker()
    for value: Double? in [0.30, nil, 0.30, nil, 0.30, nil, 0.30] { missing.add(value) }
    #expect(!missing.blinked)
}

@Test func aScanNeedsThreeMatchingFramesAndABlinkWhenAsked() {
    var withBlink = FaceMatch(prints: [owner, ownerTurned], needsBlink: true)
    for _ in 0..<5 { withBlink.add(frame(owner)) }
    #expect(withBlink.matched == 5)
    #expect(!withBlink.accepted)
    #expect(withBlink.waitingForBlink)
    // Frames read only for the eyes catch the blink without counting as faces.
    withBlink.add(FaceFrame(print: nil, eyes: 0.07, size: 0.3))
    withBlink.add(FaceFrame(print: nil, eyes: 0.30, size: 0.3))
    #expect(withBlink.seen == 5)
    #expect(withBlink.accepted)
    #expect(!withBlink.waitingForBlink)

    var noBlink = FaceMatch(prints: [owner], needsBlink: false)
    noBlink.add(frame(owner))
    noBlink.add(frame(ownerTurned))
    #expect(!noBlink.accepted)
    noBlink.add(frame(owner))
    #expect(noBlink.accepted)
}

@Test func theScanNobodyAskedForNeedsASteadyLook() {
    var steady = FaceMatch(prints: [owner], needsBlink: false, needed: 7)
    for _ in 0..<3 { steady.add(frame(owner)) }
    #expect(!steady.accepted)
    for _ in 0..<4 { steady.add(frame(owner)) }
    #expect(steady.accepted)
}

@Test func closedEyesDontUnlockEvenForTheOwner() {
    var scan = FaceMatch(prints: [owner], needsBlink: false)
    for _ in 0..<5 { scan.add(frame(owner, eyes: 0.05)) }
    #expect(scan.matched == 0)
    #expect(!scan.accepted)
    // It is the owner, only not looking, so it doesn't count against them.
    #expect(!scan.stranger)
    for _ in 0..<3 { scan.add(frame(owner, eyes: 0.3)) }
    #expect(scan.accepted)
}

@Test func onlyPrintsThatMatchTheSetupScanAreKeptForLearning() {
    let learnedElsewhere = unit([0.6, 0.8, 0, 0])
    var scan = FaceMatch(prints: [owner, learnedElsewhere], enrolled: 1, needsBlink: false)
    scan.add(frame(learnedElsewhere))
    #expect(scan.matched == 1)
    #expect(scan.strong.isEmpty)
    scan.add(frame(ownerTurned))
    #expect(scan.strong == [ownerTurned])
}

@Test func learningAddsNewLooksAndKeepsTheNewestSixteen() {
    let evening = unit([1, 0.5, 0.2, 0.3])
    #expect(FaceLearning.learn([], from: [ownerTurned], enrolled: [owner]).isEmpty)
    #expect(FaceLearning.learn([], from: [evening], enrolled: [owner]) == [evening])
    #expect(FaceLearning.learn([evening], from: [evening], enrolled: [owner]) == [evening])

    func axis(_ index: Int) -> [Float] { (0..<20).map { $0 == index ? 1 : 0 } }
    func turned(_ index: Int) -> [Float] { unit(zip(axis(0), axis(index)).map { 0.906 * $0 + 0.423 * $1 }) }
    let full = (1...FaceLearning.cap).map(turned)
    let next = FaceLearning.learn(full, from: [turned(FaceLearning.cap + 1)], enrolled: [axis(0)])
    #expect(next.count == FaceLearning.cap)
    #expect(next.first == turned(2))
    #expect(next.last == turned(FaceLearning.cap + 1))
}

@Test func someoneElseIsNeverAccepted() {
    var scan = FaceMatch(prints: [owner, ownerTurned], needsBlink: false)
    for index in 0..<6 { scan.add(frame(stranger, eyes: index == 3 ? 0.07 : 0.3)) }
    #expect(scan.matched == 0)
    #expect(!scan.accepted)
    #expect(scan.stranger)
    #expect(scan.best < FaceMatch.threshold)
}

@Test func theFaceScanKeepsOnePersonFromNewAnglesThenFromFartherBack() {
    // The first view straight on, then views turned about 25° in different directions.
    func axis(_ index: Int) -> [Float] { (0..<24).map { $0 == index ? 1 : 0 } }
    func turned(_ index: Int) -> [Float] { unit(zip(axis(0), axis(index)).map { 0.906 * $0 + 0.423 * $1 }) }
    var scan = FaceEnrollment()
    let first = scan.add(axis(0))
    let sameAgain = scan.add(axis(0))
    let someoneElse = scan.add(axis(23))
    let farTooSoon = scan.add(turned(20), far: true)
    #expect(first && !sameAgain && !someoneElse && !farTooSoon)
    var near = 0
    for index in 1..<FaceEnrollment.nearTarget where scan.add(turned(index)) { near += 1 }
    #expect(near == FaceEnrollment.nearTarget - 1)
    #expect(scan.nearDone && !scan.complete)
    let closeAfterDone = scan.add(turned(15))
    #expect(!closeAfterDone)
    var far = 0
    for index in 16..<(16 + FaceEnrollment.farTarget) where scan.add(turned(index), far: true) { far += 1 }
    #expect(far == FaceEnrollment.farTarget)
    #expect(scan.complete)
    #expect(scan.prints.count == FaceEnrollment.target)
    #expect(scan.progress == 1)
}

@Test func farFacesAreJudgedGentlyForOpenEyes() {
    var scan = FaceMatch(prints: [owner], needsBlink: false)
    // Eyes a few pixels wide read narrower from across the desk; they still count as open.
    for _ in 0..<3 { scan.add(FaceFrame(print: owner, eyes: 0.1, size: 0.07)) }
    #expect(scan.accepted)
    #expect(scan.typicalSize == 0.07)
    var close = FaceMatch(prints: [owner], needsBlink: false)
    for _ in 0..<3 { close.add(FaceFrame(print: owner, eyes: 0.1, size: 0.3)) }
    #expect(!close.accepted)
    #expect(close.notLooking == 3)
}

@Test func scansWaitForATouchAfterTheLockAndForARecentPassword() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var policy = UnlockPolicy(lockedAt: now, lastPasswordUnlock: now.addingTimeInterval(-3600))
    // The key that locked the Mac doesn't count; the next one does, once the grace second is over.
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(0.3), now: now.addingTimeInterval(1.2)))
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(0.6), now: now.addingTimeInterval(0.8)))
    #expect(policy.shouldScan(activityAt: now.addingTimeInterval(0.6), now: now.addingTimeInterval(1.1)))
    #expect(policy.shouldScan(activityAt: now.addingTimeInterval(1.5), now: now.addingTimeInterval(1.5)))

    policy.displayAsleep = true
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(9), now: now.addingTimeInterval(9)))
    policy.displayAsleep = false

    policy.failures = UnlockPolicy.strangersBeforePassword
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(9), now: now.addingTimeInterval(9)))
    policy.failures = 0

    policy.lastPasswordUnlock = now.addingTimeInterval(-7 * 24 * 3600)
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(9), now: now.addingTimeInterval(9)))
    policy.lastPasswordUnlock = nil
    #expect(!policy.shouldScan(activityAt: now.addingTimeInterval(9), now: now.addingTimeInterval(9)))

    let unlocked = UnlockPolicy(lockedAt: nil, lastPasswordUnlock: now)
    #expect(!unlocked.shouldScan(activityAt: now.addingTimeInterval(9), now: now.addingTimeInterval(9)))
}

@Test func thePasswordIsNeededAfterAWeekOrFiveStrangers() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(!UnlockPolicy(lastPasswordUnlock: now.addingTimeInterval(-24 * 3600)).passwordNeeded(now: now))
    #expect(UnlockPolicy(lastPasswordUnlock: now.addingTimeInterval(-157 * 3600)).passwordNeeded(now: now))
    #expect(UnlockPolicy(lastPasswordUnlock: nil).passwordNeeded(now: now))
    #expect(UnlockPolicy(lastPasswordUnlock: now, failures: 5).passwordNeeded(now: now))
}

@Test func thePasswordGoesInPiecesThatKeepCharactersWhole() {
    #expect(LockScreen.chunks("").isEmpty)
    let long = String(repeating: "a", count: 25)
    #expect(LockScreen.chunks(long).map(\.count) == [20, 5])
    let emoji = String(repeating: "b", count: 19) + "😀" + "c"
    let pieces = LockScreen.chunks(emoji)
    #expect(pieces.map(\.count) == [19, 3])
    #expect(String(utf16CodeUnits: pieces.flatMap { $0 }, count: pieces.reduce(0) { $0 + $1.count }) == emoji)
    #expect(LockScreen.chunks("пароль").first?.count == 6)
}
