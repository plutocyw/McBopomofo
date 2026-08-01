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
import Testing

@testable import McBopomofo

@Suite("LLM HTTP Transport Tests")
struct LLMHTTPTransportTests {
    private func makeRequest() throws -> URLRequest {
        let url = try #require(URL(string: "https://example.com/request"))
        return URLRequest(url: url)
    }

    @Test("Transport returns response data")
    func transportReturnsResponseData() throws {
        let expectedData = Data("response".utf8)
        let transport = LLMHTTPTransport { _, completion in
            completion(expectedData, nil)
        }

        let result = transport.send(
            try makeRequest(),
            waitTimeout: 0.1)

        guard case .success(let data) = result else {
            Issue.record("Expected a successful transport result")
            return
        }
        #expect(data == expectedData)
    }

    @Test("Transport preserves empty response error")
    func transportPreservesEmptyResponseError() throws {
        let transport = LLMHTTPTransport { _, completion in
            completion(nil, "network unavailable")
        }

        let result = transport.send(
            try makeRequest(),
            waitTimeout: 0.1)

        guard case .emptyResponse(let errorDescription) = result else {
            Issue.record("Expected an empty response transport result")
            return
        }
        #expect(errorDescription == "network unavailable")
    }

    @Test("Transport returns timeout when request does not finish")
    func transportReturnsTimeout() throws {
        let transport = LLMHTTPTransport { _, _ in }

        let result = transport.send(
            try makeRequest(),
            waitTimeout: 0.001)

        guard case .timedOut = result else {
            Issue.record("Expected a timed out transport result")
            return
        }
    }
}
