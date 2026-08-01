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

@Suite("LLM Cloud Client Tests")
struct LLMCloudClientTests {
    @Test("Google client validates configuration before transport")
    func googleClientValidatesConfiguration() {
        let transport = LLMHTTPTransport { _, _ in
            Issue.record("Transport should not start for invalid configuration")
        }
        let client = LLMCloudClient(transport: transport)

        let response = client.send(
            prompt: "prompt",
            configuration: .google(
                baseEndpoint: "  ",
                modelName: "gemini-test",
                apiKey: "test-key",
                thinkingLevel: .off,
                editActionCount: nil),
            timeout: 0.1)

        #expect(response.provider == "GoogleCloud")
        #expect(response.responseText == nil)
        #expect(response.fallbackReason == "emptyCloudEndpoint")
        #expect(response.elapsedMs == 0)
    }

    @Test("Google client sends request and extracts response text")
    func googleClientReturnsResponseText() {
        let responseData = Data(
            #"{"candidates":[{"content":{"parts":[{"text":"校正結果"}]}}]}"#.utf8)
        let transport = LLMHTTPTransport { request, completion in
            #expect(
                request.url?.absoluteString
                    == "https://example.com/v1/models/gemini-test:generateContent")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            completion(responseData, nil)
        }
        let client = LLMCloudClient(transport: transport)

        let response = client.send(
            prompt: "prompt",
            configuration: .google(
                baseEndpoint: "https://example.com/v1",
                modelName: "models/gemini-test",
                apiKey: "test-key",
                thinkingLevel: .low,
                editActionCount: nil),
            timeout: 0.1)

        #expect(response.provider == "GoogleCloud")
        #expect(response.responseText == "校正結果")
        #expect(response.fallbackReason == nil)
        #expect(response.errorDescription == nil)
    }

    @Test("OpenAI client preserves transport error")
    func openAIClientPreservesTransportError() {
        let transport = LLMHTTPTransport { _, completion in
            completion(nil, "network unavailable")
        }
        let client = LLMCloudClient(transport: transport)

        let response = client.send(
            prompt: "prompt",
            configuration: .openAI(
                endpoint: "https://example.com/v1/chat/completions",
                modelName: "model-test",
                apiKey: "test-key",
                usesEditActions: false),
            timeout: 0.1)

        #expect(response.provider == "OpenAICloud")
        #expect(response.responseText == nil)
        #expect(response.fallbackReason == "emptyResponse")
        #expect(response.errorDescription == "network unavailable")
    }

    @Test("OpenAI client preserves invalid JSON response")
    func openAIClientPreservesInvalidJSONResponse() {
        let transport = LLMHTTPTransport { _, completion in
            completion(Data("not-json".utf8), nil)
        }
        let client = LLMCloudClient(transport: transport)

        let response = client.send(
            prompt: "prompt",
            configuration: .openAI(
                endpoint: "https://example.com/v1/chat/completions",
                modelName: "model-test",
                apiKey: "test-key",
                usesEditActions: true),
            timeout: 0.1)

        #expect(response.responseText == nil)
        #expect(response.rawResponse == "not-json")
        #expect(response.fallbackReason == "invalidJSON")
    }
}
