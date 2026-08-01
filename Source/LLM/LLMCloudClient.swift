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

enum LLMCloudProviderConfiguration {
    case google(
        baseEndpoint: String,
        modelName: String,
        apiKey: String,
        thinkingLevel: LLMGoogleThinkingLevel,
        editActionCount: Int?
    )
    case openAI(
        endpoint: String,
        modelName: String,
        apiKey: String,
        usesEditActions: Bool
    )
}

struct LLMCloudClientResponse {
    let provider: String
    let responseText: String?
    let rawResponse: String?
    let elapsedMs: Int
    let fallbackReason: String?
    let errorDescription: String?
}

struct LLMCloudClient {
    static let live = LLMCloudClient(transport: .live)

    private let transport: LLMHTTPTransport

    init(transport: LLMHTTPTransport) {
        self.transport = transport
    }

    func send(
        prompt: String,
        configuration: LLMCloudProviderConfiguration,
        timeout: TimeInterval
    ) -> LLMCloudClientResponse {
        let startNs = DispatchTime.now().uptimeNanoseconds
        switch configuration {
        case .google(
            let baseEndpoint,
            let modelName,
            let apiKey,
            let thinkingLevel,
            let editActionCount
        ):
            return sendGoogle(
                prompt: prompt,
                baseEndpoint: baseEndpoint,
                modelName: modelName,
                apiKey: apiKey,
                thinkingLevel: thinkingLevel,
                editActionCount: editActionCount,
                timeout: timeout,
                startNs: startNs)
        case .openAI(
            let endpoint,
            let modelName,
            let apiKey,
            let usesEditActions
        ):
            return sendOpenAI(
                prompt: prompt,
                endpointText: endpoint,
                modelName: modelName,
                apiKey: apiKey,
                usesEditActions: usesEditActions,
                timeout: timeout,
                startNs: startNs)
        }
    }

    private func sendGoogle(
        prompt: String,
        baseEndpoint: String,
        modelName rawModelName: String,
        apiKey rawAPIKey: String,
        thinkingLevel: LLMGoogleThinkingLevel,
        editActionCount: Int?,
        timeout: TimeInterval,
        startNs: UInt64
    ) -> LLMCloudClientResponse {
        let provider = "GoogleCloud"
        let trimmedEndpoint = baseEndpoint.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            return failure(provider: provider, reason: "emptyCloudEndpoint")
        }
        let modelName = LLMCloudAPI.normalizedGoogleModelName(rawModelName)
        guard !modelName.isEmpty else {
            return failure(provider: provider, reason: "emptyCloudModelName")
        }
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return failure(provider: provider, reason: "emptyGoogleAPIKey")
        }
        guard
            let endpoint = LLMCloudAPI.googleGenerateContentURL(
                baseEndpoint: trimmedEndpoint,
                modelName: modelName)
        else {
            return failure(provider: provider, reason: "invalidCloudEndpoint")
        }
        guard
            let request = try? LLMCloudAPI.makeGoogleRequest(
                endpoint: endpoint,
                modelName: modelName,
                apiKey: apiKey,
                prompt: prompt,
                thinkingLevel: thinkingLevel,
                editActionCount: editActionCount,
                timeoutInterval: timeout)
        else {
            return failure(provider: provider, reason: "jsonEncodeFailed")
        }
        return send(
            request,
            provider: provider,
            timeout: timeout,
            startNs: startNs,
            responseText: LLMCloudAPI.googleResponseText)
    }

    private func sendOpenAI(
        prompt: String,
        endpointText rawEndpointText: String,
        modelName rawModelName: String,
        apiKey rawAPIKey: String,
        usesEditActions: Bool,
        timeout: TimeInterval,
        startNs: UInt64
    ) -> LLMCloudClientResponse {
        let provider = "OpenAICloud"
        let endpointText = rawEndpointText.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !endpointText.isEmpty else {
            return failure(provider: provider, reason: "emptyCloudEndpoint")
        }
        let modelName = rawModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            return failure(provider: provider, reason: "emptyCloudModelName")
        }
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            return failure(provider: provider, reason: "emptyOpenAIAPIKey")
        }
        guard let endpoint = URL(string: endpointText) else {
            return failure(provider: provider, reason: "invalidCloudEndpoint")
        }
        guard
            let request = try? LLMCloudAPI.makeOpenAIRequest(
                endpoint: endpoint,
                modelName: modelName,
                apiKey: apiKey,
                prompt: prompt,
                usesEditActions: usesEditActions,
                timeoutInterval: timeout)
        else {
            return failure(provider: provider, reason: "jsonEncodeFailed")
        }
        return send(
            request,
            provider: provider,
            timeout: timeout,
            startNs: startNs,
            responseText: LLMCloudAPI.openAIResponseText)
    }

    private func send(
        _ request: URLRequest,
        provider: String,
        timeout: TimeInterval,
        startNs: UInt64,
        responseText: (Data) -> String?
    ) -> LLMCloudClientResponse {
        let transportResult = transport.send(
            request,
            waitTimeout: timeout + 0.05)
        let elapsedMs = Int(
            (DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
        switch transportResult {
        case .timedOut:
            return failure(
                provider: provider,
                elapsedMs: elapsedMs,
                reason: "requestTimeout")
        case .emptyResponse(let errorDescription):
            return failure(
                provider: provider,
                elapsedMs: elapsedMs,
                reason: "emptyResponse",
                errorDescription: errorDescription)
        case .success(let data):
            let rawResponse = String(data: data, encoding: .utf8)
            guard let text = responseText(data) else {
                return failure(
                    provider: provider,
                    rawResponse: rawResponse,
                    elapsedMs: elapsedMs,
                    reason: "invalidJSON")
            }
            return LLMCloudClientResponse(
                provider: provider,
                responseText: text,
                rawResponse: nil,
                elapsedMs: elapsedMs,
                fallbackReason: nil,
                errorDescription: nil)
        }
    }

    private func failure(
        provider: String,
        rawResponse: String? = nil,
        elapsedMs: Int = 0,
        reason: String,
        errorDescription: String? = nil
    ) -> LLMCloudClientResponse {
        return LLMCloudClientResponse(
            provider: provider,
            responseText: nil,
            rawResponse: rawResponse,
            elapsedMs: elapsedMs,
            fallbackReason: reason,
            errorDescription: errorDescription)
    }
}
