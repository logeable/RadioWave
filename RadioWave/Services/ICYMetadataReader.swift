import Foundation

/// Reads the first ICY metadata packet from a stream. The connection is short-lived
/// so metadata can be refreshed without downloading a second copy of the audio.
@MainActor
final class ICYMetadataReader {
    private var pollingTask: Task<Void, Never>?
    private var activeRequest: ICYMetadataRequest?
    private var generation = UUID()

    func start(url: URL, onTitle: @escaping (String) -> Void) {
        stop()
        let requestGeneration = generation

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, self.generation == requestGeneration {
                if let title = await self.fetchTitle(from: url, generation: requestGeneration),
                   !Task.isCancelled,
                   self.generation == requestGeneration {
                    onTitle(title)
                }

                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        pollingTask?.cancel()
        pollingTask = nil
        activeRequest?.cancel()
        activeRequest = nil
    }

    private func fetchTitle(from url: URL, generation requestGeneration: UUID) async -> String? {
        await withCheckedContinuation { continuation in
            let request = ICYMetadataRequest { [weak self] title in
                guard let self, self.generation == requestGeneration else {
                    continuation.resume(returning: nil)
                    return
                }
                self.activeRequest = nil
                continuation.resume(returning: title)
            }
            activeRequest = request
            request.start(url: url)
        }
    }
}

private final class ICYMetadataRequest: NSObject, URLSessionDataDelegate {
    private let onCompletion: (String?) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var metadataInterval: Int?
    private var audioBytesRemaining = 0
    private var metadataBytesRemaining: Int?
    private var metadataBuffer = Data()
    private var emptyPacketCount = 0
    private var isCompleted = false

    init(onCompletion: @escaping (String?) -> Void) {
        self.onCompletion = onCompletion
    }

    func start(url: URL) {
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("RadioWave/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
    }

    func cancel() {
        finish(with: nil)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let interval = response.value(forHTTPHeaderField: "icy-metaint").flatMap(Int.init),
              interval > 0 else {
            completionHandler(.cancel)
            finish(with: nil)
            return
        }

        metadataInterval = interval
        audioBytesRemaining = interval
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let metadataInterval, !isCompleted else { return }

        var offset = 0
        while offset < data.count {
            if let remaining = metadataBytesRemaining {
                let bytesToRead = min(remaining, data.count - offset)
                metadataBuffer.append(data[offset..<(offset + bytesToRead)])
                offset += bytesToRead
                metadataBytesRemaining = remaining - bytesToRead

                if metadataBytesRemaining == 0 {
                    let packet = String(data: metadataBuffer, encoding: .utf8)
                        ?? String(data: metadataBuffer, encoding: .isoLatin1)
                        ?? ""
                    if let title = Self.streamTitle(in: packet) {
                        finish(with: title)
                        return
                    }

                    emptyPacketCount += 1
                    guard emptyPacketCount < 4 else {
                        finish(with: nil)
                        return
                    }
                    metadataBuffer.removeAll(keepingCapacity: true)
                    metadataBytesRemaining = nil
                    audioBytesRemaining = metadataInterval
                }
                continue
            }

            if audioBytesRemaining > 0 {
                let bytesToSkip = min(audioBytesRemaining, data.count - offset)
                audioBytesRemaining -= bytesToSkip
                offset += bytesToSkip
                continue
            }

            let metadataLength = Int(data[offset]) * 16
            offset += 1
            if metadataLength == 0 {
                audioBytesRemaining = metadataInterval
            } else {
                metadataBuffer.removeAll(keepingCapacity: true)
                metadataBytesRemaining = metadataLength
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        finish(with: nil)
    }

    private func finish(with title: String?) {
        guard !isCompleted else { return }
        isCompleted = true
        let session = self.session
        self.session = nil
        task = nil
        onCompletion(title)
        session?.invalidateAndCancel()
    }

    private static func streamTitle(in packet: String) -> String? {
        guard let marker = packet.range(of: "StreamTitle='", options: .caseInsensitive) else { return nil }
        let value = packet[marker.upperBound...]
        let title = String(value.prefix { $0 != "'" })
            .replacingOccurrences(of: "\\'", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
