import AVFoundation
import MediaToolbox
import os

struct AudioBandLevels: Equatable {
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0

    static let zero = AudioBandLevels()
}

final class AudioLevelMeter: @unchecked Sendable {
    private let levels = OSAllocatedUnfairLock(initialState: AudioBandLevels.zero)
    private var isFloat = true
    private var bitsPerChannel: UInt32 = 32
    private var isNonInterleaved = false
    private var sampleRate = 44_100.0
    private var bassFilterStates: [Double] = []
    private var midFilterStates: [Double] = []

    var currentBands: AudioBandLevels {
        levels.withLock { $0 }
    }

    func reset() {
        levels.withLock { $0 = .zero }
    }

    func prepare(format: AudioStreamBasicDescription) {
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        bitsPerChannel = format.mBitsPerChannel
        isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        sampleRate = max(format.mSampleRate, 1)
        let channelCount = max(Int(format.mChannelsPerFrame), 1)
        bassFilterStates = Array(repeating: 0, count: channelCount)
        midFilterStates = Array(repeating: 0, count: channelCount)
    }

    func update(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }

        let bassAlpha = 1 - exp(-2 * Double.pi * 180 / sampleRate)
        let midAlpha = 1 - exp(-2 * Double.pi * 2_200 / sampleRate)
        var bassEnergy = 0.0
        var midEnergy = 0.0
        var trebleEnergy = 0.0
        var sampleCount = 0

        for (bufferIndex, buffer) in UnsafeMutableAudioBufferListPointer(bufferList).enumerated() {
            guard let data = buffer.mData else { continue }
            let channelCount = max(Int(buffer.mNumberChannels), 1)
            let bytesPerSample = Int(bitsPerChannel / 8)
            guard bytesPerSample > 0 else { continue }
            let samplesInBuffer = Int(buffer.mDataByteSize) / bytesPerSample
            let availableFrames = isNonInterleaved ? samplesInBuffer : samplesInBuffer / channelCount
            let framesToProcess = min(frameCount, availableFrames)

            for frame in 0..<framesToProcess {
                for channel in 0..<channelCount {
                    let stateIndex = isNonInterleaved ? bufferIndex + channel : channel
                    guard stateIndex < bassFilterStates.count,
                          stateIndex < midFilterStates.count else { continue }
                    let sampleIndex = isNonInterleaved ? frame : frame * channelCount + channel
                    let sample = sampleValue(in: data, at: sampleIndex)

                    bassFilterStates[stateIndex] += bassAlpha * (sample - bassFilterStates[stateIndex])
                    midFilterStates[stateIndex] += midAlpha * (sample - midFilterStates[stateIndex])
                    let bass = bassFilterStates[stateIndex]
                    let mid = midFilterStates[stateIndex] - bass
                    let treble = sample - midFilterStates[stateIndex]

                    bassEnergy += bass * bass
                    midEnergy += mid * mid
                    trebleEnergy += treble * treble
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return }
        let count = Double(sampleCount)
        let nextLevels = AudioBandLevels(
            bass: sqrt(bassEnergy / count),
            mid: sqrt(midEnergy / count),
            treble: sqrt(trebleEnergy / count)
        )
        levels.withLock { $0 = nextLevels }
    }

    private func sampleValue(in data: UnsafeMutableRawPointer, at index: Int) -> Double {
        switch (isFloat, bitsPerChannel) {
        case (true, 32):
            return Double(data.assumingMemoryBound(to: Float.self)[index])
        case (true, 64):
            return data.assumingMemoryBound(to: Double.self)[index]
        case (false, 16):
            return Double(data.assumingMemoryBound(to: Int16.self)[index]) / Double(Int16.max)
        case (false, 32):
            return Double(data.assumingMemoryBound(to: Int32.self)[index]) / Double(Int32.max)
        default:
            return 0
        }
    }
}

enum AudioLevelTap {
    static func makeMix(for track: AVAssetTrack, meter: AudioLevelMeter) throws -> AVAudioMix {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(meter).toOpaque(),
            init: { _, clientInfo, storageOut in
            storageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<AudioLevelMeter>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
            let meter = Unmanaged<AudioLevelMeter>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            meter.prepare(format: processingFormat.pointee)
            },
            unprepare: nil,
            process: { tap, requestedFrames, _, bufferList, framesOut, flagsOut in
            var sourceFlags: MTAudioProcessingTapFlags = 0
            let status = MTAudioProcessingTapGetSourceAudio(
                tap,
                requestedFrames,
                bufferList,
                &sourceFlags,
                nil,
                framesOut
            )
            flagsOut.pointee = sourceFlags

            guard status == noErr else {
                framesOut.pointee = 0
                return
            }

            let meter = Unmanaged<AudioLevelMeter>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            meter.update(bufferList: bufferList, frameCount: Int(framesOut.pointee))
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        let inputParameters = AVMutableAudioMixInputParameters(track: track)
        inputParameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [inputParameters]
        return mix
    }
}
