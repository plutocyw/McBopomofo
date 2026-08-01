// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Foundation

enum LLMHTTPTransportResult {
    case success(Data)
    case emptyResponse(errorDescription: String?)
    case timedOut
}

struct LLMHTTPTransport: Sendable {
    typealias Completion = @Sendable (Data?, String?) -> Void
    typealias RequestStarter = @Sendable (URLRequest, @escaping Completion) -> Void

    private final class ResponseBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private var errorDescription: String?

        func store(data: Data?, errorDescription: String?) {
            lock.lock()
            self.data = data
            self.errorDescription = errorDescription
            lock.unlock()
        }

        func snapshot() -> (data: Data?, errorDescription: String?) {
            lock.lock()
            defer { lock.unlock() }
            return (data, errorDescription)
        }
    }

    static let live = LLMHTTPTransport { request, completion in
        URLSession.shared.dataTask(with: request) { data, _, error in
            completion(data, error.map { "\($0)" })
        }.resume()
    }

    private let startRequest: RequestStarter

    init(startRequest: @escaping RequestStarter) {
        self.startRequest = startRequest
    }

    func send(
        _ request: URLRequest,
        waitTimeout: TimeInterval
    ) -> LLMHTTPTransportResult {
        let semaphore = DispatchSemaphore(value: 0)
        let responseBox = ResponseBox()
        startRequest(request) { data, errorDescription in
            responseBox.store(
                data: data,
                errorDescription: errorDescription)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + waitTimeout) == .timedOut {
            return .timedOut
        }
        let response = responseBox.snapshot()
        guard let data = response.data else {
            return .emptyResponse(
                errorDescription: response.errorDescription)
        }
        return .success(data)
    }
}
