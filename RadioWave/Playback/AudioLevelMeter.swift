import AVFoundation
import MediaToolbox
import os

final class AudioLevelMeter: @unchecked Sendable {
    private let level = OSAllocatedUnfairLock(initialState: Float.zero)
    private var isFloat = true
    private var bitsPerChannel: UInt32 = 32

    var currentLevel: Float {
        level.withLock { $0 }
    }

    func reset() {
        level.withLock { $0 = 0 }
    }

    func prepare(format: AudioStreamBasicDescription) {
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        bitsPerChannel = format.mBitsPerChannel
    }

    func update(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }

        var sumOfSquares = 0.0
        var sampleCount = 0

        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let data = buffer.mData else { continue }
            switch (isFloat, bitsPerChannel) {
            case (true, 32):
                let samples = data.assumingMemoryBound(to: Float.self)
                let count = min(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size, frameCount * Int(buffer.mNumberChannels))
                for index in 0..<count {
                    let sample = Double(samples[index])
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case (true, 64):
                let samples = data.assumingMemoryBound(to: Double.self)
                let count = min(Int(buffer.mDataByteSize) / MemoryLayout<Double>.size, frameCount * Int(buffer.mNumberChannels))
                for index in 0..<count {
                    let sample = samples[index]
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case (false, 16):
                let samples = data.assumingMemoryBound(to: Int16.self)
                let count = min(Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size, frameCount * Int(buffer.mNumberChannels))
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int16.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            case (false, 32):
                let samples = data.assumingMemoryBound(to: Int32.self)
                let count = min(Int(buffer.mDataByteSize) / MemoryLayout<Int32>.size, frameCount * Int(buffer.mNumberChannels))
                for index in 0..<count {
                    let sample = Double(samples[index]) / Double(Int32.max)
                    sumOfSquares += sample * sample
                }
                sampleCount += count
            default:
                continue
            }
        }

        let rms = sampleCount > 0 ? Float((sumOfSquares / Double(sampleCount)).squareRoot()) : 0
        level.withLock { $0 = min(max(rms, 0), 1) }
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
