import AVFoundation
import AudioToolbox
import Foundation

/// A direct HTTP audio player for continuous MP3 and AAC/ADTS radio streams.
/// The stream is parsed and decoded to PCM before it is sent to AVAudioEngine.
final class LivePCMRadioPlayer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct CompressedPacket {
        let data: Data
        let description: AudioStreamPacketDescription
    }

    private static let noInputAvailable = OSStatus(0x4E444154) // "NDAT"

    private let stationUUID: String
    private let codecHint: String
    private let meter: AudioLevelMeter
    private let onPlaybackStarted: @Sendable () -> Void
    private let onFailure: @Sendable (String, Bool) -> Void
    private let callbackQueue: OperationQueue

    // All mutable playback state below is confined to callbackQueue.
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var streamID: AudioFileStreamID?
    private var inputFormat = AudioStreamBasicDescription()
    private var converter: AudioConverterRef?
    private var outputDescription = AudioStreamBasicDescription()
    private var outputFormat: AVAudioFormat?
    private var pendingPackets: [CompressedPacket] = []
    private var converterInputData = Data()
    private var converterInputDescriptions: [AudioStreamPacketDescription] = []
    private var converterInputStorage: [UnsafeMutableRawPointer] = []
    private var converterDescriptionStorage: [(pointer: UnsafeMutablePointer<AudioStreamPacketDescription>, count: Int)] = []
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isPaused = false
    private var isStopped = false
    private var hasFailed = false
    private var hasProducedAudio = false
    private var didLogUnsupportedFormat = false
    private var didLogConverterBuffers = false

    init(
        stationUUID: String,
        codecHint: String,
        meter: AudioLevelMeter,
        onPlaybackStarted: @escaping @Sendable () -> Void,
        onFailure: @escaping @Sendable (String, Bool) -> Void
    ) {
        self.stationUUID = stationUUID
        self.codecHint = codecHint.lowercased()
        self.meter = meter
        self.onPlaybackStarted = onPlaybackStarted
        self.onFailure = onFailure
        callbackQueue = OperationQueue()
        callbackQueue.name = "com.logeable.RadioWave.live-pcm-stream"
        callbackQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func start(url: URL) {
        callbackQueue.addOperation { [self] in
            guard !isStopped else { return }
            openStreamParser()
            guard !hasFailed else { return }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 0
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: callbackQueue)
            self.session = session

            var request = URLRequest(url: url)
            request.setValue("RadioWave/1.0", forHTTPHeaderField: "User-Agent")
            // Do not request ICY in-band metadata: the existing metadata reader handles it
            // separately, while this parser needs a continuous encoded audio byte stream.
            let task = session.dataTask(with: request)
            self.task = task
            RadioWaveLog.info(
                "Started PCM stream decoder for station \(stationUUID), codecHint=\(codecHint)",
                category: "PlaybackPCM"
            )
            task.resume()
        }
    }

    func pause() {
        callbackQueue.addOperation { [self] in
            guard !isStopped, !isPaused else { return }
            isPaused = true
            task?.suspend()
            playerNode?.pause()
        }
    }

    func resume() {
        callbackQueue.addOperation { [self] in
            guard !isStopped, isPaused else { return }
            isPaused = false
            task?.resume()
            if hasProducedAudio {
                playerNode?.play()
            }
        }
    }

    func setVolume(_ volume: Float) {
        callbackQueue.addOperation { [self] in
            playerNode?.volume = volume
        }
    }

    func stop() {
        callbackQueue.addOperation { [self] in
            guard !isStopped else { return }
            isStopped = true
            task?.cancel()
            task = nil
            session?.invalidateAndCancel()
            session = nil
            if let streamID {
                AudioFileStreamClose(streamID)
                self.streamID = nil
            }
            if let converter {
                AudioConverterDispose(converter)
                self.converter = nil
            }
            releaseConverterInputStorage()
            engine?.stop()
            if let playerNode, engine?.attachedNodes.contains(playerNode) == true {
                engine?.detach(playerNode)
            }
            playerNode = nil
            engine = nil
            pendingPackets.removeAll(keepingCapacity: false)
            RadioWaveLog.debug("Stopped PCM stream decoder for station \(stationUUID)", category: "PlaybackPCM")
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !isStopped, !hasFailed else {
            completionHandler(.cancel)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            fail("流服务器没有返回 HTTP 响应。")
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            fail("流服务器返回 HTTP \(httpResponse.statusCode)。")
            completionHandler(.cancel)
            return
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        RadioWaveLog.info(
            "PCM stream response for station \(stationUUID): status=\(httpResponse.statusCode), contentType=\(contentType)",
            category: "PlaybackPCM"
        )
        let lowerContentType = contentType.lowercased()
        if lowerContentType.contains("mpegurl") || lowerContentType.contains("scpls") {
            fail("服务器返回的是播放列表，交由 AVPlayer 处理。")
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isStopped, !hasFailed, !isPaused,
              let streamID,
              data.count <= Int(UInt32.max) else { return }

        let status = data.withUnsafeBytes { bytes in
            AudioFileStreamParseBytes(
                streamID,
                UInt32(data.count),
                bytes.baseAddress,
                []
            )
        }
        guard status == noErr else {
            fail("音频流解析失败（OSStatus \(status)）。")
            return
        }
        decodeAvailablePackets()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !isStopped, !hasFailed, !isPaused else { return }
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            fail("音频流连接中断：\(RadioWaveLog.errorSummary(error))")
        } else if hasProducedAudio {
            fail("电台音频流已结束。")
        } else {
            fail("连接结束前没有收到可播放的音频。")
        }
    }

    // MARK: AudioFileStream callbacks

    private func openStreamParser() {
        let hint: AudioFileTypeID
        if codecHint.contains("aac") || codecHint.contains("aac+") {
            hint = kAudioFileAAC_ADTSType
        } else {
            hint = kAudioFileMP3Type
        }
        var openedStream: AudioFileStreamID?
        let status = AudioFileStreamOpen(
            Unmanaged.passUnretained(self).toOpaque(),
            Self.propertyListener,
            Self.packetsListener,
            hint,
            &openedStream
        )
        guard status == noErr, let openedStream else {
            fail("无法初始化 MP3/AAC 流解析器（OSStatus \(status)）。")
            return
        }
        streamID = openedStream
    }

    private static let propertyListener: AudioFileStream_PropertyListenerProc = {
        clientData, streamID, propertyID, _ in
        Unmanaged<LivePCMRadioPlayer>.fromOpaque(clientData)
            .takeUnretainedValue()
            .handleStreamProperty(streamID, propertyID: propertyID)
    }

    private static let packetsListener: AudioFileStream_PacketsProc = {
        clientData, numberBytes, numberPackets, inputData, descriptions in
        Unmanaged<LivePCMRadioPlayer>.fromOpaque(clientData)
            .takeUnretainedValue()
            .handlePackets(
                numberBytes: numberBytes,
                numberPackets: numberPackets,
                inputData: inputData,
                descriptions: descriptions
            )
    }

    private func handleStreamProperty(_ streamID: AudioFileStreamID, propertyID: AudioFileStreamPropertyID) {
        guard !isStopped, !hasFailed else { return }
        guard propertyID == kAudioFileStreamProperty_DataFormat
                || propertyID == kAudioFileStreamProperty_ReadyToProducePackets else { return }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_DataFormat, &size, &format)
        guard status == noErr else { return }
        guard format.mFormatID == kAudioFormatMPEGLayer3 || format.mFormatID == kAudioFormatMPEG4AAC else {
            if !didLogUnsupportedFormat {
                didLogUnsupportedFormat = true
                fail("此流不是当前直解码版本支持的 MP3/AAC 格式（\(fourCharacterCode(format.mFormatID))）。")
            }
            return
        }
        inputFormat = format
        configureConverterIfReady()
    }

    private func handlePackets(
        numberBytes: UInt32,
        numberPackets: UInt32,
        inputData: UnsafeRawPointer,
        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard !isStopped, !hasFailed else { return }
        let bytesCount = Int(numberBytes)
        let packetCount = Int(numberPackets)
        guard bytesCount > 0, packetCount > 0 else { return }

        if let descriptions {
            for index in 0..<packetCount {
                let description = descriptions[index]
                let start = Int(description.mStartOffset)
                let size = Int(description.mDataByteSize)
                guard start >= 0, size > 0, start + size <= bytesCount else { continue }
                let packetData = Data(bytes: inputData.advanced(by: start), count: size)
                pendingPackets.append(
                    CompressedPacket(
                        data: packetData,
                        description: AudioStreamPacketDescription(
                            mStartOffset: 0,
                            mVariableFramesInPacket: description.mVariableFramesInPacket,
                            mDataByteSize: description.mDataByteSize
                        )
                    )
                )
            }
        } else if inputFormat.mBytesPerPacket > 0 {
            let packetSize = Int(inputFormat.mBytesPerPacket)
            for index in 0..<packetCount {
                let start = index * packetSize
                guard start + packetSize <= bytesCount else { break }
                pendingPackets.append(
                    CompressedPacket(
                        data: Data(bytes: inputData.advanced(by: start), count: packetSize),
                        description: AudioStreamPacketDescription(
                            mStartOffset: 0,
                            mVariableFramesInPacket: 0,
                            mDataByteSize: UInt32(packetSize)
                        )
                    )
                )
            }
        }
    }

    private func configureConverterIfReady() {
        guard converter == nil,
              inputFormat.mSampleRate > 0,
              inputFormat.mChannelsPerFrame > 0 else { return }

        let channels = min(max(inputFormat.mChannelsPerFrame, 1), 2)
        var output = AudioStreamBasicDescription(
            mSampleRate: inputFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var createdConverter: AudioConverterRef?
        var sourceFormat = inputFormat
        let status = AudioConverterNew(&sourceFormat, &output, &createdConverter)
        guard status == noErr, let createdConverter else {
            fail("无法创建 MP3/AAC 解码器（OSStatus \(status)）。")
            return
        }

        if let streamID, let cookie = magicCookie(from: streamID) {
            let cookieStatus = cookie.withUnsafeBytes { bytes in
                AudioConverterSetProperty(
                    createdConverter,
                    kAudioConverterDecompressionMagicCookie,
                    UInt32(cookie.count),
                    bytes.baseAddress!
                )
            }
            if cookieStatus != noErr {
                RadioWaveLog.debug("No decoder cookie accepted for station \(stationUUID), OSStatus=\(cookieStatus)", category: "PlaybackPCM")
            }
        }

        guard let format = AVAudioFormat(streamDescription: &output) else {
            AudioConverterDispose(createdConverter)
            fail("无法创建 PCM 音频格式。")
            return
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        meter.prepare(format: output)
        playerNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak meter] buffer, _ in
            guard let meter else { return }
            meter.update(bufferList: buffer.mutableAudioBufferList, frameCount: Int(buffer.frameLength))
        }
        engine.prepare()
        do {
            try engine.start()
            playerNode.play()
        } catch {
            AudioConverterDispose(createdConverter)
            fail("无法启动 PCM 音频引擎：\(RadioWaveLog.errorSummary(error))")
            return
        }

        converter = createdConverter
        outputDescription = output
        outputFormat = format
        self.engine = engine
        self.playerNode = playerNode
        RadioWaveLog.info(
            "PCM decoder ready for station \(stationUUID): codec=\(fourCharacterCode(inputFormat.mFormatID)), sampleRate=\(Int(output.mSampleRate)), channels=\(channels)",
            category: "PlaybackPCM"
        )
    }

    private func magicCookie(from streamID: AudioFileStreamID) -> Data? {
        var size: UInt32 = 0
        guard AudioFileStreamGetPropertyInfo(streamID, kAudioFileStreamProperty_MagicCookieData, &size, nil) == noErr,
              size > 0 else { return nil }
        var data = Data(count: Int(size))
        let status = data.withUnsafeMutableBytes { bytes in
            AudioFileStreamGetProperty(streamID, kAudioFileStreamProperty_MagicCookieData, &size, bytes.baseAddress!)
        }
        return status == noErr ? data : nil
    }

    private func decodeAvailablePackets() {
        guard let converter, let outputFormat, let playerNode else { return }
        while !pendingPackets.isEmpty, !isStopped, !hasFailed, !isPaused {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                fail("无法分配 PCM 音频缓冲区。")
                return
            }
            // AudioConverter requires the output AudioBufferList's byte sizes
            // to describe available capacity on entry. AVAudioPCMBuffer keeps
            // those sizes synchronized with frameLength, so mark the capacity
            // available before calling the converter.
            buffer.frameLength = buffer.frameCapacity
            let outputBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let outputBytesPerBuffer = Int(buffer.frameCapacity) * MemoryLayout<Float>.size
            for index in outputBuffers.indices {
                var outputBuffer = outputBuffers[index]
                outputBuffer.mNumberChannels = 1
                outputBuffer.mDataByteSize = UInt32(outputBytesPerBuffer)
                outputBuffers[index] = outputBuffer
            }
            if !didLogConverterBuffers {
                RadioWaveLog.info(
                    "AudioConverter output before first call for station \(stationUUID): buffers=\(outputBuffers.count), capacityBytes=\(outputBuffers.map { $0.mDataByteSize }), channels=\(outputBuffers.map { $0.mNumberChannels })",
                    category: "PlaybackPCM"
                )
            }
            var outputPacketCount = UInt32(buffer.frameCapacity)
            let status = AudioConverterFillComplexBuffer(
                converter,
                Self.converterInput,
                Unmanaged.passUnretained(self).toOpaque(),
                &outputPacketCount,
                buffer.mutableAudioBufferList,
                nil
            )
            if !didLogConverterBuffers {
                didLogConverterBuffers = true
                let outputSizes = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                    .map { $0.mDataByteSize }
                RadioWaveLog.info(
                    "AudioConverter first call for station \(stationUUID): status=\(status), outputBuffers=\(outputBuffers.count), outputCapacityBytes=\(outputSizes), outputFrames=\(outputPacketCount), queuedPackets=\(pendingPackets.count)",
                    category: "PlaybackPCM"
                )
            }
            releaseConverterInputStorage()
            converterInputData.removeAll(keepingCapacity: true)
            converterInputDescriptions.removeAll(keepingCapacity: true)

            guard status == noErr || status == Self.noInputAvailable else {
                fail("MP3/AAC 解码失败（OSStatus \(status)）。")
                return
            }
            guard outputPacketCount > 0 else { break }

            buffer.frameLength = AVAudioFrameCount(outputPacketCount)
            playerNode.scheduleBuffer(buffer)
            if !hasProducedAudio {
                hasProducedAudio = true
                RadioWaveLog.info("PCM decoder produced first buffer for station \(stationUUID), frames=\(buffer.frameLength)", category: "PlaybackPCM")
                onPlaybackStarted()
            }
        }
    }

    private static let converterInput: AudioConverterComplexInputDataProc = {
        _, packetCount, audioBufferList, outputDescriptions, userData in
        guard let userData else { return noErr }
        let player = Unmanaged<LivePCMRadioPlayer>.fromOpaque(userData).takeUnretainedValue()
        guard !player.pendingPackets.isEmpty else {
            packetCount.pointee = 0
            if let outputDescriptions, outputDescriptions.pointee != nil {
                outputDescriptions.pointee = nil
            }
            return noInputAvailable
        }

        let requestedCount = max(1, Int(packetCount.pointee))
        let batchCount = min(requestedCount, player.pendingPackets.count)
        let packets = Array(player.pendingPackets.prefix(batchCount))
        player.pendingPackets.removeFirst(batchCount)

        player.converterInputData.removeAll(keepingCapacity: true)
        player.converterInputDescriptions.removeAll(keepingCapacity: true)
        for packet in packets {
            var description = packet.description
            description.mStartOffset = Int64(player.converterInputData.count)
            player.converterInputDescriptions.append(description)
            player.converterInputData.append(packet.data)
        }

        guard !player.converterInputData.isEmpty else {
            packetCount.pointee = 0
            return noInputAvailable
        }
        audioBufferList.pointee.mNumberBuffers = 1
        let inputStorage = UnsafeMutableRawPointer.allocate(
            byteCount: player.converterInputData.count,
            alignment: MemoryLayout<UInt32>.alignment
        )
        player.converterInputData.copyBytes(
            to: inputStorage.assumingMemoryBound(to: UInt8.self),
            count: player.converterInputData.count
        )
        player.converterInputStorage.append(inputStorage)

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        var buffer = buffers[0]
        // Compressed packets are supplied as one opaque buffer; zero is the
        // AudioToolbox convention for the input buffer's channel count.
        buffer.mNumberChannels = 0
        buffer.mDataByteSize = UInt32(player.converterInputData.count)
        buffer.mData = inputStorage
        buffers[0] = buffer
        packetCount.pointee = UInt32(batchCount)

        if outputDescriptions != nil, !player.converterInputDescriptions.isEmpty {
            let descriptions = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(
                capacity: player.converterInputDescriptions.count
            )
            for (index, description) in player.converterInputDescriptions.enumerated() {
                descriptions.advanced(by: index).initialize(to: description)
            }
            player.converterDescriptionStorage.append((descriptions, player.converterInputDescriptions.count))
            outputDescriptions!.pointee = descriptions
        }
        if !player.didLogConverterBuffers {
            RadioWaveLog.debug(
                "AudioConverter input callback for station \(player.stationUUID): packets=\(batchCount), bytes=\(player.converterInputData.count), buffers=\(audioBufferList.pointee.mNumberBuffers), channels=\(buffer.mNumberChannels), descriptions=\(player.converterInputDescriptions.count)",
                category: "PlaybackPCM"
            )
        }
        return noErr
    }

    private func releaseConverterInputStorage() {
        converterInputStorage.forEach { $0.deallocate() }
        converterInputStorage.removeAll(keepingCapacity: true)
        converterDescriptionStorage.forEach { storage in
            storage.pointer.deinitialize(count: storage.count)
            storage.pointer.deallocate()
        }
        converterDescriptionStorage.removeAll(keepingCapacity: true)
    }

    private func fail(_ message: String) {
        guard !isStopped, !hasFailed else { return }
        hasFailed = true
        RadioWaveLog.warning("PCM stream failed for station \(stationUUID): \(message)", category: "PlaybackPCM")
        task?.cancel()
        let hasProducedAudio = self.hasProducedAudio
        onFailure(message, hasProducedAudio)
    }

    private func fourCharacterCode(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? String(format: "0x%08x", code)
    }
}
