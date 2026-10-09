import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Plays one app's sound through SAVISUL: a process tap mutes the app at its source and a private
/// aggregate device plays the tapped signal to the chosen output with its own gain.
final class TapEngine: @unchecked Sendable {
    enum Failure: Error {
        case tap(OSStatus), aggregate(OSStatus), ioProc(OSStatus), start(OSStatus)
    }

    static let ringSize = 2048

    let key: String
    let processes: [AudioObjectID]
    let outputUID: String
    let plays: Bool

    /// 0 target gain, 1 current gain, 2 peak since the last read.
    let control = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    let ring = UnsafeMutablePointer<Float>.allocate(capacity: TapEngine.ringSize)
    let head = UnsafeMutablePointer<Int>.allocate(capacity: 1)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.savisul.mixer.render", qos: .userInteractive)

    init(key: String, processes: [AudioObjectID], outputUID: String, gain: Float, plays: Bool = true) {
        self.key = key
        self.processes = processes
        self.outputUID = outputUID
        self.plays = plays
        control.initialize(repeating: 0, count: 4)
        control[0] = gain
        control[1] = gain
        ring.initialize(repeating: 0, count: TapEngine.ringSize)
        head.initialize(to: 0)
    }

    deinit {
        teardown()
        control.deallocate()
        ring.deallocate()
        head.deallocate()
    }

    var gain: Float {
        get { control[0] }
        set { control[0] = max(0, min(newValue, 4)) }
    }

    /// The loudest sample since the previous call.
    func takePeak() -> Float {
        let value = control[2]
        control[2] = 0
        return value
    }

    func start() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "SAVISUL"
        description.isPrivate = true
        description.muteBehavior = plays ? .mutedWhenTapped : .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw Failure.tap(status) }
        tapID = tap

        let inputOffset = CA.device(uid: outputUID).map { CA.streams($0, input: true) } ?? 0
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SAVISUL Mixer",
            kAudioAggregateDeviceUIDKey: "com.savisul.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate)
        guard status == noErr else {
            teardown()
            throw Failure.aggregate(status)
        }
        aggregateID = aggregate

        let control = control, ring = ring, head = head, plays = plays
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) { _, input, _, output, _ in
            TapEngine.render(input: input, output: output, inputOffset: inputOffset, control: control, ring: ring, head: head, plays: plays)
        }
        guard status == noErr else {
            teardown()
            throw Failure.ioProc(status)
        }
        status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            teardown()
            throw Failure.start(status)
        }
    }

    func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Keeps peaks under full scale without touching anything quieter than -1.4 dBFS.
    @inline(__always)
    private static func limit(_ sample: Float) -> Float {
        let level = abs(sample)
        guard level > 0.85 else { return sample }
        let over = (level - 0.85) / 0.15
        let shaped = 0.85 + 0.15 * (over / (1 + over))
        return sample < 0 ? -shaped : shaped
    }

    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, inputOffset: Int,
                               control: UnsafeMutablePointer<Float>, ring: UnsafeMutablePointer<Float>, head: UnsafeMutablePointer<Int>, plays: Bool) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard inputs.count > inputOffset, let firstData = inputs[inputOffset].mData else { return }
        let first = inputs[inputOffset]
        let channels = Int(max(first.mNumberChannels, 1))
        let left = firstData.assumingMemoryBound(to: Float.self)
        let stride: Int
        let frames: Int
        let right: UnsafeMutablePointer<Float>
        if channels >= 2 {
            stride = channels
            frames = Int(first.mDataByteSize) / (4 * channels)
            right = left + 1
        } else {
            stride = 1
            frames = Int(first.mDataByteSize) / 4
            if inputs.count > inputOffset + 1, let data = inputs[inputOffset + 1].mData {
                right = data.assumingMemoryBound(to: Float.self)
            } else {
                right = left
            }
        }
        let target = control[0]
        var gain = control[1]
        var peak = control[2]
        var index = head.pointee
        let mask = TapEngine.ringSize - 1

        var outLeft: UnsafeMutablePointer<Float>?
        var outRight: UnsafeMutablePointer<Float>?
        var outStride = 1
        var outFrames = frames
        if plays, let primary = outputs.first, let data = primary.mData {
            let count = Int(max(primary.mNumberChannels, 1))
            let base = data.assumingMemoryBound(to: Float.self)
            outFrames = Int(primary.mDataByteSize) / (4 * count)
            if count >= 2 {
                outLeft = base
                outRight = base + 1
                outStride = count
            } else if outputs.count >= 2, let second = outputs[1].mData {
                outLeft = base
                outRight = second.assumingMemoryBound(to: Float.self)
            } else {
                outLeft = base
            }
        }
        let count = min(frames, outFrames)
        for frame in 0..<count {
            gain += (target - gain) * 0.0012
            let l = limit(left[frame * stride] * gain)
            let r = limit(right[frame * stride] * gain)
            if let outLeft {
                if let outRight {
                    outLeft[frame * outStride] = l
                    outRight[frame * outStride] = r
                } else {
                    outLeft[frame] = (l + r) * 0.5
                }
            }
            let level = max(abs(l), abs(r))
            if level > peak { peak = level }
            ring[index] = (l + r) * 0.5
            index = (index + 1) & mask
        }
        control[1] = gain
        control[2] = peak
        head.pointee = index
    }
}

/// Turns the latest samples of a tap into a handful of bands for the equalizer bars.
final class SpectrumAnalyzer {
    private let size = 1024
    private let setup: vDSP_DFT_Setup?
    private var window: [Float]
    private var smoothed: [Float]
    private let edges: [Double] = [45, 110, 260, 600, 1400, 3200, 7000, 14000]

    init() {
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        smoothed = [Float](repeating: 0, count: 7)
    }

    deinit {
        if let setup { vDSP_DFT_DestroySetup(setup) }
    }

    func bands(ring: UnsafePointer<Float>, head: Int, sampleRate: Double = 48_000) -> [Float] {
        guard let setup else { return [] }
        var samples = [Float](repeating: 0, count: size)
        let mask = TapEngine.ringSize - 1
        for index in 0..<size {
            samples[index] = ring[(head - size + index + TapEngine.ringSize) & mask] * window[index]
        }
        let half = size / 2
        var realIn = [Float](repeating: 0, count: half)
        var imagIn = [Float](repeating: 0, count: half)
        for index in 0..<half {
            realIn[index] = samples[index * 2]
            imagIn[index] = samples[index * 2 + 1]
        }
        var realOut = [Float](repeating: 0, count: half)
        var imagOut = [Float](repeating: 0, count: half)
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)
        let binWidth = sampleRate / Double(size)
        var result: [Float] = []
        for band in 0..<(edges.count - 1) {
            let low = max(1, Int(edges[band] / binWidth))
            let high = min(half - 1, max(low + 1, Int(edges[band + 1] / binWidth)))
            var energy: Float = 0
            for bin in low..<high {
                energy += realOut[bin] * realOut[bin] + imagOut[bin] * imagOut[bin]
            }
            energy /= Float(high - low)
            let decibels = 10 * log10(max(energy, 1e-12))
            let value = min(max((decibels + 22) / 46, 0), 1)
            let previous = smoothed[band]
            smoothed[band] = value > previous ? previous + (value - previous) * 0.7 : previous + (value - previous) * 0.22
            result.append(smoothed[band])
        }
        return result
    }
}
